import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Downloads.self) private var downloads
    @State private var tabs = RanyTabNavigation()
    @State private var loginSheet = false
    var body: some View {
        Group {
            if store.accountID == nil { LoginView() }
            else {
                TabView(selection:Binding(get:{ tabs.selection },set:{ tabs.select($0) })) {
                    ForEach(RanyTab.allCases,id:\.self) { tab in
                        NavigationStack(path:Binding(get:{ tabs.paths[tab] ?? [] },set:{ tabs.paths[tab] = $0 })) {
                            page(tab)
                                .navigationTitle(tab.title)
                                .navigationBarTitleDisplayMode(.large)
                                .toolbar { RanyMainToolbar() }
                                .safeAreaInset(edge:.top,spacing:0) { banner }
                                .environment(\.ranyScrollToTop,tabs.scrollRequests[tab] ?? 0)
                                .ranyDestinations()
                        }
                        .environment(\.ranyInsideSettings,tabs.paths[tab]?.contains(.settings) == true)
                        .tabItem { Label(tab.label,systemImage:tab.icon) }
                        // Unread messages show on the account tab, where they are opened.
                        .badge(tab == .profile ? store.unreadMessages : 0)
                        .tag(tab)
                    }
                }
            }
        }
        .onChange(of:store.accountID) { _,_ in tabs.reset() }
        .onChange(of:tabs.paths) { _,_ in store.holdBackdropForNavigation() }
        .sheet(isPresented:Binding(get:{ store.showingNameStory },set:{ store.showingNameStory = $0 })) { RanyNameStory { store.showingNameStory = false } }
        .sheet(isPresented:$loginSheet) { LoginView().onChange(of:store.loginRequired) { _,needed in if !needed { loginSheet = false } } }
        .alert(RanyIdentity.name,isPresented:Binding(get:{store.error != nil || downloads.notice != nil},set:{if !$0 { dismissMessage() }})) { Button("حسنًا") {} } message: { Text(store.error ?? downloads.notice ?? "") }
    }
    // Two messages at once are shown one after the other; closing one never hides the other.
    // Only the presentation binding clears a message: the button runs too, and two clears
    // for one tap would drop the second message.
    private func dismissMessage() {
        if store.error != nil { store.error = nil } else { downloads.notice = nil }
    }
    @ViewBuilder private func page(_ tab: RanyTab) -> some View {
        switch tab {
        case .discover: DiscoverView()
        case .fyp: FeedView(kind:"fyp")
        case .new: FeedView(kind:"new")
        case .downloads: DownloadsView()
        case .profile: ProfileView()
        }
    }
    @ViewBuilder private var banner: some View {
        if !store.online { Label("أوفلاين · تقدمك محفوظ على الجهاز",systemImage:"wifi.slash").font(RanyTypography.font(.caption)).frame(maxWidth:.infinity).padding(7).background(Theme.surface) }
        else if store.loginRequired { Button("انتهت الجلسة · سجل الدخول لمزامنة تقدمك") { loginSheet = true }.font(RanyTypography.font(.caption)).frame(minHeight:44).padding(.horizontal,8) }
        else if store.syncProblem != nil {
            Button { Task { await store.refresh() } } label: {
                Label(store.syncing ? "جاري المزامنة…" : "تعذرت المزامنة · اضغط لإعادة المحاولة",systemImage:"exclamationmark.arrow.triangle.2.circlepath")
            }.font(RanyTypography.font(.caption)).frame(maxWidth:.infinity,minHeight:44).padding(.horizontal,8).background(Theme.surface).disabled(store.syncing)
        }
    }
}
struct LoginView: View { var body: some View { RanyLoginView() } }
