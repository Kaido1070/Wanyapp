import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @State private var selected = 4
    @State private var loginSheet = false
    private let titles = ["استكشف","FYP","جديد","التنزيلات","حسابي"]
    private let icons = ["magnifyingglass","sparkles","sparkle","arrow.down.circle","person.crop.circle"]
    var body: some View {
        Group {
            if store.state == nil { LoginView() }
            else {
                NavigationStack {
                    Group {
                        switch selected {
                        case 0: DiscoverView()
                        case 1: FeedView(kind:"fyp")
                        case 2: FeedView(kind:"new")
                        case 3: DownloadsView()
                        default: ProfileView()
                        }
                    }
                    .onAppear { store.mainPageVisible = true }
                    .navigationTitle(RanyIdentity.name).navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden,for:.navigationBar)
                    .toolbar {
                        ToolbarItem(placement:.principal) { Text(RanyIdentity.displayName).accessibilityLabel(RanyIdentity.name).font(RanyTypography.script(27)) }
                        ToolbarItem(placement:.topBarLeading) { RanyMark(size:32) }
                        ToolbarItem(placement:.topBarTrailing) { WanyLink { SettingsView() } label: { Image(systemName:"gearshape") } }
                    }
                    .safeAreaInset(edge:.top,spacing:0) {
                        if !store.online { Label("أوفلاين · تقدمك محفوظ على الجهاز",systemImage:"wifi.slash").font(RanyTypography.font(.caption)).frame(maxWidth:.infinity).padding(7).background(Theme.surface) }
                        else if store.loginRequired { Button("انتهت الجلسة · سجل الدخول لمزامنة تقدمك") { loginSheet = true }.font(RanyTypography.font(.caption)).padding(8) }
                    }
                }
                .id(selected)
                .overlay(alignment:.bottom) {
                    if store.mainPageVisible && !store.readerActive { HStack(spacing:0) {
                        ForEach(0..<5) { i in Button { selected = i; store.mainPageVisible = true; store.chromeHidden = false } label: {
                            VStack(spacing:5) { Image(systemName:icons[i]).font(.system(size:21)); Text(titles[i]).font(.custom(RanyIdentity.fontName,size:11,relativeTo:.caption2)) }.foregroundStyle(selected == i ? Theme.accent : .secondary).frame(maxWidth:.infinity).padding(.vertical,12)
                        } }
                    }.buttonStyle(.plain).ranyGlass(radius:24).padding(.horizontal,14).padding(.bottom,6)
                        .background(GeometryReader { proxy in Color.clear.preference(key:BottomBarHeightKey.self,value:proxy.size.height) })
                        .offset(y:store.chromeHidden ? 140 : 0).opacity(store.chromeHidden ? 0 : 1).allowsHitTesting(!store.chromeHidden).animation(.easeInOut(duration:0.22),value:store.chromeHidden)
                    }
                }
            }
        }
        .onPreferenceChange(BottomBarHeightKey.self) { store.bottomBarHeight = max(90,$0) }
        .sheet(isPresented:$loginSheet) { LoginView().onChange(of:store.loginRequired) { _,needed in if !needed { loginSheet = false } } }
        .alert(RanyIdentity.name,isPresented:Binding(get:{store.error != nil || downloads.notice != nil},set:{if !$0 { store.error = nil; downloads.notice = nil }})) { Button("حسنًا") { store.error = nil; downloads.notice = nil } } message: { Text(store.error ?? downloads.notice ?? "") }
    }
}
struct LoginView: View { var body: some View { RanyLoginView() } }

private struct BottomBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
