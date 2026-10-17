import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 4
    @State private var requested = 4
    @State private var selectionTask: Task<Void,Never>?
    @State private var tabOpacity = 1.0
    @State private var tabOffset: CGFloat = 0
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
                    // Animate the selected page only; never fade or move the bottom tab bar.
                    .opacity(tabOpacity).offset(y:tabOffset)
                    .background(RanyNavigationLifecycle(main:true))
                    .environment(\.ranyMainHeader,true)
                    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden,for:.navigationBar)
                    .ranyClearNavigation()
                    .safeAreaInset(edge:.top,spacing:0) {
                        if !store.online { Label("أوفلاين · تقدمك محفوظ على الجهاز",systemImage:"wifi.slash").font(RanyTypography.font(.caption)).frame(maxWidth:.infinity).padding(7).background(Theme.surface) }
                        else if store.loginRequired { Button("انتهت الجلسة · سجل الدخول لمزامنة تقدمك") { loginSheet = true }.font(RanyTypography.font(.caption)).padding(8) }
                    }
                    // This chrome belongs to the NavigationStack root, not the stack container.
                    // UIKit therefore hides it during pushes and restores it automatically on pop,
                    // even when a transient destination's lifecycle observer is already gone.
                    .overlay(alignment:.bottom) {
                        if !store.readerActive { HStack(spacing:0) {
                        ForEach(0..<5) { i in Button { select(i) } label: {
                            VStack(spacing:5) { Image(systemName:icons[i]).font(.system(size:21)); Text(titles[i]).font(.system(.caption2)) }.foregroundStyle(requested == i ? Theme.accent : .secondary).frame(maxWidth:.infinity).padding(.vertical,12)
                        } }
                    }.buttonStyle(.plain).ranyGlass(radius:24).padding(.horizontal,14).padding(.bottom,6)
                        .background(GeometryReader { proxy in Color.clear.preference(key:BottomBarHeightKey.self,value:proxy.size.height) })
                        .accessibilityIdentifier("main.bottom-bar")
                        }
                    }
                    .onAppear { store.mainPageVisible = true }
                }
                .id(selected)
            }
        }
        .onPreferenceChange(BottomBarHeightKey.self) { store.bottomBarHeight = max(90,$0) }
        .sheet(isPresented:$loginSheet) { LoginView().onChange(of:store.loginRequired) { _,needed in if !needed { loginSheet = false } } }
        .alert(RanyIdentity.name,isPresented:Binding(get:{store.error != nil || downloads.notice != nil},set:{if !$0 { store.error = nil; downloads.notice = nil }})) { Button("حسنًا") { store.error = nil; downloads.notice = nil } } message: { Text(store.error ?? downloads.notice ?? "") }
    }
    private func select(_ index: Int) {
        guard requested != index else { return }
        requested = index; selectionTask?.cancel()
        if reduceMotion {
            selected = index; tabOpacity = 1; tabOffset = 0
            store.mainPageVisible = true; return
        }
        selectionTask = Task { @MainActor in
            withAnimation(.easeIn(duration:0.085)) { tabOpacity = 0; tabOffset = -3 }
            do { try await Task.sleep(nanoseconds:85_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { selected = index; tabOpacity = 0; tabOffset = 4; store.mainPageVisible = true; store.chromeHidden = false }
            // Let the new tree lay out while hidden; outgoing text has already left.
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration:0.145)) { tabOpacity = 1; tabOffset = 0 }
        }
    }

}
struct LoginView: View { var body: some View { RanyLoginView() } }

private struct BottomBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
