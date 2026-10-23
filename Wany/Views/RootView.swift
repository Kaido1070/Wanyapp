import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @State private var tabs = RanyTabNavigation()
    @State private var loginSheet = false
    var body: some View {
        Group {
            if store.state == nil { LoginView() }
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
                        .tabItem { Label(tab.label,systemImage:tab.icon) }
                        .tag(tab)
                    }
                }
            }
        }
        .onChange(of:store.state?.user.id) { _,_ in tabs.reset() }
        .sheet(isPresented:$loginSheet) { LoginView().onChange(of:store.loginRequired) { _,needed in if !needed { loginSheet = false } } }
        .alert(RanyIdentity.name,isPresented:Binding(get:{store.error != nil || downloads.notice != nil},set:{if !$0 { store.error = nil; downloads.notice = nil }})) { Button("حسنًا") { store.error = nil; downloads.notice = nil } } message: { Text(store.error ?? downloads.notice ?? "") }
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
    }
}
struct LoginView: View { var body: some View { RanyLoginView() } }
