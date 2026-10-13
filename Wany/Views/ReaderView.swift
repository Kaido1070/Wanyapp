import SwiftUI
import ImageIO

struct ReaderGeometry: Equatable { var y: CGFloat = 0; var height: CGFloat = 1 }
struct ReaderGeometryKey: PreferenceKey {
    static var defaultValue = ReaderGeometry()
    static func reduce(value: inout ReaderGeometry,nextValue:()->ReaderGeometry) { value = nextValue() }
}
struct ReaderPage: View {
    @EnvironmentObject var downloads: Downloads
    let payload: ChapterPayload; let index: Int; let width: CGFloat
    @State private var image: UIImage?
    @State private var failedDecode = false
    var ratio: CGFloat {
        if let image { return image.size.height / max(1,image.size.width) }
        if let meta = payload.pageMeta, index < meta.count, let w = meta[index].width, let h = meta[index].height, w > 0 { return h / w }
        return 1.6
    }
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else {
                VStack(spacing:15) {
                    Image(systemName:downloads.online ? "photo" : "wifi.slash").font(.title)
                    Text("الصورة \(index+1) غير محملة").font(.caption)
                    if downloads.online { Button("إعادة المحاولة") { downloads.retryChapter(payload) } }
                }.frame(maxWidth:.infinity).frame(height:width*ratio).foregroundStyle(.secondary).background(Theme.surface)
            }
        }.frame(width:width).task(id:downloads.revision) { await load() }
    }
    func load() async {
        guard image == nil, let url = downloads.pageURL(payload,index:index) else { return }
        let loaded = await Task.detached(priority:.userInitiated) { () -> Data? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] else { return nil }
            let w = (properties[kCGImagePropertyPixelWidth] as? Double) ?? 1000
            let h = (properties[kCGImagePropertyPixelHeight] as? Double) ?? 1600
            let maxPixel = min(16000,max(w,h) * min(1,1200/max(w,1)))
            let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixel,kCGImageSourceCreateThumbnailWithTransform:true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { return nil }
            return UIImage(cgImage:cg).pngData()
        }.value
        if let loaded { image = UIImage(data:loaded) } else { failedDecode = true }
    }
}
struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @Environment(\.dismiss) var dismiss
    let story: Story
    let chapter: Chapter
    @State private var payload: ChapterPayload?
    @State private var error: String?
    @State private var currentPage: Int?
    @State private var interacted = false
    @State private var controls = true
    @State private var lastOffset: CGFloat = 0
    @State private var lastSave: CGFloat = -100
    @State private var percent: CGFloat = 0
    @State private var nextChapter: Chapter?
    var body: some View {
        GeometryReader { screen in
            ZStack(alignment:.top) {
                Color.black.ignoresSafeArea()
                if let payload {
                    ScrollView {
                        LazyVStack(spacing:0) {
                            ForEach(payload.pages.indices,id:\.self) { index in ReaderPage(payload:payload,index:index,width:screen.size.width).id(index) }
                            VStack(spacing:16) {
                                Text("نهاية الفصل \(chapterNumber(payload.number))").font(.headline)
                                if let next = payload.next { Button("الفصل التالي \(chapterNumber(next))") { nextChapter = story.chapters?.first(where:{$0.number == next}) ?? Chapter(number:next,title:"الفصل \(chapterNumber(next))") }.buttonStyle(.borderedProminent) }
                                Button("العودة للفصول") { dismiss() }
                            }.padding(.vertical,36).frame(maxWidth:.infinity)
                        }.scrollTargetLayout().background(GeometryReader { proxy in Color.clear.preference(key:ReaderGeometryKey.self,value:ReaderGeometry(y:proxy.frame(in:.named("reader")).minY,height:proxy.size.height)) })
                    }.coordinateSpace(name:"reader").scrollPosition(id:$currentPage,anchor:.top)
                        .simultaneousGesture(DragGesture(minimumDistance:3).onChanged { _ in interacted = true })
                        .onPreferenceChange(ReaderGeometryKey.self) { geometry in
                            let offset = max(0,-geometry.y)
                            let delta = offset-lastOffset
                            if abs(delta) > 8 { withAnimation(.easeInOut(duration:0.22)) { controls = delta < 0 || offset < 80 }; lastOffset = offset }
                            let actual = min(100,max(0,offset / max(1,geometry.height-screen.size.height) * 100))
                            percent = actual
                            if interacted, abs(actual-lastSave) >= 0.5 {
                                // Never mark completion while the ending images are missing.
                                let allImages = payload.pages.indices.allSatisfy { downloads.pageURL(payload,index:$0) != nil }
                                store.record(payload,page:currentPage ?? 0,percent:Double(allImages ? actual : min(actual,97)))
                                lastSave = actual
                            }
                        }
                        .onAppear { currentPage = restoredPage(payload); store.chromeHidden = true }
                } else if let error { VStack(spacing:20) { EmptyState(icon:"wifi.slash",title:"تعذر فتح الفصل",detail:error); Button("إعادة المحاولة") { Task { await load() } }; Button("العودة") { dismiss() } }.padding() }
                else { ProgressView("تجهيز الفصل…").frame(maxWidth:.infinity,maxHeight:.infinity) }
                HStack {
                    Button { dismiss() } label: { Image(systemName:"chevron.right").padding(10) }
                    VStack(alignment:.leading,spacing:3) { Text(chapter.title).font(.subheadline.bold()).lineLimit(1); if let payload { Text("\((currentPage ?? 0)+1) / \(payload.pages.count)").font(.caption).foregroundStyle(.secondary) } }
                    Spacer()
                    if let payload { Button { downloads.retryChapter(payload) } label: { Label("الصور الناقصة",systemImage:"arrow.clockwise").font(.caption) }.disabled(!store.online) }
                }.padding(10).background(.ultraThinMaterial).offset(y:controls ? 0 : -150)
                if !controls { Button { withAnimation { controls = true } } label: { Image(systemName:"ellipsis").padding(10).background(.ultraThinMaterial,in:Capsule()) }.frame(maxWidth:.infinity,alignment:.trailing).padding(8) }
            }
        }.toolbar(.hidden,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .navigationDestination(item:$nextChapter) { next in ReaderView(story:story,chapter:next) }
        .task { await load() }
        .onDisappear {
            store.chromeHidden = false
            if let payload, interacted { let complete = payload.pages.indices.allSatisfy { downloads.pageURL(payload,index:$0) != nil }; store.record(payload,page:currentPage ?? 0,percent:Double(complete ? percent : min(percent,97))) }
            Task { await store.syncProgress() }
        }
    }
    func restoredPage(_ payload: ChapterPayload) -> Int {
        if let p = store.state?.positions[payload.id] { return min(max(0,p),payload.pages.count-1) }
        let progress = store.state?.data.progress[payload.id]?.percent ?? 0
        return min(payload.pages.count-1,max(0,Int(progress/100*Double(payload.pages.count))))
    }
    func load() async {
        error = nil
        guard let owner = store.state?.user.id else { return }
        let id = story.key+":"+chapter.id
        if let saved = Disk.read(ChapterPayload.self,owner:owner,name:Disk.chapterName(id)) {
            payload = saved; currentPage = restoredPage(saved)
            if store.online { downloads.usePayload(saved) }
            return
        }
        guard store.online else { error = "هذا الفصل غير محمل. اتصل بالإنترنت لتنزيله؛ بقية الفصول المحملة متاحة من التنزيلات."; return }
        do {
            let value = try await API.shared.chapter(story.key,chapter)
            guard store.state?.user.id == owner else { return }
            payload = value; currentPage = restoredPage(value); downloads.usePayload(value); store.remember(value.item)
        } catch { self.error = error.localizedDescription }
    }
}
