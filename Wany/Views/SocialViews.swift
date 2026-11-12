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

// Mirrors the website's friend page: the account card with the friendship action,
// the reading numbers, the lists as cover tiles, what they read now, their recent
// activity and their friends.
struct PublicProfileView: View {
    @Environment(AppStore.self) private var store
    let id: String
    @StateObject private var page=CachedPage()
    @State private var relationOverride: String?
    @State private var busy=false
    @State private var actionError: String?
    @State private var confirmRemove=false
    private var profile: JSONValue { page.value["profile"] }
    private var access: String { profile["access"].string }
    private var relation: FriendRelation { FriendRelation(rawValue:relationOverride ?? profile["relationship"].string) ?? .none }
    private var readingEntries: [JSONValue] { profile["library"].array.filter { $0["status"].string == "reading" } }
    var body: some View {
        WanyScroll {
            if profile["user"].publicAccount != nil { identityCard }
            if let actionError { Text(actionError).font(.caption).foregroundStyle(.orange) }
            if access == "private" {
                EmptyState(icon:"lock",title:"حساب خاص",detail:"صاحب الحساب أخفى تفاصيله. تظهر لك بعد ما تصيرون أصدقاء.")
            } else if ["public","owner","friends"].contains(access) {
                statistics
                listsSection
                readingSection
                activitySection
                if !profile["friends"].array.isEmpty { friendsSection }
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

    // Avatar with the gold ring, name and badge, then the friend count and the action.
    private var identityCard: some View {
        HStack(spacing:12) {
            if let account=profile["user"].publicAccount {
                ProfileAvatar(user:account).frame(width:64,height:64)
                    .overlay(Circle().stroke(Theme.accent,lineWidth:2))
                    .shadow(color:Theme.accent.opacity(0.18),radius:10)
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:4) { Text(account.name).font(.title3.weight(.semibold)).lineLimit(2).layoutPriority(1); AccountBadge(kind:account.badgeType) }
                    if !account.username.isEmpty { Text("@"+account.username).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength:6)
            VStack(alignment:.trailing,spacing:8) {
                if access != "private" {
                    HStack(spacing:4) { Text("\(Int(profile["stats"]["friends"].number))").font(.subheadline.bold()); Text("الأصدقاء").font(.caption2).foregroundStyle(.secondary) }
                        .padding(.horizontal,10).frame(minHeight:32).ranyInsetGlass(radius:10)
                }
                if access != "owner" { relationButton }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).card()
    }
    @ViewBuilder private var relationButton: some View {
        switch relation {
        case .friends: pill("إزالة من الأصدقاء") { confirmRemove=true }
        case .pending_sent: pill("إلغاء الطلب") { Task { await change("cancel") } }
        case .pending_received:
            HStack(spacing:6) { pill("رفض") { Task { await change("reject") } }; pill("قبول",primary:true) { Task { await change("accept") } } }
        case .none: pill("إضافة صديق",primary:true) { Task { await change("add") } }
        }
    }
    private func pill(_ title: String,primary: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(primary ? Color.black : Color.primary)
                .padding(.horizontal,12).frame(minHeight:44)
                .background(primary ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.06)),in:Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(primary ? 0 : 0.12),lineWidth:1))
        }.buttonStyle(.plain).disabled(busy || !store.online)
    }

    // The same three numbers as the website.
    private var statistics: some View {
        HStack(spacing:0) {
            metric("فصول مقروءة",profile["stats"]["chaptersRead"].number)
            Divider().frame(height:40)
            metric("قصص",profile["stats"]["works"].number)
            Divider().frame(height:40)
            metric("أقرأ الآن",profile["stats"]["reading"].number)
        }.padding(.vertical,12).card()
    }
    private func metric(_ title: String,_ value: Double) -> some View {
        VStack(spacing:6) { Text("\(Int(value))").font(RanyTypography.font(.title2).bold()).foregroundStyle(Theme.accent); Text(title).font(RanyTypography.font(.caption)).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth:.infinity)
    }

    // Favorites and each list as a tile with a 2×2 cover collage.
    private var listsSection: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("القوائم").font(.title3.weight(.semibold))
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:10) {
                    tile(title:"المفضلة",icon:"bookmark",count:Int(profile["favoriteCount"].number),keys:profile["favorites"].array.map(\.string))
                    ForEach(Array(profile["lists"].array.enumerated()),id:\.offset) { _,list in
                        WanyLink(.listDetail(id:list["id"].string,title:list["name"].string)) {
                            tile(title:list["name"].string,icon:ListIcons.symbol(list["iconKey"].string),count:Int(list["itemCount"].number),keys:list["previewItems"].array.map(\.string))
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical,2)
            }
        }
    }
    private func tile(title: String,icon: String,count: Int,keys: [String]) -> some View {
        let stories=keys.prefix(4).compactMap { store.stories[$0] }
        return VStack(alignment:.leading,spacing:8) {
            LazyVGrid(columns:[GridItem(.flexible(),spacing:3),GridItem(.flexible(),spacing:3)],spacing:3) {
                ForEach(0..<4,id:\.self) { index in
                    Group {
                        if index < stories.count { CoverView(story:stories[index]) }
                        else { Theme.surface.overlay(index == 0 && stories.isEmpty ? Image(systemName:"plus").foregroundStyle(.secondary) : nil) }
                    }.frame(height:56).clipShape(RoundedRectangle(cornerRadius:6))
                }
            }.clipShape(RoundedRectangle(cornerRadius:10))
            Label(title,systemImage:icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
            Text("\(count) قصص").font(.caption2).foregroundStyle(.secondary)
        }.padding(8).frame(width:150).ranyGlass(radius:16)
    }

    private var readingSection: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("أقرأ الآن").font(.title3.weight(.semibold))
            let stories=readingEntries.compactMap { store.stories[$0["mangaId"].string] }
            if stories.isEmpty { emptyNote("ما بدأ قراءة أي قصة حتى الآن.") }
            else { StoryGrid(stories:stories) }
        }
    }
    private var activitySection: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("آخر النشاط").font(.title3.weight(.semibold))
            if profile["activity"].array.isEmpty { emptyNote("لا يوجد نشاط حتى الآن.") }
            ForEach(Array(profile["activity"].array.enumerated()),id:\.offset) { _,event in ActivityEventRow(event:event) }
        }
    }
    private var friendsSection: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("الأصدقاء").font(.title3.weight(.semibold))
            ForEach(Array(profile["friends"].array.enumerated()),id:\.offset) { _,user in WanyLink(.publicProfile(user["id"].string)) { PublicAccountIdentity(user:user).foregroundStyle(.primary).card() } }
        }
    }
    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            .padding(16).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(style:StrokeStyle(lineWidth:1,dash:[5,4])).foregroundStyle(Color.white.opacity(0.14)))
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
        guard ["public","owner","friends"].contains(access) else { return }
        var keys=profile["favorites"].array.map(\.string)+profile["lists"].array.flatMap { $0["previewItems"].array.map(\.string) }
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
