import SwiftUI

@MainActor final class CachedPage: ObservableObject {
    @Published var value: JSONValue = .null
    @Published var loading = false
    @Published var error: String?
    private var requestID = UUID()
    private var filename: String?
    func load(_ path: String, store: AppStore, query: [String:String] = [:]) async {
        guard let owner = store.state?.user.id else { return }
        let filename = "api/"+Disk.hash(path + query.sorted {$0.key<$1.key}.description)+".json"
        guard !loading || self.filename != filename else { return }
        let token = UUID(); requestID = token; self.filename = filename
        let ownedLists=Set((Disk.read([RanyProfileSection].self,owner:owner,name:"collections/sections.json") ?? []).filter { $0.sectionType == "custom_list" }.compactMap(\.referenceId))
        let ownList=path.hasPrefix("/api/lists/") && ownedLists.contains(String(path.dropFirst("/api/lists/".count)).removingPercentEncoding ?? "")
        let freshAuthorization=path.hasPrefix("/api/profiles/") || (path.hasPrefix("/api/lists/") && !ownList && !path.hasPrefix("/api/lists/membership/"))
        value = freshAuthorization ? .null : (Disk.read(JSONValue.self,owner:owner,name:filename) ?? .null)
        error = nil
        guard store.online else { loading = false; return }; loading = true
        defer { if requestID == token { loading = false } }
        do {
            let response = try await API.shared.get(path,query:query,as:JSONValue.self)
            guard requestID == token, store.state?.user.id == owner else { return }
            value = response; error = nil; if !freshAuthorization { try Disk.save(value,owner:owner,name:filename) }
        } catch { if requestID == token, !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @State private var editingName = false
    @State private var name = ""
    @State private var logout = false
    var body: some View {
        WanyScroll {
            RanyAppearanceControls()
            VStack(alignment:.leading,spacing:16) {
                Text("الحساب").font(RanyTypography.font(.headline))
                Button { name = store.state?.user.name ?? ""; editingName = true } label: { settingsRow("الاسم الظاهر",value:store.state?.user.name ?? "",icon:"pencil") }.disabled(!store.online)
                Divider()
                WanyLink { AvatarPickerView() } label: { settingsRow("الصورة الشخصية",icon:"person.crop.circle") }
                Divider()
                Toggle("حساب خاص",isOn:Binding(get:{store.state?.user.profileVisibility == "private"},set:{ value in Task { do { try await API.shared.send("/api/profile/visibility",method:"PUT",value:["visibility":value ? "private" : "public"]); await store.refresh() } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } } } })).disabled(!store.online)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                Text("التنزيلات والمساحة").font(RanyTypography.font(.headline))
                Toggle("التنزيل عبر Wi-Fi فقط",isOn:Binding(get:{downloads.wifiOnly},set:{downloads.wifiOnly = $0}))
                Divider()
                Picker("جودة الصور",selection:Binding(get:{downloads.quality},set:{downloads.quality = $0})) { ForEach(ImageQuality.allCases) { quality in Text(quality.label).tag(quality) } }
                Text("المتوازنة والعالية تطلبان تصغير الصورة على الخادم قبل تنزيلها. يظهر عدد الصور المصغرة في التنزيلات عندما يدعم الخادم المعالجة؛ وإلا تُصغر محليًا.").font(RanyTypography.font(.caption)).foregroundStyle(.secondary)
                settingsRow("التنزيلات المحفوظة",value:byteLabel(downloads.savedJobs.reduce(0){$0+$1.bytes}))
                settingsRow("صور القراءة المؤقتة",value:byteLabel(downloads.temporaryBytes))
                Text("صور القراءة العادية تُحذف بعد 3 دقائق من مغادرة الفصل، أو عند فتح التطبيق مجددًا إذا كان مغلقًا. تقدمك يبقى محفوظًا.").font(RanyTypography.font(.caption)).foregroundStyle(.secondary)
                Button { downloads.cleanTemporary(all:true) } label: { settingsRow("مسح الصور المؤقتة الآن",icon:"trash") }.disabled(downloads.temporaryBytes == 0)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                Text("المزامنة").font(RanyTypography.font(.headline))
                settingsRow("التحديثات المعلقة",value:String(store.state?.pending.count ?? 0))
                if let date = store.state?.lastSynced { Text("آخر مزامنة: " + date.formatted(date:.abbreviated,time:.shortened)).font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }
                Button { Task { await store.refresh() } } label: { settingsRow(store.syncing ? "جاري المزامنة…" : "مزامنة الآن",icon:"arrow.clockwise") }.disabled(!store.online || store.syncing)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                WanyLink { AccountSecurityView() } label: { settingsRow("الأمان وكلمة المرور",icon:"lock.shield") }
                Text(AppVersion.display).font(RanyTypography.font(.subheadline))
                WanyLink { UpdatesView() } label: { settingsRow("سجل التحديثات",icon:"clock.arrow.circlepath") }
            }.card()
            Button(role:.destructive) { logout = true } label: { Label("تسجيل الخروج",systemImage:"rectangle.portrait.and.arrow.right").font(RanyTypography.font(.headline)).foregroundStyle(.red).frame(maxWidth:.infinity,minHeight:52).contentShape(Rectangle()) }.padding(12).background(Color.red.opacity(0.12),in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(Color.red.opacity(0.4),lineWidth:1))
        }.buttonStyle(.plain).navigationTitle("الإعدادات")
        .alert("الاسم الظاهر",isPresented:$editingName) {
            TextField("اسمك",text:$name)
            Button("حفظ") { Task { do { try await API.shared.send("/api/profile/name",method:"PUT",value:["name":name]); await store.refresh() } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } } } }
            Button("إلغاء",role:.cancel) {}
        }
        .confirmationDialog("تسجيل الخروج؟ تبقى التنزيلات والتقدم محفوظة لحسابك.",isPresented:$logout) { Button("تسجيل الخروج",role:.destructive) { Task { await store.logout() } } }
    }
    func settingsRow(_ title: String, value: String = "", icon: String? = nil) -> some View {
        HStack(spacing:12) { Text(title).foregroundStyle(.primary); Spacer(minLength:10); if !value.isEmpty { Text(value).font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary) }; if let icon { Image(systemName:icon).foregroundStyle(Theme.accent) } }.frame(minHeight:44).contentShape(Rectangle())
    }
}
struct AvatarPickerView: View {
    var onSelect: ((String)->Void)? = nil
    var initialAvatarID: String? = nil
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ranyNavigator) private var navigator
    @StateObject private var page = CachedPage()
    @State private var query = ""
    @State private var selectedID = ""
    @State private var saving = false
    @State private var saveError: String?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if page.value["series"].array.isEmpty {
                    if page.loading { ProgressView("تحميل الصور…").frame(maxWidth:.infinity).padding() }
                    else if let error = page.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("إعادة المحاولة") { Task { await page.load("/api/avatars",store:store) } }.disabled(!store.online)
                    } else {
                        Text(store.online ? "لا توجد صور متاحة حاليًا." : "اتصل بالإنترنت لتحميل الصور الشخصية.").foregroundStyle(.secondary).padding()
                    }
                } else {
                    RanyAvatarGrid(series:page.value["series"].array,query:query,selectedID:selectedID) { selectedID = $0 }
                }
            }.padding(16)
        }
        .searchable(text:$query,prompt:"ابحث باسم الشخصية أو العمل")
        .safeAreaInset(edge:.bottom,spacing:0) {
            HStack(spacing:12) {
                if let user = previewAccount {
                    ProfileAvatar(user:user).frame(width:48,height:48)
                }
                Text(selectedName.isEmpty ? "اختر صورة من الشبكة" : selectedName).font(.subheadline).lineLimit(2)
                Spacer(minLength:0)
                Button { saveSelection() } label: {
                    if saving { ProgressView() } else { Text(onSelect == nil ? "حفظ الصورة" : "استخدام الصورة") }
                }.buttonStyle(.borderedProminent)
                    .disabled(selectedID.isEmpty || !store.online || saving)
            }.padding(12).background(.regularMaterial)
        }
        .disabled(saving)
        .onChange(of:store.online) { _,online in if online { Task { await page.load("/api/avatars",store:store) } } }
        .ranyClearNavigation().navigationTitle("الصورة الشخصية")
        .alert("تعذر حفظ الصورة",isPresented:Binding(get:{saveError != nil},set:{if !$0 { saveError = nil }})) {
            Button("حسنًا",role:.cancel) {}
        } message: { Text(saveError ?? "") }
        .task {
            if selectedID.isEmpty { selectedID = initialAvatarID ?? store.state?.user.avatarId ?? "" }
            await page.load("/api/avatars",store:store)
        }
    }
    private var selectedName: String {
        page.value["series"].array.flatMap { $0["avatars"].array }.first { $0["id"].string == selectedID }?["characterName"].string ?? ""
    }
    private var previewAccount: Account? {
        guard !selectedID.isEmpty, var account = store.state?.user else { return nil }
        account.avatarId = selectedID; return account
    }
    private func saveSelection() {
        guard !saving, !selectedID.isEmpty, store.online else { return }
        if let onSelect { onSelect(selectedID); dismiss(); return }
        saving = true
        let savingRoute = navigator?.path.last
        Task { @MainActor in
            defer { saving = false }
            do {
                try await API.shared.send("/api/profile/avatar",method:"PUT",value:["avatarId":selectedID])
                await store.refresh()
                if let navigator, let savingRoute { navigator.pop(ifCurrent:savingRoute) }
                else { dismiss() }
            } catch { if !isRequestCancellation(error) { saveError = error.localizedDescription } }
        }
    }
}

struct RanyAvatarGrid: View {
    let series: [JSONValue]
    let query: String
    let selectedID: String
    let select: (String)->Void
    @EnvironmentObject private var store: AppStore
    static func matches(_ value:String,query:String) -> Bool {
        query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || value.localizedStandardContains(query.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    private var filtered: [(name:String,avatars:[JSONValue])] {
        series.compactMap { group in
            let name = group["name"].string
            let avatars = group["avatars"].array.filter { Self.matches(name,query:query) || Self.matches($0["characterName"].string,query:query) }
            return avatars.isEmpty ? nil : (name,avatars)
        }
    }
    var body: some View {
        if filtered.isEmpty {
            Text("لا توجد صور مطابقة لبحثك").foregroundStyle(.secondary).frame(maxWidth:.infinity).padding()
        }
        ForEach(Array(filtered.enumerated()),id:\.offset) { _,group in
            VStack(alignment:.leading,spacing:12) {
                Text(group.name).font(.subheadline.bold()).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:80),spacing:10)],alignment:.center,spacing:16) {
                    ForEach(Array(group.avatars.enumerated()),id:\.offset) { _,avatar in
                        let id = avatar["id"].string
                        Button { select(id) } label: {
                            VStack(spacing:6) {
                                ZStack(alignment:.bottomTrailing) {
                                    if var account = store.state?.user {
                                        let _ = account.avatarId = id
                                        ProfileAvatar(user:account).frame(width:64,height:64)
                                            .overlay(Circle().stroke(selectedID == id ? Theme.accent : .clear,lineWidth:3))
                                    }
                                    if selectedID == id { Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.accent).background(Circle().fill(.black)).font(.body) }
                                }.frame(height:68)
                                Text(avatar["characterName"].string).font(.caption).lineLimit(2).multilineTextAlignment(.center).frame(height:32,alignment:.top)
                            }.frame(maxWidth:.infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                            .accessibilityLabel(avatar["characterName"].string)
                            .accessibilityAddTraits(selectedID == id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct PublicAccountIdentity: View {
    let user: JSONValue
    var large = false
    var body: some View {
        HStack(spacing:12) {
            if let account = user.publicAccount {
                ProfileAvatar(user:account).frame(width:large ? 72 : 44,height:large ? 72 : 44)
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text(account.name).font(large ? .title2.bold() : .body).lineLimit(2); AccountBadge(kind:account.badgeType) }
                    if !account.username.isEmpty { Text("@"+account.username).font(RanyTypography.font(.caption)).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
