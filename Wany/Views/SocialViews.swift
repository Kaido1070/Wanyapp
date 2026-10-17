import SwiftUI

enum FriendRelation: String, CaseIterable {
    case none, pending_sent, pending_received, friends
    var label: String { switch self { case .none:return "إضافة صديق"; case .pending_sent:return "طلب مرسل · إلغاء"; case .pending_received:return "قبول الطلب"; case .friends:return "صديق" } }
}
struct FriendsView: View {
    @EnvironmentObject var store: AppStore
    @State private var friends: [JSONValue] = []
    @State private var incoming: [JSONValue] = []
    @State private var outgoing: [JSONValue] = []
    @State private var results: [JSONValue] = []
    @State private var relations: [String:String] = [:]
    @State private var query=""
    @State private var busy=false
    @State private var error: String?
    @State private var removing: String?
    @State private var confirmRemove=false
    @State private var hasMore=false
    @State private var offset=0
    var body: some View {
        WanyScroll {
            HStack { Text("الأصدقاء").font(.largeTitle.bold()); Spacer(); if store.incomingFriendRequests>0 { Text("\(store.incomingFriendRequests) طلب جديد").font(.caption).foregroundStyle(Theme.accent) } }
            HStack {
                TextField("اسم المستخدم",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).onSubmit { Task { await search() } }
                Button("بحث") { Task { await search() } }.disabled(busy || !store.online)
            }.card()
            ForEach(Array(results.enumerated()),id:\.offset) { _,entry in row(entry["user"],fallback:entry["relationship"].string) }
            if !incoming.isEmpty { Text("الطلبات الواردة").font(.headline) }
            ForEach(Array(incoming.enumerated()),id:\.offset) { _,entry in
                let id=entry["user"]["id"].string
                if relation(id,fallback:"pending_received") == .pending_received { row(entry["user"],fallback:"pending_received") }
            }
            if !outgoing.isEmpty { Text("الطلبات المرسلة").font(.headline) }
            ForEach(Array(outgoing.enumerated()),id:\.offset) { _,entry in
                let id=entry["user"]["id"].string
                if relation(id,fallback:"pending_sent") == .pending_sent { row(entry["user"],fallback:"pending_sent") }
            }
            Text("أصدقاؤك").font(.headline)
            ForEach(Array(friends.enumerated()),id:\.offset) { _,entry in
                if relation(entry["user"]["id"].string,fallback:"friends") == .friends { row(entry["user"],fallback:"friends") }
            }
            if hasMore { Button("تحميل أصدقاء آخرين") { Task { await load(more:true) } }.disabled(busy || !store.online) }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.orange); Button("إعادة المحاولة") { Task { await load() } } }
        }.task(id:store.state?.user.id) { await load() }.refreshable { await load() }
            .confirmationDialog("حذف الصديق؟",isPresented:$confirmRemove,titleVisibility:.visible) { Button("حذف الصديق",role:.destructive) { if let removing { Task { await action(removing,operation:"remove") } } }; Button("إلغاء",role:.cancel) {} }
    }
    private func relation(_ id: String,fallback: String) -> FriendRelation { FriendRelation(rawValue:relations[id] ?? fallback) ?? .none }
    private func row(_ user: JSONValue,fallback: String) -> some View {
        let id=user["id"].string, status=relation(id,fallback:fallback)
        return HStack(spacing:12) {
            WanyLink { PublicProfileView(id:id) } label: { PublicAccountIdentity(user:user).foregroundStyle(.primary) }
            Spacer()
            if status == .friends {
                Menu { Button("حذف الصديق",role:.destructive) { removing=id; confirmRemove=true } } label: { Label("صديق",systemImage:"person.crop.circle.badge.checkmark") }
            } else {
                Button(status.label) { Task { await action(id,operation:status == .pending_sent ? "cancel" : (status == .pending_received ? "accept" : "add")) } }
                if status == .pending_received { Button("رفض") { Task { await action(id,operation:"reject") } } }
            }
        }.font(.subheadline).card().disabled(busy || !store.online)
    }
    private func search() async {
        guard store.online,let owner=store.state?.user.id else { return }
        do {
            let result=try await API.shared.get("/api/friends/search",query:["q":query],as:JSONValue.self)
            guard store.state?.user.id == owner else { return }; results=result["results"].array
        } catch { store.report(error); self.error=error.localizedDescription }
    }
    private func load(more: Bool = false) async {
        guard !busy,store.online,let owner=store.state?.user.id else { return }
        busy=true; error=nil; defer { busy=false }
        do {
            let page=try await API.shared.get("/api/friends",query:["limit":"100","offset":String(more ? offset : 0)],as:JSONValue.self)
            let requests=try await API.shared.get("/api/friends/requests",as:JSONValue.self)
            guard store.state?.user.id == owner else { return }
            let loaded=page["friends"].array
            if !more { friends=[]; relations=[:] }
            var seen=Set(friends.map { $0["user"]["id"].string })
            friends += loaded.filter { seen.insert($0["user"]["id"].string).inserted }
            offset=(more ? offset : 0)+loaded.count; hasMore=page["hasMore"].boolean && !loaded.isEmpty
            incoming=requests["incoming"].array; outgoing=requests["outgoing"].array
            store.incomingFriendRequests=Int(requests["incomingCount"].number)
        } catch { store.report(error); self.error=error.localizedDescription }
    }
    private func action(_ id: String,operation: String) async {
        guard !busy,let owner=store.state?.user.id else { return }; busy=true; error=nil
        do {
            let path: String,method: String
            switch operation {
            case "add":path="/api/friends"; method="POST"
            case "accept","reject":path="/api/friends/requests/"+apiComponent(id)+"/"+operation; method="POST"
            case "cancel":path="/api/friends/requests/"+apiComponent(id); method="DELETE"
            default:path="/api/friends/"+apiComponent(id); method="DELETE"
            }
            let response=try await API.shared.getMutation(path,value:["userId":id],method:method)
            guard store.state?.user.id == owner else { busy=false; return }
            relations[id]=response["relationship"].string.isEmpty ? (operation == "accept" ? "friends" : "none") : response["relationship"].string
            busy=false; await load(); if !query.isEmpty { await search() }
            NotificationCenter.default.post(name:.ranyRelationshipsChanged,object:owner)
        } catch { busy=false; store.report(error); self.error=error.localizedDescription }
    }
}

struct PublicProfileView: View {
    @EnvironmentObject var store: AppStore
    let id: String
    @StateObject private var page=CachedPage()
    private var profile: JSONValue { page.value["profile"] }
    private var publicAccess: Bool { ["public","owner"].contains(profile["access"].string) }
    var body: some View {
        WanyScroll {
            PublicAccountIdentity(user:profile["user"],large:true)
            if profile["access"].string == "private" { EmptyState(icon:"lock",title:"حساب خاص",detail:"صاحب الحساب أخفى تفاصيله. لا تسمح الصداقة وحدها بعرض سجل القراءة.") }
            else if ["public","owner","friends"].contains(profile["access"].string) {
                if publicAccess { statistics; reading; activity; friends }
                ForEach(Array(profile["sections"].array.enumerated()),id:\.offset) { _,section in
                    if section["type"].string == "favorites" { favorites }
                    else if section["type"].string == "list",let list=profile["lists"].array.first(where:{$0["id"].string == section["referenceId"].string}) { listSection(list) }
                }
                if profile["sections"].array.isEmpty { favorites; ForEach(Array(profile["lists"].array.enumerated()),id:\.offset) { _,list in listSection(list) } }
                if !publicAccess { Label("نشاط القراءة والإحصائيات والأصدقاء غير متاحة في هذا الملف",systemImage:"lock").font(.caption).foregroundStyle(.secondary) }
            }
            if page.loading { ProgressView() }
            if let error=page.error { Text(error).foregroundStyle(.orange); Button("إعادة المحاولة") { Task { await load() } } }
            if !store.online { Text("تحتاج الملفات العامة اتصالًا للتحقق من صلاحية عرضها.").font(.caption).foregroundStyle(.secondary) }
        }.task(id:store.state?.user.id) { await load() }.refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for:.ranyRelationshipsChanged)) { _ in Task { await load() } }
    }
    private var favorites: some View { VStack(alignment:.leading,spacing:12) { Text("المفضلة").font(.headline); StoryGrid(stories:profile["favorites"].array.compactMap { store.stories[$0.string] }) } }
    private var statistics: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("الإحصائيات العامة").font(.headline)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())]) {
                ForEach([("works","قصة"),("chaptersRead","فصل"),("reading","أقرأ الآن"),("lists","قائمة"),("friends","صديق")],id:\.0) { field in
                    VStack { Text("\(Int(profile["stats"][field.0].number))").font(.title3.bold()).foregroundStyle(Theme.accent); Text(field.1).font(.caption) }
                }
            }
        }.card()
    }
    private var reading: some View {
        VStack(alignment:.leading,spacing:12) { Text("أقرأ الآن").font(.headline); StoryGrid(stories:profile["library"].array.compactMap { store.stories[$0["mangaId"].string] }) }
    }
    private var activity: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("النشاط المسموح بمشاهدته").font(.headline)
            ForEach(Array(profile["activity"].array.enumerated()),id:\.offset) { _,event in ActivityEventRow(event:event) }
        }
    }
    private var friends: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("الأصدقاء").font(.headline)
            ForEach(Array(profile["friends"].array.enumerated()),id:\.offset) { _,user in WanyLink { PublicProfileView(id:user["id"].string) } label: { PublicAccountIdentity(user:user).foregroundStyle(.primary).card() } }
        }
    }
    private func listSection(_ list: JSONValue) -> some View {
        VStack(alignment:.leading,spacing:10) {
            WanyLink { ListDetailView(id:list["id"].string,title:list["name"].string) } label: { Label(list["name"].string,systemImage:ListIcons.symbol(list["iconKey"].string)).foregroundStyle(.primary) }
            if !list["description"].string.isEmpty { Text(list["description"].string).font(.caption).foregroundStyle(.secondary) }
            StoryGrid(stories:list["previewItems"].array.compactMap { store.stories[$0.string] })
        }.card()
    }
    private func load() async {
        await page.load("/api/profiles/"+apiComponent(id),store:store)
        let accessible=profile["access"].string
        guard ["public","owner","friends"].contains(accessible) else { return }
        var keys=profile["favorites"].array.map(\.string)+profile["lists"].array.flatMap { $0["previewItems"].array.map(\.string) }
        if publicAccess { keys += profile["library"].array.map { $0["mangaId"].string }; keys += profile["activity"].array.map { $0["mangaId"].string } }
        await store.resolveMetadata(keys)
    }
}

struct ActivityEventRow: View {
    @EnvironmentObject var store: AppStore
    let event: JSONValue
    private let labels=["started_work":"بدأ قراءة","progress_reached":"وصل إلى","completed_work":"أكمل","favorited_work":"أضاف للمفضلة","added_to_list":"أضاف إلى قائمة","created_list":"أنشأ قائمة"]
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            PublicAccountIdentity(user:event["user"])
            Text(labels[event["type"].string] ?? "نشاط").font(.caption).foregroundStyle(.secondary)
            if let story=store.stories[event["mangaId"].string],story.title != story.key { WanyLink(story.title) { StoryView(initial:story) } }
            else if !event["mangaId"].string.isEmpty { Text("بيانات القصة غير متاحة حاليًا").font(.caption).foregroundStyle(.secondary) }
            if event["chapterNumber"].number>0 { Text("الفصل \(chapterNumber(event["chapterNumber"].number))").font(.caption) }
            if !event["list"]["name"].string.isEmpty { Text(event["list"]["name"].string).font(.caption) }
        }.frame(maxWidth:.infinity,alignment:.leading).card()
    }
}
