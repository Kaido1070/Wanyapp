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
                    .navigationTitle("Wany").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement:.topBarLeading) { Image("Logo").resizable().frame(width:30,height:30).clipShape(RoundedRectangle(cornerRadius:8)) }
                        ToolbarItem(placement:.topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName:"gearshape") } }
                    }
                    .safeAreaInset(edge:.top,spacing:0) {
                        if !store.online { Label("أوفلاين · تقدمك محفوظ على الجهاز",systemImage:"wifi.slash").font(.caption).frame(maxWidth:.infinity).padding(7).background(Theme.surface) }
                        else if store.loginRequired { Button("انتهت الجلسة · سجل الدخول لمزامنة تقدمك") { loginSheet = true }.font(.caption).padding(8) }
                    }
                }
                .id(selected)
                .safeAreaInset(edge:.bottom,spacing:0) {
                    if !store.readerActive { HStack(spacing:0) {
                        ForEach(0..<5) { i in Button { selected = i; store.chromeHidden = false } label: {
                            VStack(spacing:5) { Image(systemName:icons[i]).font(.system(size:21)); Text(titles[i]).font(.system(size:10,weight:.medium)) }.foregroundStyle(selected == i ? Theme.accent : .secondary).frame(maxWidth:.infinity).padding(.vertical,12)
                        } }
                    }.buttonStyle(.plain).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24)).padding(.horizontal,14).padding(.bottom,6)
                        .offset(y:store.chromeHidden ? 140 : 0).opacity(store.chromeHidden ? 0 : 1).allowsHitTesting(!store.chromeHidden).animation(.easeInOut(duration:0.22),value:store.chromeHidden)
                    }
                }
            }
        }
        .sheet(isPresented:$loginSheet) { LoginView().onChange(of:store.loginRequired) { _,needed in if !needed { loginSheet = false } } }
        .alert("Wany",isPresented:Binding(get:{store.error != nil || downloads.notice != nil},set:{if !$0 { store.error = nil; downloads.notice = nil }})) { Button("حسنًا") { store.error = nil; downloads.notice = nil } } message: { Text(store.error ?? downloads.notice ?? "") }
    }
}
struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    var body: some View {
        VStack(spacing:22) {
            Spacer()
            Image("Logo").resizable().frame(width:100,height:100).clipShape(RoundedRectangle(cornerRadius:27))
            Text("Wany").font(.system(size:40,weight:.bold,design:.rounded))
            Text("قصصك معك، حتى بدون إنترنت").foregroundStyle(.secondary)
            VStack(spacing:16) {
                TextField("اسم المستخدم",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                Divider()
                SecureField("كلمة المرور",text:$password).textContentType(.password)
            }.card()
            Button { busy = true; Task { await store.login(username:username,password:password); password = ""; busy = false } } label: {
                HStack { if busy { ProgressView() }; Text("تسجيل الدخول بحساب Wany").bold() }.frame(maxWidth:.infinity).padding(16)
            }.buttonStyle(.borderedProminent).disabled(busy || username.isEmpty || password.isEmpty)
            Text("استخدم نفس حساب الموقع. بياناتك وتنزيلاتك تبقى متاحة عند انقطاع الاتصال.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(); Spacer()
        }.padding(28).background(Theme.background)
    }
}
