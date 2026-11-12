import SwiftUI

// Messages between friends: text and shared stories or chapters. Nothing polls:
// the unread count arrives with the account refresh, and a conversation is read
// when it is opened, pulled down, or the app comes back to the foreground.

struct ChatMessage: Identifiable, Equatable {
    let id: Int
    let mine: Bool
    let body: String
    let mangaId: String?
    let chapter: Double?
    let createdAt: Double
    init(_ value: JSONValue) {
        id = Int(value["id"].number)
        mine = value["mine"].boolean
        body = value["body"].string
        mangaId = value["mangaId"].string.isEmpty ? nil : value["mangaId"].string
        if case .number(let number) = value["chapter"] { chapter = number } else { chapter = nil }
        createdAt = value["createdAt"].number
    }
}

enum ChatTime {
    private static let clock: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier:"ar"); f.dateFormat = "h:mm a"; return f }()
    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier:"ar"); f.dateFormat = "EEEE، d MMMM"; return f }()
    private static let short: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier:"ar"); f.dateFormat = "d MMM"; return f }()
    static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970:ms/1000) }
    static func clockText(_ ms: Double) -> String { clock.string(from:date(ms)) }
    static func dayText(_ ms: Double) -> String {
        let value = date(ms), calendar = Calendar.current
        if calendar.isDateInToday(value) { return "اليوم" }
        if calendar.isDateInYesterday(value) { return "أمس" }
        return day.string(from:value)
    }
    static func listText(_ ms: Double) -> String {
        Calendar.current.isDateInToday(date(ms)) ? clockText(ms) : short.string(from:date(ms))
    }
    static func sameDay(_ a: Double, _ b: Double) -> Bool { Calendar.current.isDate(date(a), inSameDayAs:date(b)) }
}

// A message made only of emoji (up to three) is shown large, without a bubble.
func isEmojiOnly(_ text: String) -> Bool {
    let value = text.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !value.isEmpty else { return false }
    let characters = value.filter { !$0.isWhitespace }
    guard characters.count <= 3 else { return false }
    return characters.allSatisfy { character in
        guard let first = character.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && character.unicodeScalars.count > 1)
    }
}

private func placeholderStory(_ key: String) -> Story {
    Story(key:key,source:sourceFromStoryKey(key),slug:String(key.split(separator:":").dropFirst().joined(separator:":")),type:"",url:"",title:"قصة",cover:"",genres:[])
}

struct MessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var conversations: [JSONValue] = []
    @State private var friends: [Account] = []
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        WanyScroll {
            if let error { VStack(spacing:10) { Text(error).foregroundStyle(.orange); Button("إعادة المحاولة") { Task { await load() } } }.card() }
            if !loaded && error == nil { ProgressView().frame(maxWidth:.infinity).padding(.vertical,30) }
            ForEach(Array(conversations.enumerated()),id:\.offset) { _,row in
                if let user = row["user"].publicAccount { conversationRow(row,user:user) }
            }
            let talking = Set(conversations.map { $0["user"]["id"].string })
            let others = friends.filter { !talking.contains($0.id) }
            if loaded && conversations.isEmpty && others.isEmpty && error == nil {
                EmptyState(icon:"bubble.left.and.bubble.right",title:"الرسائل بين الأصدقاء",detail:"أضف صديقًا من صفحة الأصدقاء لتبدأ.")
            }
            if loaded && !others.isEmpty {
                Text("ابدأ محادثة").font(RanyTypography.font(.headline)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
                ForEach(others) { user in
                    WanyLink(.conversation(user.id)) {
                        HStack(spacing:12) {
                            ProfileAvatar(user:user).frame(width:44,height:44)
                            VStack(alignment:.leading,spacing:3) { Text(user.name).font(.subheadline.weight(.semibold)); Text("@"+user.username).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName:"bubble.left").foregroundStyle(Theme.accent)
                        }.foregroundStyle(.primary).contentShape(Rectangle())
                    }.buttonStyle(.plain).card()
                }
            }
        }
        .navigationTitle("الرسائل").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of:phase) { _,value in if value == .active { Task { await load() } } }
    }
    private func conversationRow(_ row: JSONValue,user: Account) -> some View {
        let unread = Int(row["unread"].number)
        let shared = !row["lastMangaId"].string.isEmpty
        let preview = row["lastBody"].string.isEmpty ? (shared ? "شارك قصة" : "") : row["lastBody"].string
        return WanyLink(.conversation(user.id)) {
            HStack(spacing:12) {
                ProfileAvatar(user:user).frame(width:48,height:48)
                VStack(alignment:.leading,spacing:4) {
                    Text(user.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text((row["lastMine"].boolean ? "أنت: " : "")+preview).font(.caption).foregroundStyle(unread > 0 ? .primary : .secondary).lineLimit(1)
                }
                Spacer(minLength:6)
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)").font(.caption2.bold()).foregroundStyle(.black).padding(.horizontal,7).frame(minWidth:22,minHeight:22).background(Theme.accent,in:Capsule())
                        .accessibilityLabel("\(unread) رسائل جديدة")
                } else {
                    Text(ChatTime.listText(row["lastAt"].number)).font(.caption2).foregroundStyle(.secondary)
                }
            }.foregroundStyle(.primary).contentShape(Rectangle())
        }.buttonStyle(.plain).card()
    }
    private func load() async {
        guard store.online, let owner = store.state?.user.id else { if !store.online { error = "الرسائل تحتاج اتصالًا" }; loaded = true; return }
        do {
            async let list = API.shared.get("/api/messages",as:JSONValue.self)
            async let friendList = API.shared.get("/api/friends",query:["limit":"100"],as:JSONValue.self)
            let (value,people) = try await (list,friendList)
            guard store.state?.user.id == owner else { return }
            conversations = value["conversations"].array
            friends = people["friends"].array.compactMap { $0["user"].publicAccount }
            store.unreadMessages = max(0,Int(value["unread"].number))
            error = nil
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
        loaded = true
    }
}

struct ConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    let friendID: String
    @State private var friend: Account?
    @State private var messages: [ChatMessage] = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingOlder = false
    @State private var sending = false
    @State private var draft = ""
    @State private var error: String?
    @State private var lastLoad = Date.distantPast
    @FocusState private var typing: Bool
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing:0) {
                    if hasMore {
                        Button(loadingOlder ? "جاري التحميل…" : "عرض رسائل أقدم") { Task { await loadOlder(proxy:proxy) } }
                            .buttonStyle(.bordered).disabled(loadingOlder).padding(.bottom,10)
                    }
                    if loading && messages.isEmpty { ProgressView().padding(.vertical,30) }
                    if !loading && messages.isEmpty && error == nil {
                        Text("لا توجد رسائل بعد.\nاكتب أول رسالة، أو شارك قصة من صفحتها.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical,40)
                    }
                    ForEach(Array(messages.enumerated()),id:\.element.id) { index,message in
                        let previous = index > 0 ? messages[index-1] : nil
                        let newDay = previous.map { !ChatTime.sameDay($0.createdAt,message.createdAt) } ?? true
                        let grouped = !newDay && previous?.mine == message.mine && message.createdAt - (previous?.createdAt ?? 0) < 300_000
                        if newDay {
                            Text(ChatTime.dayText(message.createdAt)).font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal,12).padding(.vertical,4).background(Theme.surface,in:Capsule()).padding(.top,14).padding(.bottom,6)
                        }
                        ChatBubble(message:message).padding(.top,grouped ? 3 : 10).id(message.id)
                    }
                }.padding(.horizontal,14).padding(.vertical,10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of:messages.last?.id) { _,last in if let last { withAnimation(.easeOut(duration:0.2)) { proxy.scrollTo(last,anchor:.bottom) } } }
            // The writing box stays at the bottom and rises with the keyboard.
            .safeAreaInset(edge:.bottom,spacing:0) { composer }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden,for:.tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.principal) {
                if let friend {
                    WanyLink(.publicProfile(friend.id)) {
                        HStack(spacing:8) { ProfileAvatar(user:friend).frame(width:30,height:30); Text(friend.name).font(.subheadline.weight(.semibold)).lineLimit(1) }
                    }.buttonStyle(.plain)
                } else { Text("المحادثة") }
            }
        }
        .task(id:friendID) { await load() }
        .refreshable { await load() }
        .onChange(of:phase) { _,value in if value == .active, Date().timeIntervalSince(lastLoad) > 15 { Task { await load() } } }
    }
    private var composer: some View {
        VStack(spacing:6) {
            if let error { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading) }
            HStack(alignment:.bottom,spacing:8) {
                TextField("اكتب رسالة…",text:$draft,axis:.vertical)
                    .lineLimit(1...5).focused($typing)
                    .padding(.horizontal,14).padding(.vertical,11)
                    .background(Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:22,style:.continuous))
                    .onChange(of:draft) { _,value in if value.count > 500 { draft = String(value.prefix(500)) } }
                Button { Task { await send() } } label: {
                    Image(systemName:"paperplane.fill").font(.body.weight(.semibold)).foregroundStyle(.black).frame(width:44,height:44).background(Theme.accent,in:Circle())
                }.disabled(sending || friend == nil || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .opacity(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    .accessibilityLabel("إرسال")
            }
        }
        .padding(.horizontal,14).padding(.top,8).padding(.bottom,8)
        .background(.bar)
    }
    private func load() async {
        guard store.online else { error = "الرسائل تحتاج اتصالًا"; loading = false; return }
        lastLoad = Date()
        do {
            let value = try await API.shared.get("/api/messages/with/"+apiComponent(friendID),as:JSONValue.self)
            friend = value["user"].publicAccount
            let page = value["messages"].array.map(ChatMessage.init)
            // Older pages already shown stay; the newest page replaces its own range.
            let firstNew = page.first?.id ?? Int.max
            messages = messages.filter { $0.id < firstNew } + page
            hasMore = hasMore || value["hasMore"].boolean
            store.unreadMessages = max(0,Int(value["unread"].number))
            error = nil
            await store.resolveMetadata(page.compactMap(\.mangaId))
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
        loading = false
    }
    private func loadOlder(proxy: ScrollViewProxy) async {
        guard let first = messages.first?.id, !loadingOlder else { return }
        loadingOlder = true; defer { loadingOlder = false }
        do {
            let value = try await API.shared.get("/api/messages/with/"+apiComponent(friendID),query:["before":String(first)],as:JSONValue.self)
            let older = value["messages"].array.map(ChatMessage.init)
            messages = older + messages
            hasMore = value["hasMore"].boolean
            // Keep the reader where they were instead of jumping.
            proxy.scrollTo(first,anchor:.top)
            await store.resolveMetadata(older.compactMap(\.mangaId))
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    private func send() async {
        let text = draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        do {
            let value = try await API.shared.getMutation("/api/messages",value:["to":friendID,"body":text])
            messages.append(ChatMessage(value["message"]))
            draft = ""; error = nil
        } catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}

private struct ChatBubble: View {
    @Environment(AppStore.self) private var store
    let message: ChatMessage
    var body: some View {
        let big = message.mangaId == nil && isEmojiOnly(message.body)
        VStack(alignment:.leading,spacing:5) {
            if let key = message.mangaId { sharedWork(key) }
            if !message.body.isEmpty { Text(message.body).font(big ? .system(size:40) : .body).fixedSize(horizontal:false,vertical:true) }
            Text(ChatTime.clockText(message.createdAt)).font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing)
        }
        .padding(.horizontal,big ? 2 : 12).padding(.top,big ? 0 : 9).padding(.bottom,big ? 0 : 6)
        .frame(minWidth:big ? 0 : 76,alignment:.leading)
        .background(big ? Color.clear : (message.mine ? Theme.accent.opacity(0.16) : Theme.surface),in:RoundedRectangle(cornerRadius:18,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(big ? Color.clear : (message.mine ? Theme.accent.opacity(0.28) : Color.white.opacity(0.08)),lineWidth:1))
        // Holding a message offers «نسخ», like any chat app.
        .contextMenu {
            if !message.body.isEmpty {
                Button("نسخ",systemImage:"doc.on.doc") { UIPasteboard.general.string = message.body }
            }
        }
        .frame(maxWidth:320,alignment:message.mine ? .trailing : .leading)
        .frame(maxWidth:.infinity,alignment:message.mine ? .trailing : .leading)
    }
    @ViewBuilder private func sharedWork(_ key: String) -> some View {
        let story = store.stories[key] ?? placeholderStory(key)
        let route: RanyRoute = message.chapter.map { .sourceChapter(key:key,chapter:Chapter(number:$0,title:"الفصل \(chapterNumber($0))"),fallback:story) } ?? .story(story)
        WanyLink(route) {
            // A slim one-line card, so a shared story never fills the screen.
            HStack(spacing:9) {
                CoverView(story:story).frame(width:36,height:50).clipShape(RoundedRectangle(cornerRadius:6))
                VStack(alignment:.leading,spacing:2) {
                    Text(story.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(message.chapter.map { "اقرأ الفصل \(chapterNumber($0))" } ?? "افتح القصة").font(.caption).foregroundStyle(Theme.accent)
                }
                Spacer(minLength:0)
            }.padding(5).frame(width:220).background(Color.black.opacity(0.24),in:RoundedRectangle(cornerRadius:11)).foregroundStyle(.primary)
        }.buttonStyle(.plain)
    }
}

// Sends a story, or one chapter of it, to a friend as a message.
struct ShareWithFriendSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let story: Story
    var chapter: Double? = nil
    @State private var friends: [Account] = []
    @State private var loading = true
    @State private var note = ""
    @State private var busy: String?
    @State private var sent: Set<String> = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("تعليق (اختياري)",text:$note,axis:.vertical).lineLimit(1...3)
                        .onChange(of:note) { _,value in if value.count > 500 { note = String(value.prefix(500)) } }
                } header: { Text(chapter.map { "الفصل \(chapterNumber($0)) من \(story.title)" } ?? story.title) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                Section("الأصدقاء") {
                    if loading { ProgressView() }
                    if !loading && friends.isEmpty && error == nil { Text("ما عندك أصدقاء بعد. أضفهم من صفحة الأصدقاء.").foregroundStyle(.secondary) }
                    ForEach(friends) { friend in
                        HStack(spacing:12) {
                            ProfileAvatar(user:friend).frame(width:38,height:38)
                            VStack(alignment:.leading,spacing:2) { Text(friend.name).font(.subheadline.weight(.semibold)); Text("@"+friend.username).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if sent.contains(friend.id) { Label("تم الإرسال",systemImage:"checkmark").font(.caption).foregroundStyle(.secondary) }
                            else {
                                Button(busy == friend.id ? "جاري الإرسال…" : "إرسال") { Task { await send(to:friend.id) } }
                                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black).disabled(busy != nil || !store.online)
                            }
                        }
                    }
                }
            }
            .navigationTitle("مشاركة مع صديق").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("تم") { dismiss() } } }
            .task { await load() }
        }.environment(\.layoutDirection,.rightToLeft).tint(Theme.accent)
    }
    private func load() async {
        defer { loading = false }
        guard store.online else { error = "المشاركة تحتاج اتصالًا"; return }
        do { friends = try await API.shared.get("/api/friends",query:["limit":"100"],as:JSONValue.self)["friends"].array.compactMap { $0["user"].publicAccount } }
        catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    private func send(to id: String) async {
        busy = id; defer { busy = nil }
        var value: [String:JSONValue] = ["to":.string(id),"mangaId":.string(story.key)]
        let text = note.trimmingCharacters(in:.whitespacesAndNewlines)
        if !text.isEmpty { value["body"] = .string(text) }
        if let chapter { value["chapter"] = .number(chapter) }
        do { _ = try await API.shared.getMutation("/api/messages",value:value); sent.insert(id); error = nil }
        catch { if !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}
