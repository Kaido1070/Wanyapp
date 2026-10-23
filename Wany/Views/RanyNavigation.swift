import SwiftUI
import UIKit

// Every push is a value on the selected tab's NavigationStack path. UIKit owns
// the transition, the back button and the edge swipe; touches are never blocked.
enum RanyRoute: Hashable {
    case story(Story,sourceKeys:[String] = [])
    case reader(Story,Chapter)
    case sourceChapter(key: String, chapter: Chapter, fallback: Story)
    case listDetail(id: String, title: String)
    case publicProfile(String)
    case settings, stats, friends, activity, updates, avatarPicker, lists, accountSecurity
    case securityPassword, securityQuestion, securityRecovery
}
struct RanyDestination: View {
    let route: RanyRoute
    var body: some View {
        switch route {
        case .story(let story,let sourceKeys): StoryView(initial:story,sourceKeys:sourceKeys)
        case .reader(let story,let chapter): ReaderView(story:story,chapter:chapter)
        case .sourceChapter(let key,let chapter,let fallback): SourceChapterDestination(key:key,chapter:chapter,fallback:fallback)
        case .listDetail(let id,let title): ListDetailView(id:id,title:title)
        case .publicProfile(let id): PublicProfileView(id:id)
        case .settings: SettingsView()
        case .stats: StatsView()
        case .friends: FriendsView()
        case .activity: ActivityView()
        case .updates: UpdatesView()
        case .avatarPicker: AvatarPickerView()
        case .lists: ListsView()
        case .accountSecurity: AccountSecurityView()
        case .securityPassword: SecurityPasswordView()
        case .securityQuestion: SecurityQuestionView()
        case .securityRecovery: SecurityRecoveryView()
        }
    }
}
private struct RanyDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for:RanyRoute.self) { route in RanyDestination(route:route).ranyClearNavigation().modifier(RanySettingsTabBar()) }
    }
}
// Settings and every page opened from it keep the bottom tab bar out of the way.
private struct RanySettingsTabBar: ViewModifier {
    @Environment(\.ranyInsideSettings) private var insideSettings
    func body(content: Content) -> some View {
        if insideSettings { content.toolbar(.hidden,for:.tabBar) } else { content }
    }
}
extension View { func ranyDestinations() -> some View { modifier(RanyDestinations()) } }

enum RanyTab: Int, CaseIterable, Hashable {
    case discover, fyp, new, downloads, profile
    var label: String { ["استكشف","FYP","جديد","التنزيلات","حسابي"][rawValue] }
    var title: String { ["استكشف","مقترح لك","جديد","تنزيلاتي","حسابي"][rawValue] }
    var icon: String { ["magnifyingglass","sparkles","sparkle","arrow.down.circle","person.crop.circle"][rawValue] }
}

// Tapping the selected tab pops its stack, or scrolls its root page to the top.
struct RanyTabNavigation {
    var selection: RanyTab = .profile
    var paths: [RanyTab:[RanyRoute]] = [:]
    private(set) var scrollRequests: [RanyTab:Int] = [:]
    mutating func select(_ tab: RanyTab) {
        guard tab == selection else { selection = tab; return }
        if paths[tab]?.isEmpty == false { paths[tab] = [] }
        else { scrollRequests[tab,default:0] += 1 }
    }
    mutating func reset() { paths = [:] }
}

private struct RanyScrollToTopKey: EnvironmentKey { static let defaultValue = 0 }
private struct RanyInsideSettingsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ranyScrollToTop: Int {
        get { self[RanyScrollToTopKey.self] }
        set { self[RanyScrollToTopKey.self] = newValue }
    }
    var ranyInsideSettings: Bool {
        get { self[RanyInsideSettingsKey.self] }
        set { self[RanyInsideSettingsKey.self] = newValue }
    }
}

struct RanyMainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement:.topBarLeading) { RanyToolbarMark() }
        ToolbarItem(placement:.topBarTrailing) {
            NavigationLink(value:RanyRoute.settings) {
                Image(systemName:"gearshape").frame(minWidth:44,minHeight:44).contentShape(Rectangle())
            }.accessibilityLabel("الإعدادات").accessibilityIdentifier("main.settings")
        }
    }
}

// Pages that hide the navigation bar (the reader) lose UIKit's edge swipe. Keep
// the native interactive pop available while such a page is visible.
struct RanyInteractivePop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var navigation: UINavigationController?
        private weak var original: UIGestureRecognizerDelegate?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigation = navigationController, let gesture = navigation.interactivePopGestureRecognizer else { return }
            self.navigation = navigation
            if gesture.delegate !== self { original = gesture.delegate; gesture.delegate = self }
            gesture.isEnabled = true
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let gesture = navigation?.interactivePopGestureRecognizer, gesture.delegate === self { gesture.delegate = original }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation else { return false }
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }
    }
}
