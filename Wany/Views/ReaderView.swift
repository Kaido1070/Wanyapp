import SwiftUI
import ImageIO

struct ReaderGeometry: Equatable { var y: CGFloat = 0; var height: CGFloat = 1 }
struct ReaderGeometryKey: PreferenceKey {
    static var defaultValue = ReaderGeometry()
    static func reduce(value: inout ReaderGeometry,nextValue:()->ReaderGeometry) { value = nextValue() }
}
struct ReaderPageFramesKey: PreferenceKey {
    static var defaultValue: [Int:CGRect] = [:]
    static func reduce(value: inout [Int:CGRect], nextValue: () -> [Int:CGRect]) { value.merge(nextValue(),uniquingKeysWith: { _,new in new }) }
}
struct ReaderPage: View {
    @EnvironmentObject var downloads: Downloads
    let payload: ChapterPayload; let index: Int; let width: CGFloat
    var knownRatio: CGFloat? = nil
    @State private var image: UIImage?
    @State private var failedDecode = false
    var ratio: CGFloat {
        if let knownRatio { return knownRatio }
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
        }.frame(width:width,height:width*ratio).task(id:downloads.revision) { await load() }
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
        if let loaded { image = UIImage(data:loaded) } else { failedDecode = true; downloads.invalidatePage(payload,index:index) }
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
    @State private var zoom: CGFloat = 1
    @State private var pinching = false
    @State private var currentPage: Int?
    @State private var interacted = false
    @State private var controls = true
    @State private var scrollDirection = ReaderScrollDirection(revealDistance:288)
    @State private var activeChapter: Chapter?
    @State private var choosingChapter = false
    @State private var chapterQuery = ""
    @State private var headerHeight: CGFloat = 160
    @State private var saveTask: Task<Void,Never>?
    @State private var pageRatios: [Int:CGFloat] = [:]
    @State private var percent: CGFloat = 0
    var readingChapter: Chapter { activeChapter ?? chapter }
    var chapters: [Chapter] { (store.stories[story.key] ?? story).orderedChapters }
    var previousChapter: Chapter? { neighbor(forward:false) }
    var nextChapter: Chapter? { neighbor(forward:true) }
    var body: some View {
        GeometryReader { screen in
            ZStack(alignment:.top) {
                Color.black.ignoresSafeArea()
                if let payload {
                    ScrollViewReader { scroll in
                    ScrollView([.vertical,.horizontal]) {
                        LazyVStack(spacing:0) {
                            ForEach(payload.pages.indices,id:\.self) { index in ReaderPage(payload:payload,index:index,width:screen.size.width * zoom,knownRatio:pageRatios[index]).id(index)
                                .background(GeometryReader { page in Color.clear.preference(key:ReaderPageFramesKey.self,value:[index:page.frame(in:.named("reader"))]) }) }
                            VStack(spacing:16) {
                                Text("نهاية الفصل \(chapterNumber(payload.number))").font(.headline)
                                if let next = nextChapter { Button("الفصل التالي \(next.id)") { open(next) }.buttonStyle(.borderedProminent) }
                                Button("العودة للفصول") { dismiss() }
                            }.padding(.vertical,36).frame(maxWidth:.infinity)
                        }
                        .frame(width:screen.size.width * zoom)
                        .background(ReaderPinchZoom(scale:$zoom,isPinching:$pinching,baseWidth:screen.size.width))
                        .background(ReaderScrollObserver { offset, moving in
                            if !pinching, let visible = scrollDirection.update(offset:offset,userScrolling:moving), visible != controls {
                                withAnimation(.easeInOut(duration:0.22)) { controls = visible }
                            }
                        })
                        .background(GeometryReader { proxy in Color.clear.preference(key:ReaderGeometryKey.self,value:ReaderGeometry(y:proxy.frame(in:.named("reader")).minY,height:proxy.size.height)) })
                    }.id(payload.id).coordinateSpace(name:"reader")
                        .environment(\.layoutDirection,.leftToRight)
                        .transaction { $0.animation = nil }
                        .scrollBounceBehavior(.basedOnSize,axes:.horizontal)
                        .simultaneousGesture(DragGesture(minimumDistance:3).onChanged { _ in interacted = true })
                        .onPreferenceChange(ReaderGeometryKey.self) { geometry in
                            let offset = max(0,-geometry.y)
                            let actual = min(100,max(0,offset / max(1,geometry.height-screen.size.height) * 100))
                            percent = actual
                            if interacted && !pinching { scheduleSave() }
                        }
                        .onPreferenceChange(ReaderPageFramesKey.self) { frames in
                            if let page = ReaderPosition.visiblePage(frames:frames), page != currentPage { currentPage = page }
                        }
                        .onAppear {
                            let page = restoredPage(payload); currentPage = page
                            scroll.scrollTo(page,anchor:.top)
                            store.chromeHidden = true
                        }
                    }.id(payload.id)
                } else if let error { VStack(spacing:20) { EmptyState(icon:"wifi.slash",title:"تعذر فتح الفصل",detail:error); Button("إعادة المحاولة") { Task { await load() } }; Button("العودة") { dismiss() } }.padding() }
                else { ProgressView("تجهيز الفصل…").frame(maxWidth:.infinity,maxHeight:.infinity) }
                VStack(spacing:10) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName:"chevron.right").padding(10) }.accessibilityLabel("العودة للفصول")
                        VStack(alignment:.leading,spacing:3) {
                            Text(readingChapter.title).font(.subheadline.bold()).lineLimit(1)
                            if let payload { Text("\((currentPage ?? 0)+1) / \(payload.pages.count)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength:8)
                        if let payload { Button { downloads.retryChapter(payload) } label: { Label("الصور الناقصة",systemImage:"arrow.clockwise").font(.caption) }.disabled(!store.online) }
                    }
                    HStack(spacing:12) {
                        Button { if let previous = previousChapter { open(previous) } } label: { Label("السابق",systemImage:"chevron.right") }.disabled(previousChapter == nil)
                        Spacer(minLength:0)
                        Button { chapterQuery = ""; choosingChapter = true } label: { Label("اختيار الفصل",systemImage:"list.bullet") }
                        Spacer(minLength:0)
                        Button { if let next = nextChapter { open(next) } } label: { Label("التالي",systemImage:"chevron.left") }.disabled(nextChapter == nil)
                    }.font(.subheadline).padding(.horizontal,8)
                }.padding(10).background(.ultraThinMaterial)
                    .background(GeometryReader { proxy in Color.clear.preference(key:ReaderHeaderHeightKey.self,value:proxy.size.height) })
                    .onPreferenceChange(ReaderHeaderHeightKey.self) { headerHeight = $0 }
                    .offset(y:controls ? 0 : -(headerHeight + screen.safeAreaInsets.top + 12))
                    .opacity(controls ? 1 : 0).allowsHitTesting(controls)
            }
        }.toolbar(.hidden,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .sheet(isPresented:$choosingChapter) { chapterPicker }
        .task(id:readingChapter.id) { await load() }
        .task {
            if store.online, let full = try? await API.shared.fullSeries(story.key), !Task.isCancelled { store.remember(full) }
        }
        .onAppear { store.readerActive = true; store.chromeHidden = true }
        .onDisappear {
            saveTask?.cancel()
            store.readerActive = false; store.chromeHidden = false
            if let payload { downloads.leaveChapter(payload.id) }
            savePosition()
            Task { await store.syncProgress() }
        }
    }
    var chapterPicker: some View {
        NavigationStack {
            List {
                if chapters.isEmpty { Text("قائمة الفصول غير متاحة حاليًا. اتصل بالإنترنت لتحديثها.").foregroundStyle(.secondary) }
                ForEach(chapters.filter { chapterQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(chapterQuery) || $0.id.contains(chapterQuery) }) { item in
                    Button { choosingChapter = false; open(item) } label: {
                        HStack {
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            if item.id == readingChapter.id { Image(systemName:"book.fill").foregroundStyle(Theme.accent) }
                            if downloads.savedJobs.first(where:{$0.id == story.key})?.chapters.first(where:{$0.id == item.id})?.complete == true { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                        }
                    }
                }
            }.searchable(text:$chapterQuery,prompt:"رقم الفصل أو عنوانه")
                .navigationTitle("اختيار الفصل").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("إغلاق") { choosingChapter = false } } }
        }.environment(\.layoutDirection,.rightToLeft)
    }
    func neighbor(forward: Bool) -> Chapter? {
        if let index = chapters.firstIndex(where:{$0.id == readingChapter.id}) {
            let target = index + (forward ? 1 : -1)
            return chapters.indices.contains(target) ? chapters[target] : nil
        }
        guard let number = forward ? payload?.next : payload?.previous else { return nil }
        return chapters.first(where:{$0.number == number}) ?? Chapter(number:number,title:"الفصل \(chapterNumber(number))")
    }
    func scheduleSave() {
        saveTask?.cancel()
        let id = payload?.id
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for:.milliseconds(400)) } catch { return }
            guard !Task.isCancelled, payload?.id == id else { return }
            savePosition()
        }
    }
    func cachedRatios(_ value: ChapterPayload, owner: String) -> [Int:CGFloat] {
        var result: [Int:CGFloat] = [:]
        for index in value.pages.indices {
            if let metadata = value.pageMeta, metadata.indices.contains(index), let w = metadata[index].width, let h = metadata[index].height, w > 0, h > 0 { result[index] = CGFloat(h/w) }
            let file = Disk.file(owner,Disk.imageName(value.id,index))
            if let source = CGImageSourceCreateWithURL(file as CFURL,nil), let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
               let w = properties[kCGImagePropertyPixelWidth] as? NSNumber, let h = properties[kCGImagePropertyPixelHeight] as? NSNumber, w.doubleValue > 0, h.doubleValue > 0 {
                result[index] = CGFloat(h.doubleValue/w.doubleValue)
            }
        }
        return result
    }
    func savePosition() {
        guard let payload, interacted else { return }
        let complete = payload.pages.indices.allSatisfy { downloads.pageURL(payload,index:$0) != nil }
        store.record(payload,page:currentPage ?? 0,percent:Double(complete ? percent : min(percent,97)))
    }
    func open(_ target: Chapter) {
        guard target.id != readingChapter.id else { return }
        saveTask?.cancel(); savePosition()
        if let payload { downloads.leaveChapter(payload.id) }
        payload = nil; error = nil; currentPage = nil; interacted = false
        zoom = 1; pinching = false; percent = 0; pageRatios = [:]; scrollDirection = ReaderScrollDirection(revealDistance:288); controls = true
        activeChapter = target
        Task { await store.syncProgress() }
    }
    func restoredPage(_ payload: ChapterPayload) -> Int {
        if let p = store.state?.positions[payload.id] { return min(max(0,p),payload.pages.count-1) }
        let progress = store.state?.data.progress[payload.id]?.percent ?? 0
        return min(payload.pages.count-1,max(0,Int(progress/100*Double(payload.pages.count))))
    }
    func load() async {
        error = nil
        guard let owner = store.state?.user.id else { return }
        let requested = readingChapter
        let id = story.key+":"+requested.id
        if let saved = Disk.read(ChapterPayload.self,owner:owner,name:Disk.chapterName(id)) {
            pageRatios = cachedRatios(saved,owner:owner)
            payload = saved; currentPage = restoredPage(saved)
            downloads.usePayload(saved)
            return
        }
        guard store.online else { error = "هذا الفصل غير محمل. اتصل بالإنترنت لتنزيله؛ بقية الفصول المحملة متاحة من التنزيلات."; return }
        do {
            let value = try await API.shared.chapter(story.key,requested)
            guard !Task.isCancelled, readingChapter.id == requested.id, store.state?.user.id == owner else { return }
            pageRatios = cachedRatios(value,owner:owner)
            payload = value; currentPage = restoredPage(value); downloads.usePayload(value); store.remember(value.item)
        } catch { if !Task.isCancelled, readingChapter.id == requested.id { self.error = error.localizedDescription } }
    }
}

private struct ReaderHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
