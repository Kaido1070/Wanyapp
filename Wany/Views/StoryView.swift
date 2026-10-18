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
    @State private var ascending = false
    @State private var chapterPage = 1
    @State private var selecting = false
    @State private var listPicker = false
    @State private var preparingUnread = false
    @State private var selected: Set<String> = []
    var story: Story { detail ?? store.stories[selectedSource ?? initial.key] ?? initial }
    var chapters: [Chapter] {
        let numberQuery=query.map { $0.wholeNumberValue.map { String($0) } ?? String($0) }.joined()
        let result = story.orderedChapters.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.contains(numberQuery) }
        return ascending ? result : result.reversed()
    }
    var page: StoryChapterPage { StoryChapterPage(chapters:chapters,requested:chapterPage) }
    var body: some View {
        ScrollViewReader { proxy in
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
            HStack {
                Text("الفصول · \(story.chapters?.count ?? 0)").font(RanyTypography.font(.title3).bold())
                Spacer()
                if loading { ProgressView() }
                Button(selecting ? "إلغاء" : "تحديد للتنزيل") { selecting.toggle(); selected.removeAll() }
                    .font(RanyTypography.font(.caption))
            }.id("chapters-top")
            Button { ascending.toggle() } label: {
                Label(ascending ? "من الأقدم للأحدث" : "من الأحدث للأقدم",systemImage:"arrow.up.arrow.down")
                    .frame(maxWidth:.infinity,minHeight:44)
            }.buttonStyle(.bordered)
            if let error { Text(error).font(RanyTypography.font(.caption)).foregroundStyle(.orange); Button("إعادة جلب قائمة الفصول") { Task { await refresh() } } }
            if !store.online { Text("التفاصيل محفوظة. الفصول بعلامة ✓ متاحة بدون إنترنت؛ الفصول الناقصة تحتاج اتصالًا لاستكمال الصور.").font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }
            TextField("ابحث برقم الفصل أو عنوانه",text:$query).textFieldStyle(.plain).padding(13).ranyInsetGlass(radius:14).keyboardType(.default)
            StoryReadingTools(
                canReadAll:story.chapterListComplete == true && !story.orderedChapters.isEmpty,
                disabled:!store.online || loading || store.loginRequired || store.readingMutation || store.syncing,
                markAll:{ confirmReadAll=true },clear:{ confirmClear=true }
            )
            StoryChapterPagination(page:page.number,pages:page.count) { goToPage($0,proxy:proxy) }
            if selecting {
                HStack { Button("تحديد الكل") { selected = Set(chapters.map(\.id)) }; Spacer(); Button("تحميل \(selected.count) فصل") { let list = chapters.filter { selected.contains($0.id) }; Task { await downloads.enqueue(story,chapters:list) }; selecting = false }.disabled(selected.isEmpty || !store.online) }
            }
            LazyVStack(spacing:0) {
                ForEach(page.chapters) { chapter in
                    StoryChapterRow(story:story,chapter:chapter,loading:loading,selecting:selecting,selected:$selected)
                }
            }.padding(.horizontal,12).ranyInsetGlass(radius:14)
            if chapters.isEmpty && !loading {
                Text(query.isEmpty ? "لا توجد فصول متاحة" : "لا توجد فصول مطابقة للبحث")
                    .font(RanyTypography.font(.subheadline)).foregroundStyle(.secondary)
            }
            StoryChapterPagination(page:page.number,pages:page.count) { goToPage($0,proxy:proxy) }
        }.navigationTitle(story.title).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("تعليم جميع الفصول كمقروءة؟",isPresented:$confirmReadAll,titleVisibility:.visible) { Button("تأكيد تعليم \(story.chapters?.count ?? 0) فصل") { Task { await store.manualRead(story,chapters:story.orderedChapters.map(\.number)) } }; Button("إلغاء",role:.cancel) {} }
            .confirmationDialog("مسح تقدم هذه القصة؟",isPresented:$confirmClear,titleVisibility:.visible) { Button("مسح التقدم",role:.destructive) { Task { await store.manualUnreadGroup(story,keys:sourceKeys) } }; Button("إلغاء",role:.cancel) {} } message: { Text("يُحذف سجل وتقدم القراءة لكل المصادر المرتبطة بهذه القصة عبر الموقع. تبقى الملفات المحملة والمفضلة والقوائم.") }
            .sheet(isPresented:$listPicker) { StoryListPicker(story:story) }
            .task { await refresh() }.refreshable { await refresh() }
            .onChange(of:query) { _,_ in chapterPage=1 }
            .onChange(of:ascending) { _,_ in chapterPage=1 }
            .onChange(of:story.key) { _,_ in chapterPage=1; selected.removeAll(); selecting=false }
            .onChange(of:chapters.count) { _,_ in chapterPage=page.number }
        }
    }
    private func goToPage(_ value: Int,proxy: ScrollViewProxy) {
        chapterPage=min(max(1,value),page.count)
        proxy.scrollTo("chapters-top",anchor:.top)
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


// Visible reading actions stay separate from the chapter download selection.
struct StoryReadingTools: View {
    let canReadAll: Bool
    let disabled: Bool
    let markAll: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing:10) {
            Button(action:markAll) {
                Label("تحديد الكل كمقروء",systemImage:"checkmark")
                    .frame(maxWidth:.infinity,minHeight:44)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius:10).stroke(Theme.accent.opacity(0.22)))
            }.disabled(!canReadAll).opacity(canReadAll ? 1 : 0.45).accessibilityIdentifier("reading.markAll")
            Button(role:.destructive,action:clear) {
                Text("مسح تقدم القراءة").frame(maxWidth:.infinity,minHeight:44)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius:10).stroke(Theme.accent.opacity(0.22)))
            }.accessibilityIdentifier("reading.clearStory")
        }
        .font(RanyTypography.font(.footnote))
        .buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(disabled).opacity(disabled ? 0.45 : 1)
    }
}

struct ChapterReadingTools: View {
    let completed: Bool
    let disabled: Bool
    let markRead: () -> Void
    let markUnread: () -> Void

    var body: some View {
        Button(action:completed ? markUnread : markRead) {
            Text(completed ? "مقروء ✓" : "غير مقروء")
                .font(RanyTypography.font(.footnote))
                .frame(minWidth:72,minHeight:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .overlay(RoundedRectangle(cornerRadius:10).stroke(Theme.accent.opacity(0.22)))
        .disabled(disabled).opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(completed ? "مقروء، إعادة الفصل إلى غير مقروء" : "غير مقروء، تعليم الفصل كمقروء")
        .accessibilityIdentifier("reading.toggleChapter")
    }
}

// The website slices the ordered chapter list into groups of 100.
struct StoryChapterPage {
    static let size=100
    let number: Int
    let count: Int
    let chapters: [Chapter]
    init(chapters: [Chapter],requested: Int) {
        count=max(1,(chapters.count + Self.size - 1)/Self.size)
        number=min(max(1,requested),count)
        let start=min((number-1)*Self.size,chapters.count)
        self.chapters=Array(chapters[start..<min(start+Self.size,chapters.count)])
    }
}

struct StoryChapterPagination: View {
    let page: Int
    let pages: Int
    let onPage: (Int) -> Void
    var body: some View {
        if pages > 1 {
            HStack(spacing:8) {
                pageButton("السابق",enabled:page > 1) { onPage(page-1) }
                Spacer(minLength:0)
                Text("صفحة")
                Picker("صفحة \(page) من \(pages)",selection:Binding(get:{ page },set:onPage)) {
                    ForEach(1...pages,id:\.self) { value in Text("\(value)").tag(value) }
                }.labelsHidden().pickerStyle(.menu)
                    .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
                    .accessibilityIdentifier("reading.page.select")
                    .accessibilityLabel("اختيار صفحة الفصول، صفحة \(page) من \(pages)")
                Text("من \(pages)").foregroundStyle(.secondary)
                Spacer(minLength:0)
                pageButton("التالي",enabled:page < pages) { onPage(page+1) }
            }
            .font(RanyTypography.font(.caption))
            .frame(minHeight:44).tint(Theme.accent)
        }
    }
    private func pageButton(_ title: String,enabled: Bool,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(title).frame(minWidth:48,minHeight:44)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius:10).stroke(Theme.accent.opacity(0.22)))
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            .disabled(!enabled).opacity(enabled ? 1 : 0.4)
            .accessibilityIdentifier(title == "التالي" ? "reading.page.next" : "reading.page.previous")
    }
}

enum StoryChapterDate {
    static func display(_ value: String) -> String? {
        let parser=ISO8601DateFormatter()
        parser.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        var date=parser.date(from:value)
        if date == nil { parser.formatOptions=[.withInternetDateTime]; date=parser.date(from:value) }
        if date == nil {
            let plain=DateFormatter(); plain.locale=Locale(identifier:"en_US_POSIX")
            plain.calendar=Calendar(identifier:.gregorian); plain.timeZone=TimeZone(secondsFromGMT:0)
            plain.dateFormat="yyyy-MM-dd"; plain.isLenient=false
            if value.count == 10 { date=plain.date(from:value) }
        }
        guard let date else { return nil }
        let output=DateFormatter(); output.locale=Locale(identifier:"en_GB")
        output.calendar=Calendar(identifier:.gregorian); output.timeZone=TimeZone(secondsFromGMT:0)
        output.dateFormat="dd/MM/yyyy"
        return output.string(from:date)
    }
}

struct StoryChapterRow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    let story: Story
    let chapter: Chapter
    let loading: Bool
    let selecting: Bool
    @Binding var selected: Set<String>
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                if selecting { Button { if selected.contains(chapter.id) { selected.remove(chapter.id) } else { selected.insert(chapter.id) } } label: { Image(systemName:selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").frame(width:44,height:44).contentShape(Rectangle()) } }
                WanyLink { ReaderView(story:story,chapter:chapter) } label: {
                    VStack(alignment:.leading,spacing:5) {
                        Text(chapter.title).font(RanyTypography.font(.subheadline)).lineLimit(2)
                        HStack(spacing:8) {
                            if store.state?.data.completed.contains(story.key+":"+chapter.id) == true { Text("مقروء").foregroundStyle(Theme.accent) }
                            else if let percent=store.state?.data.progress[story.key+":"+chapter.id]?.percent,percent>0 { Text("\(Int(percent))٪").foregroundStyle(Theme.accent) }
                            if let date=chapter.publishedAt.flatMap(StoryChapterDate.display) { Text(date).foregroundStyle(.secondary) }
                        }.font(RanyTypography.font(.caption))
                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()).foregroundStyle(.primary)
                }
                if !selecting {
                    ChapterReadingTools(
                        completed:store.state?.data.completed.contains(story.key+":"+chapter.id) == true,
                        disabled:!store.online || loading || store.loginRequired || store.syncing || store.readingMutation,
                        markRead:{ Task { await store.manualReadChapter(story,chapter:chapter.number) } },
                        markUnread:{ Task { await store.manualUnread(story,chapter:chapter.number) } }
                    )
                }
                if downloads.savedJobs.first(where:{$0.id == story.key})?.chapters.first(where:{$0.id == chapter.id})?.complete == true {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(.green).frame(width:44,height:44)
                } else {
                    Button { Task { await downloads.enqueue(story,chapters:[chapter]) } } label: {
                        Image(systemName:"arrow.down.circle").font(RanyTypography.font(.title3)).frame(width:44,height:44).contentShape(Rectangle())
                    }.buttonStyle(.borderless).disabled(!store.online)
                }
            }.padding(.vertical,10)
            Divider()
        }
    }
}

#if DEBUG
// Offline fixture for real simulator taps; excluded from Release builds.
struct ChapterControlsFixture: View {
    @State private var completed=false
    @State private var page=1
    @State private var disabled=false
    @State private var action="none"
    var body: some View {
        VStack(spacing:18) {
            Text("الفصول").font(RanyTypography.font(.title3).bold())
            StoryReadingTools(canReadAll:true,disabled:disabled,markAll:{ action="read-all" },clear:{ action="clear-all" })
            HStack {
                Text("الفصل 408.3").font(RanyTypography.font(.subheadline)).frame(maxWidth:.infinity,alignment:.leading)
                ChapterReadingTools(completed:completed,disabled:disabled,markRead:{ completed=true },markUnread:{ completed=false })
            }
            StoryChapterPagination(page:page,pages:3,onPage:{ page=$0 })
            Text(String(page)).accessibilityIdentifier("fixture.page")
            Text(action).accessibilityIdentifier("fixture.action")
            Toggle("إيقاف الأدوات",isOn:$disabled).accessibilityIdentifier("fixture.disabled")
            Spacer()
        }.padding(18).background(Theme.background.ignoresSafeArea())
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
    }
}
#endif
