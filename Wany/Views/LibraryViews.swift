import SwiftUI
import ImageIO

struct DiscoverView: View {
    @EnvironmentObject var store: AppStore
    @State private var source = "all"
    @State private var filter=CatalogFilter()
    @State private var filtersOpen=false
    @State private var groups: [StorySourceGroup] = []
    @State private var filterLoading=false
    @State private var metadataVerified: Set<String> = []
    @State private var groupToken=UUID()
    @State private var mode = "latest"
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var items: [Story] = []
    @State private var sourceItems: [String:[Story]] = [:]
    @State private var pages: [String:Int] = [:]
    @State private var more: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var busy = false
    @State private var message: String?
    @State private var requestToken = UUID()
    var requestKey: String { source + "|" + mode + "|" + submittedQuery + "|" + filter.type + "|" + filter.status + "|" + filter.genres.sorted().joined(separator:",") }
    var hasMore: Bool { !more.isEmpty || !failed.isEmpty }
    var body: some View {
        WanyScroll {
            HStack {
                Text("استكشف").font(RanyTypography.font(.largeTitle).bold()); Spacer()
                Menu {
                    Button("الكل") { source = "all" }
                    ForEach(sources,id:\.self) { item in Button(sourceLabel(item)) { source = item } }
                } label: { Label(source == "all" ? "الكل" : sourceLabel(source),systemImage:"line.3.horizontal.decrease.circle").frame(minHeight:44) }.accessibilityHint("تغيير مصدر القصص")
            }
            HStack {
                TextField("ابحث عن قصة",text:$query).submitLabel(.search).onSubmit { search() }
                Button { search() } label: { Image(systemName:"magnifyingglass").frame(width:44,height:44) }
            }.card()
            Picker("ترتيب",selection:$mode) { Text("الأحدث").tag("latest"); Text("الأكثر شعبية").tag("popular") }.pickerStyle(.segmented)
            if let message { Text(message).font(RanyTypography.font(.caption)).foregroundStyle(.orange) }
            HStack { Button("فلاتر النوع والحالة والتصنيفات",systemImage:"line.3.horizontal.decrease.circle") { filtersOpen=true }; Spacer(); if filterLoading { ProgressView() } }.font(.caption)
            let featured=groups.filter { isWideCover($0.primary) }
            if !featured.isEmpty { DiscoverFeaturedStories(stories:featured.map(\.primary),sourceGroups:Dictionary(featured.map { ($0.primary.key,$0.items.map(\.key)) },uniquingKeysWith:{ _,b in b })) }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:20) {
                ForEach(groups.filter { !isWideCover($0.primary) }) { group in StoryCard(story:group.primary,sourceKeys:group.items.map(\.key)) }
            }
            if busy { ProgressView("جاري تحميل القصص") }
            if hasMore && !busy { Button("تحميل المزيد") { Task { await load(reset:false) } }.buttonStyle(.bordered) }
        }.sheet(isPresented:$filtersOpen) { DiscoveryFilterSheet(filter:$filter,source:$source) }
        .task(id:items) { await refreshGroups() }
        .task(id:requestKey) { await load(reset:true) }.refreshable { await load(reset:true) }
        .task(id:items.map(\.cover)) {
            // Warm the first covers so wide artwork can move into the carousel before scrolling.
            for story in items.prefix(28) { guard !Task.isCancelled else { return }; await store.cacheCover(story) }
        }
    }
    private func refreshGroups() async {
        let token=UUID(); groupToken=token; filterLoading=true
        defer { if groupToken == token { filterLoading=false } }
        var enriched=items.map { store.stories[$0.key] ?? $0 }
        if filter.requiresMetadata,store.online {
            let missing=enriched.filter { !metadataVerified.contains($0.key) }
            var failures=0
            for start in stride(from:0,to:missing.count,by:3) {
                guard !Task.isCancelled,groupToken == token else { return }
                let batch=Array(missing[start..<min(start+3,missing.count)])
                let resolved=await withTaskGroup(of:(String,Story?).self,returning:[(String,Story?)].self) { group in
                    for story in batch { group.addTask { (story.key,try? await API.shared.get("/api/source/series",query:["key":story.key],as:SeriesResponse.self).item) } }
                    var result: [(String,Story?)] = []; for await row in group { result.append(row) }; return result
                }
                guard !Task.isCancelled,groupToken == token else { return }
                for (key,value) in resolved {
                    if let value { metadataVerified.insert(key); store.remember(value); if let i=enriched.firstIndex(where:{$0.key == key}) { enriched[i]=value } }
                    else { failures += 1 }
                }
            }
            if failures>0 { message="تعذر استكمال بيانات \(failures) قصة؛ نتائج الفلاتر قد تكون جزئية. أعد المحاولة بالسحب للتحديث." }
        }
        var applied=filter; applied.source=source
        let result=await CatalogRules.groups(enriched,filter:applied)
        if !Task.isCancelled,groupToken == token { groups=result }
    }
    func isWideCover(_ story: Story) -> Bool {
        guard let owner = store.state?.user.id,
              let image = CGImageSourceCreateWithURL(Disk.file(owner,Disk.coverName(story.key)) as CFURL,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return DiscoverResults.isWideCover(width:width.doubleValue,height:height.doubleValue)
    }
    func search() {
        let value = query.trimmingCharacters(in:.whitespacesAndNewlines)
        if submittedQuery == value { Task { await load(reset:true) } } else { submittedQuery = value }
    }
    func load(reset: Bool) async {
        guard reset || !busy else { return }
        let token = UUID(); requestToken = token
        let selected = source; let text = submittedQuery
        let endpoint = text.isEmpty ? mode : "search"
        guard store.online else {
            items = store.stories.values.filter { (selected == "all" || $0.source == selected) && (text.isEmpty || $0.title.localizedCaseInsensitiveContains(text)) }.sorted { $0.title < $1.title }
            sourceItems = Dictionary(grouping:items,by:\.source)
            more = []; failed = []; busy = false; message = "تظهر القصص المحفوظة على الجهاز"; return
        }
        busy = true; defer { if requestToken == token { busy = false } }
        if reset { items = []; sourceItems = [:]; pages = [:]; more = []; failed = []; message = nil }
        let targets = selected == "all" ? sources.filter { reset || more.contains($0) || failed.contains($0) } : [selected]
        let requestedPages = Dictionary(uniqueKeysWithValues:targets.map { ($0,reset ? 1 : (pages[$0] ?? 0)+1) })
        let owner = store.state?.user.id
        await withTaskGroup(of:(String,APIList?).self) { group in
            for target in targets {
                let page = requestedPages[target] ?? 1
                group.addTask {
                    let result = try? await API.shared.get("/api/source/"+endpoint,query:["source":target,"page":String(page),"q":text],as:APIList.self)
                    return (target,result)
                }
            }
            for await (target,result) in group {
                guard !Task.isCancelled, requestToken == token, store.state?.user.id == owner else { group.cancelAll(); continue }
                if let result {
                    failed.remove(target); pages[target] = result.page
                    if result.hasMore { more.insert(target) } else { more.remove(target) }
                    sourceItems[target] = DiscoverResults.append(result.items,to:sourceItems[target] ?? [])
                    items = DiscoverResults.combine(sourceItems,order:selected == "all" ? sources : [selected])
                    for item in result.items { store.remember(item) }
                } else { failed.insert(target) }
                message = failed.isEmpty ? nil : "تعذر تحميل: " + targets.filter { failed.contains($0) }.map(sourceLabel).joined(separator:"، ") + ". يمكنك إعادة المحاولة من تحميل المزيد."
            }
        }
    }
}
struct DiscoverFeaturedStories: View {
    let stories: [Story]
    var sourceGroups: [String:[String]] = [:]
    @State private var selected: String?
    var body: some View {
        VStack(spacing:10) {
            ScrollView(.horizontal) {
                LazyHStack(spacing:16) {
                    ForEach(stories) { story in
                        WanyLink { StoryView(initial:story,sourceKeys:sourceGroups[story.key] ?? []) } label: {
                            VStack(alignment:.leading,spacing:10) {
                                CoverView(story:story).frame(height:190).clipShape(RoundedRectangle(cornerRadius:20))
                                Text(story.title).font(RanyTypography.font(.headline)).lineLimit(2).frame(maxWidth:.infinity,minHeight:44,alignment:.topLeading)
                            }.foregroundStyle(.primary).containerRelativeFrame(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain).id(story.key)
                    }
                }.scrollTargetLayout()
            }.scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned).scrollPosition(id:$selected)
            if stories.count > 1 {
                HStack(spacing:6) { ForEach(stories) { story in
                    Capsule().fill((selected ?? stories.first?.key) == story.key ? Theme.accent : Color.secondary.opacity(0.3)).frame(width:(selected ?? stories.first?.key) == story.key ? 18 : 6,height:5)
                } }.accessibilityLabel("قصص مميزة قابلة للسحب")
            }
        }.onChange(of:stories.map(\.key)) { _,keys in if let selected, !keys.contains(selected) { self.selected = keys.first } }
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
            HStack { Text(kind == "fyp" ? "مقترح لك" : "جديد").font(RanyTypography.font(.largeTitle).bold()); Spacer(); Button { Task { await store.loadFeed(kind) } } label: { Image(systemName:"arrow.clockwise") }.disabled(!store.online || store.loadingFeed) }
            if store.loadingFeed { HStack { ProgressView(); Text(store.feedProgress).font(RanyTypography.font(.caption)) }.card() }
            if kind == "fyp" {
                let recommendations = Array((store.state?.fyp ?? []).prefix(visible))
                if recommendations.isEmpty && !store.loadingFeed { EmptyState(icon:"sparkles",title:"اقتراحات تناسب قراءتك",detail:"تُجهز من مفضلتك وسجل قراءتك وقوائمك، بنفس خوارزمية الموقع.") }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:20) { ForEach(recommendations) { r in VStack(alignment:.leading,spacing:6) { StoryCard(story:r.item,sourceKeys:r.sourceKeys); Text(r.reason).font(RanyTypography.font(.caption2)).foregroundStyle(.secondary).lineLimit(3) } } }
                if visible < (store.state?.fyp.count ?? 0) { Button("عرض المزيد") { visible += 12 }.buttonStyle(.bordered) }
            } else {
                Picker("العرض",selection:$followed) { Text("الكل").tag(false); Text("أتابعها").tag(true) }.pickerStyle(.segmented)
                if groups.isEmpty && !store.loadingFeed { EmptyState(icon:"sparkle",title:"لا توجد فصول جديدة هنا",detail:"الفصول المنشورة خلال آخر 24 ساعة، مع توضيح مصدر كل فصل واستبعاد الإصدارات القديمة المكررة.") }
                ForEach(groups) { group in
                    VStack(alignment:.leading,spacing:14) {
                        WanyLink { StoryView(initial:group.item,sourceKeys:group.sourceKeys) } label: { HStack { CoverView(story:group.item).frame(width:55,height:78).clipShape(RoundedRectangle(cornerRadius:8)); Text(group.item.title).font(RanyTypography.font(.headline)).foregroundStyle(.primary) } }
                        ForEach(group.chapters) { chapter in
                            WanyLink {
                                SourceChapterDestination(key:chapter.sourceKey,chapter:Chapter(number:chapter.number,title:chapter.title),fallback:group.item)
                            } label: { HStack { Text(chapter.title); Spacer(); Text(chapter.sourceLabel).foregroundStyle(Theme.accent); if chapter.read { Image(systemName:"checkmark") } }.font(RanyTypography.font(.caption)).foregroundStyle(.primary).padding(.vertical,4) }
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
    @State private var listSections: [RanyProfileSection] = []
    @State private var creating = false
    @State private var newName = ""
    @State private var adding = false
    @State private var busy = false
    @State private var editingProfile = false
    @State private var editingName = false
    @State private var draftName = ""
    @State private var draftAvatarID: String?
    @State private var pickingAvatar = false
    @State private var savingProfile = false
    @FocusState private var nameFocused: Bool
    private var visibleLists: [JSONValue] {
        let visibility=Dictionary(listSections.filter { $0.sectionType == "custom_list" }.map { ($0.referenceId ?? "",$0.isVisible) },uniquingKeysWith:{ _,b in b })
        return lists.value["lists"].array.filter { visibility[$0["id"].string] ?? true }
    }
    private var favoriteSectionHidden: Bool { listSections.first { $0.sectionType == "favorites" }?.isVisible == false }
    var keys: [String] {
        guard let state = store.state else { return [] }
        if tab == "favorites" { return favoriteSectionHidden ? [] : state.data.favorites }
        if tab == "lists" { return selectedList.value["items"].array.map { $0["mangaId"].string } }
        return state.data.library.filter { $0.status == "reading" }.sorted { ($0.lastReadAt ?? $0.updatedAt) > ($1.lastReadAt ?? $1.updatedAt) }.map(\.mangaId)
    }
    var body: some View {
        WanyScroll {
            if let state = store.state {
                identity(state)
                accountDetails(state)
                continueReading(state)
                library(state)

            }
        }.task { await loadLists(); await loadSelectedList() }
        .refreshable { await store.refresh(); await loadLists(); await loadSelectedList() }
        .onReceive(NotificationCenter.default.publisher(for:.ranyCollectionsChanged)) { _ in Task { await loadLists(); await loadSelectedList() } }
        .onChange(of:tab) { _,value in if value == "lists" { Task { await loadLists(); await loadSelectedList() } } }
        .onChange(of:listID) { _,_ in Task { await loadSelectedList() } }
        .sheet(isPresented:$adding,onDismiss:{ Task { await loadSelectedList(); await loadLists() } }) { AddStoriesToListView(id:listID) }
        .sheet(isPresented:$pickingAvatar) {
            NavigationStack {
                AvatarPickerView(onSelect:{ avatarID in draftAvatarID = avatarID },initialAvatarID:draftAvatarID)
                    .environmentObject(store)
                    .environmentObject(store.downloads)
                    .toolbar { ToolbarItem(placement:.topBarLeading) { Button("إغلاق") { pickingAvatar = false } } }
            }.preferredColorScheme(.dark)
        }
        .alert("قائمة جديدة",isPresented:$creating) {
            TextField("اسم القائمة",text:$newName)
            Button("إنشاء") { Task { await createList() } }.disabled(busy)
            Button("إلغاء",role:.cancel) {}
        }
    }
    private func identity(_ state: AccountState) -> some View {
        HStack(spacing:12) {
            if editingProfile {
                Button { pickingAvatar = true } label: {
                    ProfileAvatar(user:previewAccount(state.user)).frame(width:54,height:54)
                        .overlay(alignment:.bottomLeading) {
                            Image(systemName:"pencil").font(.system(size:11,weight:.semibold))
                                .foregroundStyle(.white)
                                .frame(width:25,height:25)
                                .background(Theme.accent,in:Circle())
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("تغيير الصورة الشخصية")
                    .accessibilityIdentifier("profile.avatar-edit")
            } else {
                ProfileAvatar(user:state.user).frame(width:54,height:54)
            }
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:7) {
                    if editingProfile && editingName {
                        TextField("الاسم الظاهر",text:$draftName)
                            .textContentType(.name).textInputAutocapitalization(.words)
                            .font(.title3.weight(.medium)).textFieldStyle(.plain)
                            .focused($nameFocused).submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .accessibilityIdentifier("profile.name-input")
                    } else {
                        Text(editingProfile ? draftName : state.user.name)
                            .font(.title3.weight(.medium)).lineLimit(2)
                    }
                    if editingProfile {
                        Button { editingName = true; nameFocused = true } label: {
                            Image(systemName:"pencil").font(.system(size:12,weight:.medium))
                                .foregroundStyle(Theme.accent).frame(width:32,height:34)
                        }.buttonStyle(.plain).accessibilityLabel("تغيير الاسم الظاهر")
                            .accessibilityIdentifier("profile.name-edit")
                    } else {
                        AccountBadge(kind:state.user.badgeType)
                    }
                }
                Text("@"+state.user.username).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:8)
            Button {
                if editingProfile {
                    Task { await saveProfile(state) }
                } else {
                    draftName = state.user.name
                    draftAvatarID = state.user.avatarId
                    editingName = false
                    editingProfile = true
                }
            } label: {
                VStack(spacing:5) {
                    if savingProfile { ProgressView().tint(Theme.accent) }
                    else { Image(systemName:editingProfile ? "checkmark" : "pencil").font(.system(size:12)) }
                    Text(editingProfile ? "حفظ" : "تعديل").font(.caption2)
                }.foregroundStyle(Theme.accent).frame(width:44,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(savingProfile || !store.online)
                .accessibilityIdentifier("profile.edit-save")
        }.frame(maxWidth:.infinity,alignment:.leading).card().accessibilityIdentifier("profile.identity")
    }
    private func previewAccount(_ user: Account) -> Account {
        var result = user
        result.avatarId = draftAvatarID
        return result
    }
    private func saveProfile(_ state: AccountState) async {
        guard !savingProfile, store.online else { return }
        let cleanedName = draftName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            store.error = "اكتب اسمًا ظاهرًا قبل الحفظ."
            return
        }
        savingProfile = true
        defer { savingProfile = false }
        do {
            if cleanedName != state.user.name {
                try await API.shared.send("/api/profile/name",method:"PUT",value:["name":cleanedName])
            }
            if draftAvatarID != state.user.avatarId, let avatarID = draftAvatarID {
                try await API.shared.send("/api/profile/avatar",method:"PUT",value:["avatarId":avatarID])
            }
            await store.refresh()
            nameFocused = false
            editingName = false
            editingProfile = false
        } catch {
            if !isRequestCancellation(error) { store.error = error.localizedDescription }
        }
    }
    private func accountDetails(_ state: AccountState) -> some View {
                VStack(spacing:12) {
                    HStack(spacing:6) {
                        WanyLink { StatsView() } label: { accountTool("الإحصائيات","chart.xyaxis.line") }
                        WanyLink { FriendsView() } label: { accountTool(store.incomingFriendRequests > 0 ? "الأصدقاء · \(store.incomingFriendRequests)" : "الأصدقاء","person.2") }
                        WanyLink { ActivityView() } label: { accountTool("النشاط","clock") }
                    }.buttonStyle(.plain)
                    HStack {
                        stat("قصة في مكتبتي",state.data.library.count)
                        Divider().frame(height:32)
                        stat("فصل مكتمل",state.data.completed.count)
                        Divider().frame(height:32)
                        stat("مفضلة",state.data.favorites.count)
                    }
                }.card().accessibilityIdentifier("profile.details")

    }
    private func continueReading(_ state: AccountState) -> some View {
                VStack(spacing:10) {
                    if let last = state.data.lastOpened, let story = store.stories[last.mangaId] {
                        WanyLink { ReaderView(story:story,chapter:story.chapters?.first(where:{$0.number == last.chapter}) ?? Chapter(number:last.chapter,title:"الفصل \(chapterNumber(last.chapter))")) } label: {
                            HStack(spacing:12) {
                                CoverView(story:story).frame(width:48,height:70).clipShape(RoundedRectangle(cornerRadius:10))
                                VStack(alignment:.leading,spacing:6) {
                                    Text("أكمل من حيث توقفت").font(.caption).foregroundStyle(Theme.accent)
                                    Text(story.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text("الفصل \(chapterNumber(last.chapter))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength:0)
                                Image(systemName:"play.fill").foregroundStyle(Theme.accent).frame(width:32,height:32)
                            }.foregroundStyle(.primary)
                        }
                        Divider()
                    }
                    RanyProgressStatus()
                }.card()

    }
    private func library(_ state: AccountState) -> some View {
                VStack(alignment:.leading,spacing:14) {
                    HStack { Text("مكتبتي").font(.headline); Spacer(); Text("\(state.data.library.count) قصة").font(.caption).foregroundStyle(.secondary); Button { newName = ""; creating = true } label: { Image(systemName:"plus").frame(width:44,height:44).ranyInsetGlass(radius:12).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("إنشاء قائمة").disabled(!store.online) }
                HStack(spacing:8) {
                    ForEach([("reading","أقرأ حاليًا"),("favorites","المفضلة"),("lists","القوائم")],id:\.0) { pair in
                        Button { tab = pair.0 } label: { Text(pair.1).font(RanyTypography.font(.caption)).frame(maxWidth:.infinity,minHeight:44).background(tab == pair.0 ? Theme.accent.opacity(0.25) : Theme.surface.opacity(0.22),in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                }
                if tab == "lists" {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) { ForEach(Array(visibleLists.enumerated()),id:\.offset) { _,list in
                            Button { listID = list["id"].string } label: { Label(list["name"].string,systemImage:ListIcons.symbol(list["iconKey"].string)).font(RanyTypography.font(.subheadline)).padding(.horizontal,16).frame(minHeight:48).background(listID == list["id"].string ? Theme.accent.opacity(0.25) : Theme.surface.opacity(0.22),in:Capsule()).contentShape(Capsule()) }.buttonStyle(.plain)
                        } }
                    }
                    WanyLink { ListsView() } label: { Label("إدارة القوائم وترتيب الأقسام",systemImage:"slider.horizontal.3").font(.caption).frame(minHeight:44) }
                    if !listID.isEmpty {
                        HStack(spacing:16) {
                            Button { adding = true } label: { Label("إضافة قصص",systemImage:"plus").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }.disabled(!store.online)
                            WanyLink { ListDetailView(id:listID,title:lists.value["lists"].array.first(where:{$0["id"].string == listID})?["name"].string ?? "القائمة") } label: { Label("إدارة القائمة",systemImage:"slider.horizontal.3").frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle()) }
                        }.font(RanyTypography.font(.caption)).buttonStyle(.plain)
                    } else { Text("أنشئ قائمتك من زر + وأضف لها القصص التي تختارها.").font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary) }
                }
                if tab == "favorites" { MergedStoryGrid(stories:keys.compactMap { store.stories[$0] },showReadingProgress:true) } else { StoryGrid(stories:keys.compactMap { store.stories[$0] },showReadingProgress:true) }
                let missing = keys.filter { store.stories[$0] == nil }.count
                if missing > 0 { Text("\(missing) قصة بانتظار حفظ تفاصيلها عند الاتصال").font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }
                if keys.isEmpty { if tab == "favorites" && favoriteSectionHidden { Text("القسم مخفي من صفحتك. يمكنك إظهاره من إدارة القوائم.").font(.caption).foregroundStyle(.secondary) } else { EmptyState(icon:"books.vertical",title:"لا توجد قصص هنا",detail:"أضف قصة من صفحة الاستكشاف لتظهر في مكتبتك.") } }
                }.card()
    }
    func loadLists() async {
        await lists.load("/api/lists",store:store)
        if let owner=store.state?.user.id {
            if store.online,let result=try? await API.shared.get("/api/profile/sections",as:SectionsResponse.self),store.state?.user.id == owner {
                listSections=result.sections; try? Disk.save(result.sections,owner:owner,name:"collections/sections.json")
            } else { listSections=Disk.read([RanyProfileSection].self,owner:owner,name:"collections/sections.json") ?? [] }
        }
        if !visibleLists.contains(where:{$0["id"].string == listID}) { listID=visibleLists.first?["id"].string ?? "" }
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
    func stat(_ title: String,_ value: Int) -> some View { VStack(spacing:6) { Text("\(value)").font(RanyTypography.font(.title2).bold()).foregroundStyle(Theme.accent); Text(title).font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity) }
    private func accountTool(_ title: String,_ icon: String) -> some View { Label(title,systemImage:icon).font(.caption).foregroundStyle(Theme.accent).frame(maxWidth:.infinity,minHeight:44).ranyInsetGlass(radius:10).contentShape(Rectangle()) }
}
struct ProfileAvatar: View {
    @EnvironmentObject var store: AppStore
    let user: Account
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group { if let image { Image(uiImage:image).resizable().scaledToFill() } else { Image(systemName:"person.crop.circle.fill").resizable().foregroundStyle(Theme.accent) } }
                .frame(width:geometry.size.width,height:geometry.size.height).clipShape(Circle())
        }
            .task(id:[store.state?.user.id ?? "",user.avatarId ?? "",store.online ? "online" : "offline"]) {
                image = nil
                guard let id = user.avatarId, !id.isEmpty, let owner = store.state?.user.id else { return }
                let path = Disk.file(owner,"avatars/"+Disk.hash(id)+".image")
                if let cached = UIImage(contentsOfFile:path.path) { image = cached; return }
                guard store.online else { return }
                if let request = try? API.shared.request("/api/avatars/"+id+"/image"), let (data,response) = try? await URLSession.shared.data(for:request), (response as? HTTPURLResponse)?.statusCode == 200, let value = UIImage(data:data), !Task.isCancelled, store.state?.user.id == owner {
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
            Text("إحصائيات القراءة").font(RanyTypography.font(.largeTitle).bold()).frame(maxWidth:.infinity,alignment:.leading)
            if let state = store.state {
                if !state.pending.isEmpty { Text("يوجد تقدم محلي بانتظار المزامنة. تتحدث الإحصائيات بعد رفعه.").font(RanyTypography.font(.caption)).foregroundStyle(.orange) }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) { ForEach(fields,id:\.0) { field in VStack(spacing:9) { Text(String(format:"%g",state.stats[field.0]?.number ?? 0)).font(RanyTypography.font(.largeTitle).bold()).foregroundStyle(Theme.accent); Text(field.1).font(RanyTypography.font(.caption)) }.frame(maxWidth:.infinity).card() } }
                Text("الأيام الأخيرة").font(RanyTypography.font(.headline)).frame(maxWidth:.infinity,alignment:.leading)
                ForEach(Array((state.stats["recentDays"]?.array ?? []).enumerated()),id:\.offset) { _,day in HStack { Text(day["day"].string); Spacer(); Text("\(Int(day["chapters"].number)) فصل") }.font(RanyTypography.font(.subheadline)).card() }
            }
        }.navigationTitle("الإحصائيات").refreshable { await store.refresh() }
    }
}
