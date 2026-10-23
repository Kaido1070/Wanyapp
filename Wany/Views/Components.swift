import SwiftUI
import UIKit
import ImageIO

enum Theme {
    static let background = Color(red:23/255,green:25/255,blue:27/255)
    static let surface = Color(red:32/255,green:34/255,blue:37/255)
    static let accent = Color(red:219/255,green:185/255,blue:145/255)
}
struct WanyCard: ViewModifier {
    func body(content: Content) -> some View { content.padding(16).ranyGlass(radius:22) }
}
extension View { func card() -> some View { modifier(WanyCard()) } }
struct WanyScroll<Content: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.ranyScrollToTop) private var scrollToTop
    @State private var scrollDirection = ReaderScrollDirection(revealDistance:192)
    @State private var chromeSettlesAt = Date.distantPast
    let content: Content
    init(@ViewBuilder content: ()->Content) { self.content = content() }
    var body: some View {
        ScrollView {
            // Lazy: long feeds, downloads and lists only build the rows near the viewport.
            LazyVStack(spacing:18) { content }
                .padding(.horizontal,18)
                .padding(.bottom,32)
                .background(ReaderScrollObserver(scrollToTop:scrollToTop) { offset, moving in
                    store.setScrolling(moving)
                    // While the bar animates, inset changes move the offset; ignore them.
                    guard Date() >= chromeSettlesAt else { return }
                    if let visible = scrollDirection.update(offset:offset,userScrolling:moving), store.chromeHidden == visible {
                        chromeSettlesAt = Date().addingTimeInterval(0.45)
                        withAnimation(.easeInOut(duration:0.22)) { store.chromeHidden = !visible }
                    }
                })
        }
        // The native tab bar slides away while reading down and returns on a deliberate scroll up.
        .toolbar(store.chromeHidden ? .hidden : .visible,for:.tabBar)
        .onAppear {
            scrollDirection = ReaderScrollDirection(revealDistance:192)
            store.chromeHidden = false
        }
        .onDisappear { store.setScrolling(false) }
        .background(Color.clear).ranyClearNavigation()
    }
}
// Covers are decoded off the main thread as thumbnails sized to their slot and kept
// in memory. The slot keeps its size while loading, so nothing jumps.
enum RanyCoverCache {
    private static let cache: NSCache<NSString,UIImage> = { let cache = NSCache<NSString,UIImage>(); cache.countLimit = 400; return cache }()
    static func cached(_ key: String) -> UIImage? { cache.object(forKey:key as NSString) }
    static func load(_ url: URL, key: String, maxPixel: CGFloat) async -> UIImage? {
        if let image = cached(key) { return image }
        let image = await Task.detached(priority:.userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
                    kCGImageSourceShouldCacheImmediately:true,kCGImageSourceThumbnailMaxPixelSize:max(1,maxPixel)] as CFDictionary) else { return nil }
            return UIImage(cgImage:cg)
        }.value
        if let image { cache.setObject(image,forKey:key as NSString) }
        return image
    }
}
struct CoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    let story: Story
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            let pixel = ceil(max(geometry.size.width,geometry.size.height)*displayScale/40)*40
            ZStack {
                if let image { Image(uiImage:image).resizable().scaledToFill() }
                else { Theme.surface; Image(systemName:"book.closed").font(RanyTypography.font(.largeTitle)).foregroundStyle(Theme.accent.opacity(0.6)) }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
            .task(id:CoverRequest(owner:store.accountID,key:story.key,cover:story.cover,pixel:pixel,revision:store.coverRevision)) {
                guard let owner = store.accountID, pixel > 0 else { image = nil; return }
                let cacheKey = owner+"|"+story.key+"|"+story.cover+"|\(Int(pixel))"
                if let cached = RanyCoverCache.cached(cacheKey) { image = cached; return }
                let loaded = await RanyCoverCache.load(Disk.file(owner,Disk.coverName(story.key)),key:cacheKey,maxPixel:pixel)
                if !Task.isCancelled, let loaded { image = loaded }
            }
        }.task(id:story.cover) { await store.cacheCover(story) }
    }
}
private struct CoverRequest: Hashable { let owner: String?; let key: String; let cover: String; let pixel: CGFloat; let revision: Int }
struct StoryCard: View {
    @Environment(AppStore.self) private var store
    let story: Story
    var showReadingProgress = false
    var sourceKeys: [String] = []
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            WanyLink(.story(story,sourceKeys:sourceKeys)) {
                VStack(alignment:.leading,spacing:7) {
                    CoverView(story:story).frame(height:205).clipShape(RoundedRectangle(cornerRadius:15))
                    Text(story.title).font(RanyTypography.font(.subheadline).weight(.semibold)).lineLimit(2,reservesSpace:true).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.topLeading)
                    HStack { Text(sourceKeys.count>1 ? "\(sourceKeys.count) مصادر · \(sourceLabel(story.source))" : sourceLabel(story.source)); Spacer(); if let latest = story.latest { Text(chapterNumber(latest)) } }.font(RanyTypography.font(.caption2)).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if showReadingProgress, let state = store.state {
                let full = store.stories[story.key] ?? story
                let summary = state.readingSummary(for:full)
                if let number = summary.chapter {
                    WanyLink(.reader(full,full.chapters?.first(where:{$0.number == number}) ?? Chapter(number:number,title:"الفصل \(chapterNumber(number))"))) {
                        Label("وصلت للفصل \(chapterNumber(number))",systemImage:"play.fill").font(RanyTypography.font(.caption)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                } else { Text("لم تبدأ القراءة").font(RanyTypography.font(.caption)).foregroundStyle(.secondary).frame(minHeight:44) }
                if let percent = summary.percent {
                    HStack { Text("تقدم القصة"); Spacer(); Text(percent.formatted(.number.precision(.fractionLength(1))) + "٪").monospacedDigit() }.font(RanyTypography.font(.caption2)).foregroundStyle(.secondary)
                    ProgressView(value:percent,total:100).tint(Theme.accent)
                } else { Text("\(summary.completedCount) فصل مقروء · بانتظار تحديث الفصول").font(RanyTypography.font(.caption2)).foregroundStyle(.secondary) }
            }
        }.padding(12).ranyGlass(radius:20)
    }
}

struct StoryGrid: View {
    let stories: [Story]
    var showReadingProgress = false
    var body: some View { LazyVGrid(columns:[GridItem(.flexible(),alignment:.top),GridItem(.flexible(),alignment:.top)],alignment:.leading,spacing:20) { ForEach(stories) { StoryCard(story:$0,showReadingProgress:showReadingProgress) } } }
}
struct AccountBadge: View {
    let kind: String?
    @State private var explaining = false
    var body: some View {
        if kind == "crown" || kind == "verified" {
            Button { explaining = true } label: {
                Image(kind == "crown" ? "crown" : "verified").resizable().frame(width:22,height:22)
                    .frame(width:30,height:44).contentShape(Rectangle())
            }.buttonStyle(.borderless)
                .highPriorityGesture(TapGesture().onEnded { explaining = true })
                .accessibilityLabel(kind == "crown" ? "Owner، مالك التطبيق" : "Beta Tester، مشارك في التجربة المبكرة")
                .popover(isPresented:$explaining) {
                    Text(kind == "crown" ? "Owner · مالك التطبيق" : "Beta Tester · مشارك في التجربة المبكرة")
                        .font(.caption).padding(14).presentationCompactAdaptation(.popover)
                        .task { try? await Task.sleep(nanoseconds:2_500_000_000); if !Task.isCancelled { explaining = false } }
                }
        }
    }
}
struct EmptyState: View {
    let icon: String; let title: String; let detail: String
    var body: some View { VStack(spacing:14) { Image(systemName:icon).font(.system(size:40)).foregroundStyle(Theme.accent); Text(title).font(RanyTypography.font(.headline)); Text(detail).font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(.vertical,45) }
}
