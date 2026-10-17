import SwiftUI

struct StoryView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    let initial: Story
    var sourceKeys: [String] = []
    @State private var selectedSource: String?
    @State private var confirmReadAll=false
    @State private var confirmClear=false
    @State private var detail: Story?
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var ascending = true
    @State private var selecting = false
    @State private var listPicker = false
    @State private var preparingUnread = false
    @State private var selected: Set<String> = []
    var story: Story { detail ?? store.stories[selectedSource ?? initial.key] ?? initial }
    var chapters: [Chapter] {
        let result = story.orderedChapters.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.contains(query) }
        return ascending ? result : result.reversed()
    }
    var body: some View {
        WanyScroll {
            HStack(alignment:.top,spacing:18) {
                CoverView(story:story).frame(width:112,height:164).clipShape(RoundedRectangle(cornerRadius:16))
                VStack(alignment:.leading,spacing:10) {
                    Text(story.title).font(RanyTypography.font(.title2).bold())
                    if sourceKeys.count > 1 { Menu {
                        ForEach(sourceKeys,id:\.self) { key in Button(sourceLabel(sourceFromStoryKey(key))) { Task { await switchSource(key) } } }
                    } label: { Label(sourceLabel(story.source),systemImage:"arrow.triangle.2.circlepath").font(.caption) }.disabled(loading)
                    } else { Text(sourceLabel(story.source)).font(RanyTypography.font(.caption)).foregroundStyle(Theme.accent) }
                    Text(storyStatusLabel(story.status ?? story.type)).font(RanyTypography.font(.caption)).foregroundStyle(.secondary)
                    Button { Task { await store.toggleFavorite(story) } } label: { Label(store.state?.data.favorites.contains(story.key) == true ? "في المفضلة" : "أضف للمفضلة",systemImage:store.state?.data.favorites.contains(story.key) == true ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                    Button("إضافة إلى قائمة",systemImage:"text.badge.plus") { listPicker=true }.buttonStyle(.bordered).disabled(!store.online)
                    Menu("حالة القراءة") { ForEach([("reading","أقرأ حاليًا"),("completed","مكتمل"),("paused","متوقف"),("planned","أخطط لقراءته")],id:\.0) { pair in Button(pair.1) { Task { await store.setStatus(story,status:pair.0) } } } }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let description = story.description, !description.isEmpty { Text(description.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)).font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            if !story.genres.isEmpty { Text(story.genres.joined(separator:" · ")).font(RanyTypography.font(.caption)).foregroundStyle(Theme.accent).frame(maxWidth:.infinity,alignment:.leading) }
            if let recent = store.state?.data.library.first(where:{$0.mangaId == story.key})?.lastReadChapter {
                WanyLink { ReaderView(story:story,chapter:story.chapters?.first(where:{$0.number == recent}) ?? Chapter(number:recent,title:"الفصل \(chapterNumber(recent))")) } label: { Label("متابعة الفصل \(chapterNumber(recent))",systemImage:"book.fill").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
            }
            Button { Task { await downloads.enqueue(story) } } label: {
                HStack { if downloads.preparing.contains(story.key) { ProgressView() }; Label(downloads.preparing.contains(story.key) ? "تجهيز جميع الفصول…" : "تحميل القصة كاملة",systemImage:"arrow.down.to.line").bold() }.frame(maxWidth:.infinity).padding(9)
            }.buttonStyle(.borderedProminent).disabled(preparingUnread || downloads.preparing.contains(story.key) || !store.online)
            Button {
                preparingUnread = true
                Task { await store.downloadUnread(story); preparingUnread = false }
            } label: {
                VStack(spacing:8) {
                    HStack {
                    if preparingUnread { ProgressView() }
                    Label(preparingUnread ? "فحص الفصول غير المقروءة…" : "تحميل الفصول غير المقروءة",systemImage:"book.closed").bold()
                    }
                    Text("يتجاوز الفصول التي أكملتها، ويشمل الفصل الذي لم تكمل قراءته.").font(RanyTypography.font(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth:.infinity).padding(9)
            }.buttonStyle(.bordered).disabled(preparingUnread || downloads.preparing.contains(story.key) || !store.online)
            if let job = downloads.savedJobs.first(where:{$0.id == story.key}) { DownloadSummary(job:job).card() }
            Menu("أدوات القراءة",systemImage:"checkmark.bookmark") {
                Button("تعليم جميع الفصول كمقروءة") { confirmReadAll=true }.disabled(story.chapterListComplete != true || story.orderedChapters.isEmpty)
                Button("مسح تقدم القصة وإعادتها لغير مقروءة",role:.destructive) { confirmClear=true }
            }.disabled(!store.online || loading || store.readingMutation || store.syncing)
            HStack { Text("الفصول · \(story.chapters?.count ?? 0)").font(RanyTypography.font(.title3).bold()); Spacer(); if loading { ProgressView() }; Button { ascending.toggle() } label: { Image(systemName:"arrow.up.arrow.down") }; Button(selecting ? "إلغاء" : "تحديد") { selecting.toggle(); selected.removeAll() } }
            if let error { Text(error).font(RanyTypography.font(.caption)).foregroundStyle(.orange); Button("إعادة جلب قائمة الفصول") { Task { await refresh() } } }
            if !store.online { Text("التفاصيل محفوظة. الفصول بعلامة ✓ متاحة بدون إنترنت؛ الفصول الناقصة تحتاج اتصالًا لاستكمال الصور.").font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }
            TextField("ابحث برقم الفصل أو عنوانه",text:$query).textFieldStyle(.plain).padding(13).ranyInsetGlass(radius:14).keyboardType(.default)
            if selecting {
                HStack { Button("تحديد الكل") { selected = Set(chapters.map(\.id)) }; Spacer(); Button("تحميل \(selected.count) فصل") { let list = chapters.filter { selected.contains($0.id) }; Task { await downloads.enqueue(story,chapters:list) }; selecting = false }.disabled(selected.isEmpty || !store.online) }
            }
            LazyVStack(spacing:2) {
                ForEach(chapters) { chapter in
                    HStack {
                        if selecting { Button { if selected.contains(chapter.id) { selected.remove(chapter.id) } else { selected.insert(chapter.id) } } label: { Image(systemName:selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle") } }
                        WanyLink { ReaderView(story:story,chapter:chapter) } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text(chapter.title).font(RanyTypography.font(.subheadline))
                                HStack(spacing:8) {
                                    if store.state?.data.completed.contains(story.key+":"+chapter.id) == true { Text("مقروء").foregroundStyle(Theme.accent) }
                                    else if let percent=store.state?.data.progress[story.key+":"+chapter.id]?.percent,percent>0 { Text("\(Int(percent))٪").foregroundStyle(Theme.accent) }
                                    if let date=chapter.publishedAt,!date.isEmpty { Text(date).foregroundStyle(.secondary) }
                                }.font(.caption2)
                            }.frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.primary)
                        }
                        if downloads.savedJobs.first(where:{$0.id == story.key})?.chapters.first(where:{$0.id == chapter.id})?.complete == true { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                        else { Button { Task { await downloads.enqueue(story,chapters:[chapter]) } } label: { Image(systemName:"arrow.down.circle").font(RanyTypography.font(.title3)) }.disabled(!store.online) }
                    }.padding(14).ranyInsetGlass(radius:12).contextMenu {
                        Button("تعليم الفصل كمقروء",systemImage:"checkmark") { Task { await store.manualReadChapter(story,chapter:chapter.number) } }.disabled(!store.online || store.syncing || store.readingMutation)
                        Button("إعادة الفصل إلى غير مقروء",systemImage:"arrow.uturn.backward") { Task { await store.manualUnread(story,chapter:chapter.number) } }.disabled(!store.online || store.syncing || store.readingMutation)
                    }
                }
            }
        }.navigationTitle(story.title).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("تعليم جميع الفصول كمقروءة؟",isPresented:$confirmReadAll,titleVisibility:.visible) { Button("تأكيد تعليم \(story.chapters?.count ?? 0) فصل") { Task { await store.manualRead(story,chapters:story.orderedChapters.map(\.number)) } }; Button("إلغاء",role:.cancel) {} }
            .confirmationDialog("مسح تقدم هذه القصة؟",isPresented:$confirmClear,titleVisibility:.visible) { Button("مسح التقدم",role:.destructive) { Task { await store.manualUnreadGroup(story,keys:sourceKeys) } }; Button("إلغاء",role:.cancel) {} } message: { Text("يُحذف سجل وتقدم القراءة لكل المصادر المرتبطة بهذه القصة عبر الموقع. تبقى الملفات المحملة والمفضلة والقوائم.") }
            .sheet(isPresented:$listPicker) { StoryListPicker(story:story) }
            .task { await refresh() }.refreshable { await refresh() }
    }
    private func switchSource(_ key: String) async {
        guard key != story.key,store.online,!loading else { return }
        loading=true; let owner=store.state?.user.id; defer { loading=false }
        do {
            let value=try await API.shared.fullSeries(key)
            guard !Task.isCancelled,owner == store.state?.user.id else { return }
            store.remember(value); selectedSource=key; detail=value; selecting=false; selected=[]; error=nil
        } catch { self.error=error.localizedDescription }
    }
    func refresh() async {
        guard store.online, !loading else { return }; loading = true; defer { loading = false }
        do { let value = try await API.shared.fullSeries(selectedSource ?? initial.key); detail = value; store.remember(value); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
