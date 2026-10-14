import SwiftUI

@MainActor final class CachedPage: ObservableObject {
    @Published var value: JSONValue = .null
    @Published var loading = false
    @Published var error: String?
    func load(_ path: String, store: AppStore, query: [String:String] = [:]) async {
        guard let owner = store.state?.user.id else { return }
        let filename = "api/"+Disk.hash(path + query.sorted {$0.key<$1.key}.description)+".json"
        if let cached = Disk.read(JSONValue.self,owner:owner,name:filename) { value = cached }
        guard store.online, !loading else { return }; loading = true; defer { loading = false }
        do {
            let response = try await API.shared.get(path,query:query,as:JSONValue.self)
            guard store.state?.user.id == owner else { return }
            value = response; error = nil; try Disk.save(value,owner:owner,name:filename)
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
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
        .sheet(isPresented:$adding) { NavigationStack { List(store.stories.values.sorted {$0.title<$1.title}) { story in Button(story.title) { Task { do { try await API.shared.send("/api/lists/"+id+"/items",value:["mangaId":story.key]); adding = false; await load() } catch { store.error = error.localizedDescription } } } }.navigationTitle("إضافة قصة للقائمة").toolbar { Button("إغلاق") { adding = false } } } }
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
    @State private var wifiOnly = false
    @State private var name = ""
    @State private var privateProfile = false
    @State private var logout = false
    var body: some View {
        Form {
            Section("التنزيلات") {
                Toggle("تحميل عبر Wi-Fi فقط",isOn:$wifiOnly).onChange(of:wifiOnly) { _,value in downloads.wifiOnly = value }
                LabeledContent("المساحة المستخدمة",value:byteLabel(downloads.jobs.reduce(0){$0+$1.bytes}))
                Text("يمكن إيقاف التحميل واستكماله من صفحة التنزيلات. عند إغلاق التطبيق بالقوة يتوقف عمل الخلفية حتى فتحه مجددًا.").font(.caption).foregroundStyle(.secondary)
            }
            Section("الحساب") {
                TextField("الاسم الظاهر",text:$name)
                Button("حفظ الاسم") { Task { do { try await API.shared.send("/api/profile/name",method:"PUT",value:["name":name]); await store.refresh() } catch { store.error = error.localizedDescription } } }.disabled(!store.online)
                NavigationLink("الصورة الشخصية") { AvatarPickerView() }
                Toggle("حساب خاص",isOn:$privateProfile).onChange(of:privateProfile) { _,value in if (store.state?.user.profileVisibility == "private") != value { Task { do { try await API.shared.send("/api/profile/visibility",method:"PUT",value:["visibility":value ? "private" : "public"]); await store.refresh() } catch { store.error = error.localizedDescription; privateProfile = store.state?.user.profileVisibility == "private" } } } }.disabled(!store.online)
            }
            Section("المزامنة") {
                LabeledContent("التحديثات المعلقة",value:String(store.state?.pending.count ?? 0))
                if let date = store.state?.lastSynced { LabeledContent("آخر مزامنة",value:date.formatted(date:.abbreviated,time:.shortened)) }
                Button("مزامنة الآن") { Task { await store.refresh() } }.disabled(!store.online || store.syncing)
            }
            Section { Button("تسجيل الخروج",role:.destructive) { logout = true } }
            Section { HStack { Image("Logo").resizable().frame(width:32,height:32).clipShape(RoundedRectangle(cornerRadius:8)); Text(AppVersion.display); Spacer() }; NavigationLink("سجل التحديثات") { UpdatesView() }; Text("قصصك وتقدمك محفوظة داخل التطبيق. النسخة الأولى للآيفون.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("الإعدادات")
        .onAppear { wifiOnly = downloads.wifiOnly; name = store.state?.user.name ?? ""; privateProfile = store.state?.user.profileVisibility == "private" }
        .confirmationDialog("تسجيل الخروج؟ تبقى التنزيلات والتحديثات المعلقة محفوظة لهذا الحساب حتى تسجيل دخوله مجددًا.",isPresented:$logout) { Button("تسجيل الخروج",role:.destructive) { Task { await store.logout() } } }
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
