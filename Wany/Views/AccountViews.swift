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
        value = Disk.read(JSONValue.self,owner:owner,name:filename) ?? .null
        error = nil
        guard store.online else { loading = false; return }; loading = true
        defer { if requestID == token { loading = false } }
        do {
            let response = try await API.shared.get(path,query:query,as:JSONValue.self)
            guard requestID == token, store.state?.user.id == owner else { return }
            value = response; error = nil; try Disk.save(value,owner:owner,name:filename)
        } catch { if requestID == token, !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}
struct ListsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var page = CachedPage()
    @State private var create = false
    @State private var name = ""
    var body: some View {
        WanyScroll {
            HStack { Text("قوائمي").font(.largeTitle.bold()); Spacer(); Button { create = true } label: { Image(systemName:"plus") }.disabled(!store.online) }
            ForEach(Array(page.value["lists"].array.enumerated()),id:\.offset) { _,list in
                NavigationLink { ListDetailView(id:list["id"].string,title:list["name"].string) } label: { HStack { Image(systemName:"list.bullet.rectangle"); Text(list["name"].string); Spacer(); Text("\(Int(list["itemCount"].number))").foregroundStyle(.secondary); Image(systemName:"chevron.left") }.foregroundStyle(.primary).card() }
            }
            if let error = page.error { Text(error).foregroundStyle(.orange) }
        }.task { await page.load("/api/lists",store:store) }.refreshable { await page.load("/api/lists",store:store) }
        .alert("قائمة جديدة",isPresented:$create) { TextField("اسم القائمة",text:$name); Button("إنشاء") { Task { do { try await API.shared.send("/api/lists",value:["name":name,"description":"","iconKey":"lists"]); name = ""; await page.load("/api/lists",store:store) } catch { store.error = error.localizedDescription } } }; Button("إلغاء",role:.cancel) {} }
    }
}
struct ListDetailView: View {
    @EnvironmentObject var store: AppStore
    let id: String; let title: String
    @StateObject private var page = CachedPage()
    @State private var adding = false
    var body: some View {
        WanyScroll {
            HStack { Text(title).font(.largeTitle.bold()); Spacer(); Button { adding = true } label: { Image(systemName:"plus") }.disabled(!store.online) }
            ForEach(Array(page.value["items"].array.enumerated()),id:\.offset) { _,item in
                if let story = store.stories[item["mangaId"].string] {
                    HStack { NavigationLink { StoryView(initial:story) } label: { Text(story.title).foregroundStyle(.primary) }; Spacer(); Button(role:.destructive) { Task { do { _ = try await API.shared.raw("/api/lists/"+id+"/items/"+story.key,method:"DELETE"); await load() } catch { store.error = error.localizedDescription } } } label: { Image(systemName:"minus.circle") }.disabled(!store.online) }.card()
                } else { Text(item["mangaId"].string).font(.caption) }
            }
            if let error = page.error { Text(error).foregroundStyle(.orange) }
        }.task { await load() }.refreshable { await load() }
        .sheet(isPresented:$adding,onDismiss:{ Task { await load() } }) { AddStoriesToListView(id:id) }
    }
    func load() async {
        await page.load("/api/lists/"+id,store:store)
        let keys = page.value["items"].array.map {$0["mangaId"].string}.filter {store.stories[$0] == nil}
        guard store.online else { return }
        for start in stride(from:0,to:keys.count,by:40) {
            if let r = try? await API.shared.get("/api/source/resolve",query:["keys":keys[start..<min(start+40,keys.count)].joined(separator:",")],as:ResolveResponse.self) { for item in r.items { store.remember(item) } }
        }
    }
}
struct FriendsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var page = CachedPage()
    @StateObject private var requests = CachedPage()
    @StateObject private var search = CachedPage()
    @State private var query = ""
    var body: some View {
        WanyScroll {
            Text("الأصدقاء").font(.largeTitle.bold()).frame(maxWidth:.infinity,alignment:.leading)
            HStack { TextField("اسم المستخدم",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("بحث") { Task { await search.load("/api/friends/search",store:store,query:["q":query]) } }.disabled(!store.online) }.card()
            ForEach(Array(search.value["results"].array.enumerated()),id:\.offset) { _,entry in
                HStack { userLabel(entry["user"]); Spacer(); Button(entry["relationship"].string == "none" ? "إضافة" : "طلب مسجل") { Task { await action("/api/friends",body:["userId":entry["user"]["id"].string]); await search.load("/api/friends/search",store:store,query:["q":query]) } }.disabled(entry["relationship"].string != "none" || !store.online) }.card()
            }
            ForEach(Array(requests.value["incoming"].array.enumerated()),id:\.offset) { _,entry in
                HStack { userLabel(entry["user"]); Spacer(); Button("قبول") { Task { await action("/api/friends/requests/"+entry["user"]["id"].string+"/accept") } }; Button("رفض") { Task { await action("/api/friends/requests/"+entry["user"]["id"].string+"/reject") } } }.card()
            }
            ForEach(Array(page.value["friends"].array.enumerated()),id:\.offset) { _,entry in
                NavigationLink { PublicProfileView(id:entry["user"]["id"].string) } label: { userLabel(entry["user"]).frame(maxWidth:.infinity,alignment:.leading).card() }.foregroundStyle(.primary)
            }
            if let error = page.error { Text(error).foregroundStyle(.orange) }
        }.task { await load() }.refreshable { await load() }
    }
    func userLabel(_ user: JSONValue) -> some View { HStack { Text(user["name"].string); AccountBadge(kind:user["badgeType"].string) } }
    func load() async { await page.load("/api/friends",store:store,query:["limit":"100"]); await requests.load("/api/friends/requests",store:store) }
    func action(_ path: String, body: [String:String] = [:]) async { do { try await API.shared.send(path,value:body); await load() } catch { store.error = error.localizedDescription } }
}
struct PublicProfileView: View {
    @EnvironmentObject var store: AppStore
    let id: String
    @StateObject private var page = CachedPage()
    var body: some View {
        WanyScroll {
            HStack { Text(page.value["profile"]["user"]["name"].string).font(.largeTitle.bold()); AccountBadge(kind:page.value["profile"]["user"]["badgeType"].string) }
            if page.value["profile"]["access"].string == "private" { EmptyState(icon:"lock",title:"حساب خاص",detail:"صاحب الحساب أخفى تفاصيل مكتبته") }
            else {
                Text("المفضلة").font(.headline)
                StoryGrid(stories:page.value["profile"]["favorites"].array.compactMap { store.stories[$0.string] })
            }
        }.task {
            await page.load("/api/profiles/"+id,store:store)
            let keys = page.value["profile"]["favorites"].array.map(\.string)
            if store.online { for start in stride(from:0,to:keys.count,by:40) { if let r = try? await API.shared.get("/api/source/resolve",query:["keys":keys[start..<min(start+40,keys.count)].joined(separator:",")],as:ResolveResponse.self) { for story in r.items { store.remember(story) } } } }
        }
    }
}
struct ActivityView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var page = CachedPage()
    @State private var friends = false
    private let labels = ["started_work":"بدأ قراءة", "progress_reached":"وصل إلى", "completed_work":"أكمل", "favorited_work":"أضاف للمفضلة", "added_to_list":"أضاف إلى قائمة", "created_list":"أنشأ قائمة"]
    var body: some View {
        WanyScroll {
            Text("النشاط").font(.largeTitle.bold())
            Picker("النشاط",selection:$friends) { Text("نشاطي").tag(false); Text("الأصدقاء").tag(true) }.pickerStyle(.segmented).onChange(of:friends) { _,_ in Task { await load() } }
            ForEach(Array(page.value["events"].array.enumerated()),id:\.offset) { _,event in VStack(alignment:.leading,spacing:8) {
                HStack { Text(event["user"]["name"].string).bold(); AccountBadge(kind:event["user"]["badgeType"].string) }
                Text(labels[event["type"].string] ?? event["type"].string).font(.caption).foregroundStyle(.secondary)
                if let story = store.stories[event["mangaId"].string] { NavigationLink(story.title) { StoryView(initial:story) } }
                if event["chapterNumber"].number > 0 { Text("الفصل \(chapterNumber(event["chapterNumber"].number))").font(.caption) }
                if !event["list"]["name"].string.isEmpty { Text(event["list"]["name"].string) }
            }.frame(maxWidth:.infinity,alignment:.leading).card() }
        }.task { await load() }.refreshable { await load() }
    }
    func load() async { await page.load(friends ? "/api/activity/friends" : "/api/activity/me",store:store,query:["limit":"50","offset":"0"]) }
}
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @State private var editingName = false
    @State private var name = ""
    @State private var logout = false
    @State private var compress = false
    var body: some View {
        WanyScroll {
            VStack(alignment:.leading,spacing:16) {
                Text("الحساب").font(.headline)
                Button { name = store.state?.user.name ?? ""; editingName = true } label: { settingsRow("الاسم الظاهر",value:store.state?.user.name ?? "",icon:"pencil") }.disabled(!store.online)
                Divider()
                NavigationLink { AvatarPickerView() } label: { settingsRow("الصورة الشخصية",icon:"person.crop.circle") }
                Divider()
                Toggle("حساب خاص",isOn:Binding(get:{store.state?.user.profileVisibility == "private"},set:{ value in Task { do { try await API.shared.send("/api/profile/visibility",method:"PUT",value:["visibility":value ? "private" : "public"]); await store.refresh() } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } } } })).disabled(!store.online)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                Text("التنزيلات والمساحة").font(.headline)
                Toggle("التنزيل عبر Wi-Fi فقط",isOn:Binding(get:{downloads.wifiOnly},set:{downloads.wifiOnly = $0}))
                Divider()
                Picker("جودة الصور",selection:Binding(get:{downloads.quality},set:{downloads.quality = $0})) { ForEach(ImageQuality.allCases) { quality in Text(quality.label).tag(quality) } }
                Text("المتوازنة تقلل الحجم مع وضوح مناسب للقراءة. تؤثر الجودة على الصور الجديدة؛ استخدم الزر أدناه لتقليل التنزيلات الموجودة.").font(.caption).foregroundStyle(.secondary)
                settingsRow("التنزيلات المحفوظة",value:byteLabel(downloads.savedJobs.reduce(0){$0+$1.bytes}))
                settingsRow("صور القراءة المؤقتة",value:byteLabel(downloads.temporaryBytes))
                Text("صور القراءة العادية تُحذف بعد 3 دقائق من مغادرة الفصل، أو عند فتح التطبيق مجددًا إذا كان مغلقًا. تقدمك يبقى محفوظًا.").font(.caption).foregroundStyle(.secondary)
                Button { compress = true } label: { settingsRow(downloads.compacting ? downloads.compactProgress : "تقليل حجم التنزيلات الموجودة",icon:"arrow.down.right.and.arrow.up.left") }.disabled(downloads.compacting || downloads.savedJobs.isEmpty)
                Button { downloads.cleanTemporary(all:true) } label: { settingsRow("مسح الصور المؤقتة الآن",icon:"trash") }.disabled(downloads.temporaryBytes == 0)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                Text("المزامنة").font(.headline)
                settingsRow("التحديثات المعلقة",value:String(store.state?.pending.count ?? 0))
                if let date = store.state?.lastSynced { Text("آخر مزامنة: " + date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                Button { Task { await store.refresh() } } label: { settingsRow(store.syncing ? "جاري المزامنة…" : "مزامنة الآن",icon:"arrow.clockwise") }.disabled(!store.online || store.syncing)
            }.card()
            VStack(alignment:.leading,spacing:16) {
                Text(AppVersion.display).font(.subheadline)
                NavigationLink { UpdatesView() } label: { settingsRow("سجل التحديثات",icon:"clock.arrow.circlepath") }
            }.card()
            Button(role:.destructive) { logout = true } label: { Text("تسجيل الخروج").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }.card()
        }.buttonStyle(.plain).navigationTitle("الإعدادات")
        .alert("الاسم الظاهر",isPresented:$editingName) {
            TextField("اسمك",text:$name)
            Button("حفظ") { Task { do { try await API.shared.send("/api/profile/name",method:"PUT",value:["name":name]); await store.refresh() } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } } } }
            Button("إلغاء",role:.cancel) {}
        }
        .confirmationDialog("تقليل الحجم بجودة متوازنة أو الجودة المحددة؟ لا يمكن استعادة الصورة الأصلية إلا بإعادة تنزيلها.",isPresented:$compress) { Button("تقليل الحجم") { Task { await downloads.compactSaved() } } }
        .confirmationDialog("تسجيل الخروج؟ تبقى التنزيلات والتقدم محفوظة لحسابك.",isPresented:$logout) { Button("تسجيل الخروج",role:.destructive) { Task { await store.logout() } } }
    }
    func settingsRow(_ title: String, value: String = "", icon: String? = nil) -> some View {
        HStack(spacing:12) { Text(title).foregroundStyle(.primary); Spacer(minLength:10); if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(.secondary) }; if let icon { Image(systemName:icon).foregroundStyle(Theme.accent) } }.frame(minHeight:44).contentShape(Rectangle())
    }
}
struct AvatarPickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var page = CachedPage()
    var body: some View {
        List { ForEach(Array(page.value["series"].array.enumerated()),id:\.offset) { _,series in
            Section(series["name"].string) { ForEach(Array(series["avatars"].array.enumerated()),id:\.offset) { _,avatar in
                Button { Task { do { try await API.shared.send("/api/profile/avatar",method:"PUT",value:["avatarId":avatar["id"].string]); await store.refresh(); dismiss() } catch { store.error = error.localizedDescription } } } label: {
                    HStack { if var account = store.state?.user { let _ = account.avatarId = avatar["id"].string; ProfileAvatar(user:account).frame(width:42,height:42) }; Text(avatar["characterName"].string) }
                }.disabled(!store.online)
            } }
        } }.navigationTitle("الصورة الشخصية").task { await page.load("/api/avatars",store:store) }
    }
}
