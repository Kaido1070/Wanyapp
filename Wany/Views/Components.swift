import SwiftUI
import ImageIO

enum Theme {
    static let background = Color(red:23/255,green:25/255,blue:27/255)
    static let surface = Color(red:32/255,green:34/255,blue:37/255)
    static let accent = Color(red:219/255,green:185/255,blue:145/255)
}
struct WanyCard: ViewModifier {
    func body(content: Content) -> some View { content.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:20)) }
}
extension View { func card() -> some View { modifier(WanyCard()) } }
struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: ()->CGFloat) { value = nextValue() }
}
struct WanyScroll<Content: View>: View {
    @EnvironmentObject var store: AppStore
    @State private var last: CGFloat = 0
    @State private var travel: CGFloat = 0
    @State private var direction = false
    let content: Content
    init(@ViewBuilder content: ()->Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(spacing:18) {
                GeometryReader { proxy in Color.clear.preference(key:OffsetKey.self,value:proxy.frame(in:.named("page")).minY) }.frame(height:0)
                content
            }.padding(.horizontal,18).padding(.bottom,24)
        }.coordinateSpace(name:"page")
        .onPreferenceChange(OffsetKey.self) { value in
            let delta = last-value; last = value
            if value > -80 { store.chromeHidden = false; travel = 0; return }
            guard abs(delta) >= 1 else { return }
            if (delta > 0) != direction { direction = delta > 0; travel = 0 }
            travel += abs(delta)
            if travel >= (direction ? 28 : 16) { withAnimation(.easeInOut(duration:0.22)) { store.chromeHidden = direction }; travel = 0 }
        }
        .onAppear { store.chromeHidden = false }
        .background(Theme.background)
    }
}
struct CoverView: View {
    @EnvironmentObject var store: AppStore
    let story: Story
    var body: some View {
        Group {
            if let owner = store.state?.user.id, let image = UIImage(contentsOfFile:Disk.file(owner,Disk.coverName(story.key)).path) { Image(uiImage:image).resizable().scaledToFill() }
            else { ZStack { Theme.surface; Image(systemName:"book.closed").font(.largeTitle).foregroundStyle(Theme.accent.opacity(0.6)) } }
        }.clipped().task(id:story.cover) { await store.cacheCover(story) }
    }
}
struct StoryCard: View {
    @EnvironmentObject var store: AppStore
    let story: Story
    var showReadingProgress = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            NavigationLink { StoryView(initial:story) } label: {
                VStack(alignment:.leading,spacing:7) {
                    CoverView(story:story).frame(height:205).clipShape(RoundedRectangle(cornerRadius:15))
                    Text(story.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(height:40,alignment:.topLeading)
                    HStack { Text(sourceLabel(story.source)); Spacer(); if let latest = story.latest { Text(chapterNumber(latest)) } }.font(.caption2).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if showReadingProgress, let state = store.state {
                let full = store.stories[story.key] ?? story
                let summary = state.readingSummary(for:full)
                if let number = summary.chapter {
                    NavigationLink { ReaderView(story:full,chapter:full.chapters?.first(where:{$0.number == number}) ?? Chapter(number:number,title:"الفصل \(chapterNumber(number))")) } label: {
                        Label("وصلت للفصل \(chapterNumber(number))",systemImage:"play.fill").font(.caption).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                } else { Text("لم تبدأ القراءة").font(.caption).foregroundStyle(.secondary).frame(minHeight:44) }
                if let percent = summary.percent {
                    HStack { Text("تقدم القصة"); Spacer(); Text(percent.formatted(.number.precision(.fractionLength(1))) + "٪").monospacedDigit() }.font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value:percent,total:100).tint(Theme.accent)
                } else { Text("\(summary.completedCount) فصل مقروء · بانتظار تحديث الفصول").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

struct StoryGrid: View {
    let stories: [Story]
    var showReadingProgress = false
    var body: some View { LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:20) { ForEach(stories) { StoryCard(story:$0,showReadingProgress:showReadingProgress) } } }
}
struct AccountBadge: View {
    let kind: String?
    var body: some View {
        if kind == "crown" || kind == "verified" {
            Image(kind == "crown" ? "crown" : "verified").resizable().frame(width:22,height:22)
                .accessibilityLabel(kind == "crown" ? "Owner" : "Beta Tester")
        }
    }
}
struct EmptyState: View {
    let icon: String; let title: String; let detail: String
    var body: some View { VStack(spacing:14) { Image(systemName:icon).font(.system(size:40)).foregroundStyle(Theme.accent); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(.vertical,45) }
}
