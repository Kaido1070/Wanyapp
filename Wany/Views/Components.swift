import SwiftUI
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
    @EnvironmentObject var store: AppStore
    @Environment(\.ranyMainHeader) private var mainHeader
    @State private var scrollDirection = ReaderScrollDirection(revealDistance:192)
    let content: Content
    init(@ViewBuilder content: ()->Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(spacing:18) {
                if mainHeader { RanyPageHeader() }
                content
            }
                .ranyGlassGroup()
                .padding(.horizontal,18)
                // Navigation destinations must reserve their own space for the floating bar.
                .padding(.bottom,store.mainPageVisible ? store.bottomBarHeight + 32 : 32)
                .background(ReaderScrollObserver { offset, moving in
                    if let visible = scrollDirection.update(offset:offset,userScrolling:moving), store.chromeHidden == visible {
                        withAnimation(.easeInOut(duration:0.22)) { store.chromeHidden = !visible }
                    }
                })
        }
        .onAppear { scrollDirection = ReaderScrollDirection(revealDistance:192); store.chromeHidden = false }
        .background(Color.clear).ranyClearNavigation()
    }
}
struct CoverView: View {
    @EnvironmentObject var store: AppStore
    let story: Story
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let owner = store.state?.user.id, let image = UIImage(contentsOfFile:Disk.file(owner,Disk.coverName(story.key)).path) { Image(uiImage:image).resizable().scaledToFill() }
                else { ZStack { Theme.surface; Image(systemName:"book.closed").font(RanyTypography.font(.largeTitle)).foregroundStyle(Theme.accent.opacity(0.6)) } }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.task(id:story.cover) { await store.cacheCover(story) }
    }
}
struct StoryCard: View {
    @EnvironmentObject var store: AppStore
    let story: Story
    var showReadingProgress = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            WanyLink { StoryView(initial:story) } label: {
                VStack(alignment:.leading,spacing:7) {
                    CoverView(story:story).frame(height:205).clipShape(RoundedRectangle(cornerRadius:15))
                    Text(story.title).font(RanyTypography.font(.subheadline).weight(.semibold)).lineLimit(2).frame(height:40,alignment:.topLeading)
                    HStack { Text(sourceLabel(story.source)); Spacer(); if let latest = story.latest { Text(chapterNumber(latest)) } }.font(RanyTypography.font(.caption2)).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if showReadingProgress, let state = store.state {
                let full = store.stories[story.key] ?? story
                let summary = state.readingSummary(for:full)
                if let number = summary.chapter {
                    WanyLink { ReaderView(story:full,chapter:full.chapters?.first(where:{$0.number == number}) ?? Chapter(number:number,title:"الفصل \(chapterNumber(number))")) } label: {
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
    var body: some View { VStack(spacing:14) { Image(systemName:icon).font(.system(size:40)).foregroundStyle(Theme.accent); Text(title).font(RanyTypography.font(.headline)); Text(detail).font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(.vertical,45) }
}
