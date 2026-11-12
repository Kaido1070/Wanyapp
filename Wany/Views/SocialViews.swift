import SwiftUI

enum FriendRelation: String, CaseIterable {
    case none, pending_sent, pending_received, friends
    var label: String { switch self { case .none:return "إضافة صديق"; case .pending_sent:return "طلب مرسل · إلغاء"; case .pending_received:return "قبول الطلب"; case .friends:return "صديق" } }
}
struct FriendsView: View {
    @Environment(AppStore.self) private var store
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
            WanyLink(.publicProfile(id)) { PublicAccountIdentity(user:user).foregroundStyle(.primary) }
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

// A friend's page laid out like the reader's own account page in Rany: the glass
// identity card with the friendship action, a tools row with the numbers, then
// their library with the same three tabs, recent activity and friends.
struct PublicProfileView: View {
    @Environment(AppStore.self) private var store
    let id: String
    @StateObject private var page=CachedPage()
    @State private var relationOverride: String?
    @State private var busy=false
    @State private var actionError: String?
    @State private var confirmRemove=false
    @State private var tab="reading"
    @State private var listID=""
    private var profile: JSONValue { page.value["profile"] }
    private var access: String { profile["access"].string }
    private var relation: FriendRelation { FriendRelation(rawValue:relationOverride ?? profile["relationship"].string) ?? .none }
    private var lists: [JSONValue] { profile["lists"].array }
    private var keys: [String] {
        switch tab {
        case "favorites": return profile["favorites"].array.map(\.string)
        case "lists": return lists.first { $0["id"].string == listID }?["previewItems"].array.map(\.string) ?? []
        default: return profile["library"].array.filter { $0["status"].string == "reading" }.map { $0["mangaId"].string }
        }
    }
    var body: some View {
        WanyScroll {
            if let account=profile["user"].publicAccount { identity(account) }
            if let actionError { Text(actionError).font(.caption).foregroundStyle(.orange) }
            if access == "private" {
                EmptyState(icon:"lock",title:"حساب خاص",detail:"صاحب الحساب أخفى تفاصيله. تظهر لك بعد ما تصيرون أصدقاء.")
            } else if ["public","owner","friends"].contains(access) {
                details
                library
                if !profile["activity"].array.isEmpty { activity }
                if !profile["friends"].array.isEmpty { friends }
            }
            if page.loading && profile["user"].publicAccount == nil { ProgressView() }
            if let error=page.error { Text(error).foregroundStyle(.orange); Button("إعادة المحاولة") { Task { await load() } } }
            if !store.online { Text("تحتاج الملفات العامة اتصالًا للتحقق من صلاحية عرضها.").font(.caption).foregroundStyle(.secondary) }
        }.task(id:store.state?.user.id) { await load() }.refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for:.ranyRelationshipsChanged)) { _ in Task { await load() } }
            .confirmationDialog("إزالة من الأصدقاء؟",isPresented:$confirmRemove,titleVisibility:.visible) {
                Button("إزالة",role:.destructive) { Task { await change("remove") } }
                Button("إلغاء",role:.cancel) {}
            }
    }

    // Same card as the reader's own: avatar, name with badge, @username in the
    // accent, and one action on the trailing edge.
    private func identity(_ account: Account) -> some View {
        HStack(spacing:12) {
            ProfileAvatar(user:account).frame(width:54,height:54)
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:2) { Text(account.name).font(.title3.weight(.semibold)).lineLimit(2).layoutPriority(1); AccountBadge(kind:account.badgeType) }
                if !account.username.isEmpty { Text("@"+account.username).font(.subheadline).foregroundStyle(Theme.accent.opacity(0.85)).lineLimit(1) }
            }
            Spacer(minLength:8)
            if access != "owner" { relationAction.disabled(busy || !store.online) }
        }.frame(maxWidth:.infinity,alignment:.leading).card()
    }
    @ViewBuilder private var relationAction: some View {
        switch relation {
        case .friends:
            Menu { Button("إزالة من الأصدقاء",role:.destructive) { confirmRemove=true } } label: { actionLabel("صديق","person.crop.circle.badge.checkmark") }
        case .pending_sent:
            Menu { Button("إلغاء الطلب",role:.destructive) { Task { await change("cancel") } } } label: { actionLabel("مرسل","clock") }
        case .pending_received:
            Menu { Button("قبول الطلب") { Task { await change("accept") } }; Button("رفض",role:.destructive) { Task { await change("reject") } } } label: { actionLabel("طلب","person.badge.clock") }
        case .none:
            Button { Task { await change("add") } } label: { actionLabel("إضافة","person.badge.plus") }.buttonStyle(.plain)
        }
    }
    private func actionLabel(_ title: String,_ icon: String) -> some View {
        VStack(spacing:5) {
            Image(systemName:icon).font(.system(size:14,weight:.semibold))
            Text(title).font(.caption2).lineLimit(1)
        }.foregroundStyle(Theme.accent).frame(width:52,height:48).contentShape(Rectangle())
    }

    // Tools row in the glass group, then the numbers, as on the reader's own page.
    private var details: some View {
        VStack(spacing:12) {
            if relation == .friends {
                HStack(spacing:6) {
                    WanyLink(.conversation(id)) { tool("مراسلة","bubble.left.and.bubble.right") }
                }.buttonStyle(.plain).ranyGlassGroup()
            }
            HStack {
                stat("قصة",profile["stats"]["works"].number)
                Divider().frame(height:32)
                stat("فصل مقروء",profile["stats"]["chaptersRead"].number)
                Divider().frame(height:32)
                stat("صديق",profile["stats"]["friends"].number)
            }
        }.card()
    }
    private func tool(_ title: String,_ icon: String) -> some View {
        VStack(spacing:4) {
            Image(systemName:icon).font(.system(size:15,weight:.medium))
            Text(title).font(.caption2).lineLimit(1)
        }.foregroundStyle(Theme.accent).frame(maxWidth:.infinity,minHeight:52).ranyInsetGlass(radius:10).contentShape(Rectangle())
    }
    private func stat(_ title: String,_ value: Double) -> some View {
        VStack(spacing:6) { Text("\(Int(value))").font(RanyTypography.font(.title2).bold()).foregroundStyle(Theme.accent); Text(title).font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity)
    }

    // Their library with the same three tabs as «مكتبتي».
    private var library: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("مكتبته").font(.headline); Spacer(); Text("\(Int(profile["stats"]["works"].number)) قصة").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing:8) {
                ForEach([("reading","أقرأ حاليًا"),("favorites","المفضلة"),("lists","القوائم")],id:\.0) { pair in
                    Button { tab=pair.0 } label: { Text(pair.1).font(RanyTypography.font(.caption)).frame(maxWidth:.infinity,minHeight:44).background(tab == pair.0 ? Theme.accent.opacity(0.25) : Theme.surface.opacity(0.22),in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
            }
            if tab == "lists" {
                if lists.isEmpty { Text("ما عنده قوائم بعد.").font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary) }
                else {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) {
                            ForEach(Array(lists.enumerated()),id:\.offset) { _,list in
                                Button { listID=list["id"].string } label: { Label(list["name"].string,systemImage:ListIcons.symbol(list["iconKey"].string)).font(RanyTypography.font(.subheadline)).padding(.horizontal,16).frame(minHeight:48).background(listID == list["id"].string ? Theme.accent.opacity(0.25) : Theme.surface.opacity(0.22),in:Capsule()).contentShape(Capsule()) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let list=lists.first(where:{ $0["id"].string == listID }) {
                        WanyLink(.listDetail(id:listID,title:list["name"].string)) { Label("عرض القائمة كاملة",systemImage:"chevron.left").font(.caption).frame(minHeight:44) }
                    }
                }
            }
            if !keys.isEmpty { StoryGrid(stories:keys.compactMap { store.stories[$0] }) }
            else if tab != "lists" || !lists.isEmpty {
                EmptyState(icon:"books.vertical",title:"لا توجد قصص هنا",detail:tab == "reading" ? "ما بدأ قراءة قصة حتى الآن." : "القسم فاضي حاليًا.")
            }
        }.card()
    }
    private var activity: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("آخر النشاط").font(.headline)
            ForEach(Array(profile["activity"].array.enumerated()),id:\.offset) { _,event in ActivityEventRow(event:event) }
        }.card()
    }
    private var friends: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("أصدقاؤه").font(.headline)
            ForEach(Array(profile["friends"].array.enumerated()),id:\.offset) { _,user in WanyLink(.publicProfile(user["id"].string)) { PublicAccountIdentity(user:user).foregroundStyle(.primary).padding(.vertical,4) } }
        }.card()
    }

    private func change(_ operation: String) async {
        guard !busy,let owner=store.state?.user.id else { return }
        busy=true; actionError=nil; defer { busy=false }
        do {
            let path: String,method: String
            switch operation {
            case "add":path="/api/friends"; method="POST"
            case "accept","reject":path="/api/friends/requests/"+apiComponent(id)+"/"+operation; method="POST"
            case "cancel":path="/api/friends/requests/"+apiComponent(id); method="DELETE"
            default:path="/api/friends/"+apiComponent(id); method="DELETE"
            }
            let response=try await API.shared.getMutation(path,value:["userId":id],method:method)
            guard store.state?.user.id == owner else { return }
            relationOverride=response["relationship"].string.isEmpty ? (operation == "accept" ? "friends" : (operation == "add" ? "pending_sent" : "none")) : response["relationship"].string
            NotificationCenter.default.post(name:.ranyRelationshipsChanged,object:owner)
        } catch { store.report(error); actionError=error.localizedDescription }
    }
    private func load() async {
        await page.load("/api/profiles/"+apiComponent(id),store:store)
        relationOverride=nil
        if !lists.contains(where:{ $0["id"].string == listID }) { listID=lists.first?["id"].string ?? "" }
        guard ["public","owner","friends"].contains(access) else { return }
        var keys=profile["favorites"].array.map(\.string)+lists.flatMap { $0["previewItems"].array.map(\.string) }
        keys += profile["library"].array.map { $0["mangaId"].string }; keys += profile["activity"].array.map { $0["mangaId"].string }
        await store.resolveMetadata(keys)
    }
}

// One compact line per event: small avatar, who did what and when, then the story.
struct ActivityEventRow: View {
    @Environment(AppStore.self) private var store
    let event: JSONValue
    private let labels=["started_work":"بدأ قراءة","progress_reached":"وصل إلى","completed_work":"أكمل","favorited_work":"أضاف للمفضلة","added_to_list":"أضاف إلى قائمة","created_list":"أنشأ قائمة"]
    var body: some View {
        let account=event["user"].publicAccount
        HStack(alignment:.top,spacing:10) {
            if let account { ProfileAvatar(user:account).frame(width:32,height:32) }
            VStack(alignment:.leading,spacing:3) {
                HStack(spacing:4) {
                    if let account {
                        Text(account.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if account.badgeType == "crown" || account.badgeType == "verified" {
                            Image(account.badgeType == "crown" ? "crown" : "verified").resizable().frame(width:14,height:14).accessibilityHidden(true)
                        }
                    }
                    Text(labels[event["type"].string] ?? "نشاط").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength:4)
                    if let when=ActivityEventRow.relative(event["createdAt"].string) { Text(when).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
                HStack(spacing:4) {
                    if let story=store.stories[event["mangaId"].string],story.title != story.key { WanyLink(story.title,route:.story(story)).font(.footnote.weight(.medium)).lineLimit(1) }
                    else if !event["mangaId"].string.isEmpty { Text("بيانات القصة غير متاحة حاليًا").font(.caption).foregroundStyle(.secondary) }
                    if event["chapterNumber"].number>0 { Text("· الفصل \(chapterNumber(event["chapterNumber"].number))").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if !event["list"]["name"].string.isEmpty { Text(event["list"]["name"].string).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(.horizontal,12).padding(.vertical,9)
        .ranyGlass(radius:14)
    }
    private static let parser: ISO8601DateFormatter = { let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]; return f }()
    private static let plainParser=ISO8601DateFormatter()
    private static let formatter: RelativeDateTimeFormatter = { let f=RelativeDateTimeFormatter(); f.locale=Locale(identifier:"ar"); f.unitsStyle = .short; return f }()
    static func relative(_ text: String) -> String? {
        guard let date=parser.date(from:text) ?? plainParser.date(from:text) else { return nil }
        return formatter.localizedString(for:date,relativeTo:Date())
    }
}
