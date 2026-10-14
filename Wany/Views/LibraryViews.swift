import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var store: AppStore
    @State private var source = "teamx"
    @State private var mode = "latest"
    @State private var query = ""
    @State private var items: [Story] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        WanyScroll {
            HStack { Text("استكشف").font(.largeTitle.bold()); Spacer(); Menu(sourceLabel(source)) { ForEach(sources,id:\.self) { s in Button(sourceLabel(s)) { source = s; Task { await load(reset:true) } } } } }
            HStack { TextField("ابحث عن قصة",text:$query).submitLabel(.search).onSubmit { Task { await load(reset:true) } }; Button { Task { await load(reset:true) } } label: { Image(systemName:"magnifyingglass") } }.card()
            Picker("ترتيب",selection:$mode) { Text("الأحدث").tag("latest"); Text("الأكثر شعبية").tag("popular") }.pickerStyle(.segmented).onChange(of:mode) { _,_ in Task { await load(reset:true) } }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            StoryGrid(stories:items)
            if busy { ProgressView("جاري تحميل القصص") }
            if hasMore && !busy { Button("تحميل المزيد") { Task { await load(reset:false) } }.buttonStyle(.bordered) }
        }.task { if items.isEmpty { await load(reset:true) } }.refreshable { await load(reset:true) }
    }
    func load(reset: Bool) async {
        guard !busy else { return }
        guard store.online else { items = store.stories.values.filter { $0.source == source && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }.sorted { $0.title < $1.title }; message = "تظهر القصص المحفوظة على الجهاز"; return }
        busy = true; defer { busy = false }
        let nextPage = reset ? 1 : page+1
        let endpoint = query.trimmingCharacters(in:.whitespaces).isEmpty ? mode : "search"
        do {
            let result = try await API.shared.get("/api/source/"+endpoint,query:["source":source,"page":String(nextPage),"q":query],as:APIList.self)
            if reset { items = [] }
            let existing = Set(items.map(\.key)); items += result.items.filter { !existing.contains($0.key) }
            page = nextPage; hasMore = result.hasMore; message = nil
            for item in result.items { store.remember(item) }
        } catch { message = error.localizedDescription }
    }
}
struct FeedView: View {
    @EnvironmentObject var store: AppStore
    let kind: String
    @State private var followed = false
    @State private var visible = 20
    var groups: [FeedGroup] { followed ? (store.state?.newFeed?.followed ?? []) : (store.state?.newFeed?.all ?? []) }
    var body: some View {
        WanyScroll {
            HStack { Text(kind == "fyp" ? "مقترح لك" : "جديد").font(.largeTitle.bold()); Spacer(); Button { Task { await store.loadFeed(kind) } } label: { Image(systemName:"arrow.clockwise") }.disabled(!store.online || store.loadingFeed) }
            if store.loadingFeed { HStack { ProgressView(); Text(store.feedProgress).font(.caption) }.card() }
            if kind == "fyp" {
                let recommendations = Array((store.state?.fyp ?? []).prefix(visible))
                if recommendations.isEmpty && !store.loadingFeed { EmptyState(icon:"sparkles",title:"اقتراحات تناسب قراءتك",detail:"تُجهز من مفضلتك وسجل قراءتك وقوائمك، بنفس خوارزمية الموقع.") }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:20) { ForEach(recommendations) { r in VStack(alignment:.leading,spacing:6) { StoryCard(story:r.item); Text(r.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(3) } } }
                if visible < (store.state?.fyp.count ?? 0) { Button("عرض المزيد") { visible += 12 }.buttonStyle(.bordered) }
            } else {
                Picker("العرض",selection:$followed) { Text("الكل").tag(false); Text("أتابعها").tag(true) }.pickerStyle(.segmented)
                if groups.isEmpty && !store.loadingFeed { EmptyState(icon:"sparkle",title:"لا توجد فصول جديدة هنا",detail:"الفصول المنشورة خلال آخر 24 ساعة، مع توضيح مصدر كل فصل واستبعاد الإصدارات القديمة المكررة.") }
                ForEach(groups) { group in
                    VStack(alignment:.leading,spacing:14) {
                        NavigationLink { StoryView(initial:group.item) } label: { HStack { CoverView(story:group.item).frame(width:55,height:78).clipShape(RoundedRectangle(cornerRadius:8)); Text(group.item.title).font(.headline).foregroundStyle(.primary) } }
                        ForEach(group.chapters) { chapter in
                            NavigationLink {
                                SourceChapterDestination(key:chapter.sourceKey,chapter:Chapter(number:chapter.number,title:chapter.title),fallback:group.item)
                            } label: { HStack { Text(chapter.title); Spacer(); Text(chapter.sourceLabel).foregroundStyle(Theme.accent); if chapter.read { Image(systemName:"checkmark") } }.font(.caption).foregroundStyle(.primary).padding(.vertical,4) }
                        }
                    }.card()
                }
                if store.state?.newFeed?.hasMore == true { Button("الصفحة التالية") { Task { await store.loadFeed("new",page:(store.state?.newFeed?.page ?? 1)+1) } }.disabled(store.loadingFeed || !store.online) }
            }
        }.task { if kind == "fyp" ? (store.state?.fyp.isEmpty ?? true) : store.state?.newFeed == nil { await store.loadFeed(kind) } }.refreshable { await store.loadFeed(kind) }
    }
}
struct SourceChapterDestination: View {
    @EnvironmentObject var store: AppStore
    let key: String; let chapter: Chapter; let fallback: Story
    @State private var story: Story?
    @State private var message: String?
    var body: some View {
        Group { if let story { ReaderView(story:story,chapter:chapter) } else if let cached = store.stories[key] { ReaderView(story:cached,chapter:chapter) } else if let message { EmptyState(icon:"wifi.slash",title:"تعذر فتح الفصل",detail:message) } else { ProgressView() } }
            .task {
                if key == fallback.key { story = fallback; return }
                do { story = try await API.shared.get("/api/source/series",query:["key":key],as:SeriesResponse.self).item } catch { message = error.localizedDescription }
            }
    }
}
struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = "reading"
    @StateObject private var lists = CachedPage()
    @StateObject private var selectedList = CachedPage()
    @State private var listID = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var adding = false
    @State private var busy = false
    var keys: [String] {
        guard let state = store.state else { return [] }
        if tab == "favorites" { return state.data.favorites }
        if tab == "lists" { return selectedList.value["items"].array.map { $0["mangaId"].string } }
        return state.data.library.filter { $0.status == "reading" }.sorted { ($0.lastReadAt ?? $0.updatedAt) > ($1.lastReadAt ?? $1.updatedAt) }.map(\.mangaId)
    }
    var body: some View {
        WanyScroll {
            if let state = store.state {
                HStack(spacing:15) {
                    ProfileAvatar(user:state.user).frame(width:66,height:66)
                    VStack(alignment:.leading,spacing:6) { HStack { Text(state.user.name).font(.title2.bold()); AccountBadge(kind:state.user.badgeType) }; Text("@"+state.user.username).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    NavigationLink { StatsView() } label: { Image(systemName:"chart.bar.xaxis").font(.title2) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                HStack { Label(store.syncing ? "جاري المزامنة…" : state.pending.isEmpty ? "التقدم متزامن" : "\(state.pending.count) تحديث بانتظار الاتصال",systemImage:state.pending.isEmpty ? "checkmark.icloud" : "icloud.and.arrow.up").font(.caption).foregroundStyle(.secondary); Spacer(); Button { Task { await store.refresh() } } label: { Image(systemName:"arrow.clockwise") }.disabled(!store.online || store.syncing) }
                if let last = state.data.lastOpened, let story = store.stories[last.mangaId] {
                    NavigationLink { ReaderView(story:story,chapter:story.chapters?.first(where:{$0.number == last.chapter}) ?? Chapter(number:last.chapter,title:"الفصل \(chapterNumber(last.chapter))")) } label: {
                        HStack { CoverView(story:story).frame(width:60,height:84).clipShape(RoundedRectangle(cornerRadius:10)); VStack(alignment:.leading,spacing:6) { Text("أكمل من حيث توقفت").font(.caption).foregroundStyle(Theme.accent); Text(story.title).bold().lineLimit(1); Text("الفصل \(chapterNumber(last.chapter))").font(.caption) }; Spacer(); Image(systemName:"play.fill") }.foregroundStyle(.primary).card()
                    }
                }
                HStack {
                    stat("قصص",state.data.library.count)
                    stat("مكتمل",state.data.completed.count)
                    stat("مفضلة",state.data.favorites.count)
                }
                HStack(spacing:16) {
                    NavigationLink { FriendsView() } label: { Label("الأصدقاء",systemImage:"person.2").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }
                    NavigationLink { ActivityView() } label: { Label("النشاط",systemImage:"clock").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }
                }.font(.subheadline).buttonStyle(.plain)
                HStack(spacing:8) {
                    ForEach([("reading","أقرأ حاليًا"),("favorites","المفضلة"),("lists","القوائم")],id:\.0) { pair in
                        Button { tab = pair.0 } label: { Text(pair.1).font(.subheadline).frame(maxWidth:.infinity,minHeight:48).background(tab == pair.0 ? Theme.accent.opacity(0.25) : Theme.surface,in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                    Button { newName = ""; creating = true } label: { Image(systemName:"plus").frame(width:48,height:48).background(Theme.surface,in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("إنشاء قائمة").disabled(!store.online)
                }
                if tab == "lists" {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) { ForEach(Array(lists.value["lists"].array.enumerated()),id:\.offset) { _,list in
                            Button { listID = list["id"].string } label: { Text(list["name"].string).font(.subheadline).padding(.horizontal,16).frame(minHeight:48).background(listID == list["id"].string ? Theme.accent.opacity(0.25) : Theme.surface,in:Capsule()).contentShape(Capsule()) }.buttonStyle(.plain)
                        } }
                    }
                    if !listID.isEmpty {
                        HStack(spacing:16) {
                            Button { adding = true } label: { Label("إضافة قصص",systemImage:"plus").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }.disabled(!store.online)
                            NavigationLink { ListDetailView(id:listID,title:lists.value["lists"].array.first(where:{$0["id"].string == listID})?["name"].string ?? "القائمة") } label: { Label("إدارة القائمة",systemImage:"slider.horizontal.3").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }
                        }.font(.caption).buttonStyle(.plain)
                    } else { Text("أنشئ قائمتك من زر + وأضف لها القصص التي تختارها.").font(.subheadline).foregroundStyle(.secondary) }
                }
                StoryGrid(stories:keys.compactMap { store.stories[$0] },showReadingProgress:true)
                let missing = keys.filter { store.stories[$0] == nil }.count
                if missing > 0 { Text("\(missing) قصة بانتظار حفظ تفاصيلها عند الاتصال").font(.caption).foregroundStyle(.secondary) }
                if keys.isEmpty { EmptyState(icon:"books.vertical",title:"لا توجد قصص هنا",detail:"أضف قصة من صفحة الاستكشاف لتظهر في مكتبتك.") }
            }
        }.task { await loadLists(); await loadSelectedList() }
        .refreshable { await store.refresh(); await loadLists(); await loadSelectedList() }
        .onChange(of:tab) { _,value in if value == "lists" { Task { await loadLists(); await loadSelectedList() } } }
        .onChange(of:listID) { _,_ in Task { await loadSelectedList() } }
        .sheet(isPresented:$adding,onDismiss:{ Task { await loadSelectedList(); await loadLists() } }) { AddStoriesToListView(id:listID) }
        .alert("قائمة جديدة",isPresented:$creating) {
            TextField("اسم القائمة",text:$newName)
            Button("إنشاء") { Task { await createList() } }.disabled(busy)
            Button("إلغاء",role:.cancel) {}
        }
    }
    func loadLists() async {
        await lists.load("/api/lists",store:store)
        if listID.isEmpty { listID = lists.value["lists"].array.first?["id"].string ?? "" }
    }
    func loadSelectedList() async {
        guard !listID.isEmpty else { return }
        await selectedList.load("/api/lists/"+listID,store:store)
        guard store.online else { return }
        let keys = selectedList.value["items"].array.map { $0["mangaId"].string }.filter { store.stories[$0] == nil }
        for start in stride(from:0,to:keys.count,by:40) {
            if let response = try? await API.shared.get("/api/source/resolve",query:["keys":keys[start..<min(start+40,keys.count)].joined(separator:",")],as:ResolveResponse.self) { for story in response.items { store.remember(story) } }
        }
    }
    func createList() async {
        let name = newName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, !busy else { return }; busy = true; defer { busy = false }
        do {
            let data = try await API.shared.raw("/api/lists",method:"POST",body:JSONEncoder().encode(["name":name,"description":"","iconKey":"lists"]))
            let result = try JSONDecoder().decode(JSONValue.self,from:data)
            await loadLists(); listID = result["list"]["id"].string; tab = "lists"; await loadSelectedList()
        } catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } }
    }
    func stat(_ title: String,_ value: Int) -> some View { VStack(spacing:6) { Text("\(value)").font(.title2.bold()).foregroundStyle(Theme.accent); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity).card() }
}
struct ProfileAvatar: View {
    @EnvironmentObject var store: AppStore
    let user: Account
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage:image).resizable().scaledToFill() } else { Image(systemName:"person.crop.circle.fill").resizable().foregroundStyle(Theme.accent) } }.clipShape(Circle())
            .task(id:user.avatarId) {
                guard let id = user.avatarId, let owner = store.state?.user.id else { return }
                let path = Disk.file(owner,"avatars/"+Disk.hash(id)+".image")
                if let cached = UIImage(contentsOfFile:path.path) { image = cached; return }
                guard store.online else { return }
                if let request = try? API.shared.request("/api/avatars/"+id+"/image"), let (data,response) = try? await URLSession.shared.data(for:request), (response as? HTTPURLResponse)?.statusCode == 200, let value = UIImage(data:data) {
                    image = value; try? FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true); try? data.write(to:path,options:.atomic)
                }
            }
    }
}
struct StatsView: View {
    @EnvironmentObject var store: AppStore
    let fields = [("storiesRead","القصص المقروءة"),("organicChapters","الفصول المقروءة"),("organicCompletedChapters","الفصول المكتملة"),("bulkChapters","الفصول المحددة دفعة واحدة"),("activeDays","أيام القراءة"),("dailyAverage","المعدل اليومي"),("currentStreak","سلسلة الأيام الحالية"),("bestStreak","أفضل سلسلة"),("accountDays","عمر الحساب بالأيام")]
    var body: some View {
        WanyScroll {
            Text("إحصائيات القراءة").font(.largeTitle.bold()).frame(maxWidth:.infinity,alignment:.leading)
            if let state = store.state {
                if !state.pending.isEmpty { Text("يوجد تقدم محلي بانتظار المزامنة. تتحدث الإحصائيات بعد رفعه.").font(.caption).foregroundStyle(.orange) }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) { ForEach(fields,id:\.0) { field in VStack(spacing:9) { Text(String(format:"%g",state.stats[field.0]?.number ?? 0)).font(.largeTitle.bold()).foregroundStyle(Theme.accent); Text(field.1).font(.caption) }.frame(maxWidth:.infinity).card() } }
                Text("الأيام الأخيرة").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                ForEach(Array((state.stats["recentDays"]?.array ?? []).enumerated()),id:\.offset) { _,day in HStack { Text(day["day"].string); Spacer(); Text("\(Int(day["chapters"].number)) فصل") }.font(.subheadline).card() }
            }
        }.navigationTitle("الإحصائيات").refreshable { await store.refresh() }
    }
}
