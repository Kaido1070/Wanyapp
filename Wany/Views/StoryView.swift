import SwiftUI

struct StoryView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    let initial: Story
    @State private var detail: Story?
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var ascending = true
    @State private var selecting = false
    @State private var selected: Set<String> = []
    var story: Story { detail ?? store.stories[initial.key] ?? initial }
    var chapters: [Chapter] {
        let result = story.orderedChapters.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.contains(query) }
        return ascending ? result : result.reversed()
    }
    var body: some View {
        WanyScroll {
            HStack(alignment:.top,spacing:18) {
                CoverView(story:story).frame(width:112,height:164).clipShape(RoundedRectangle(cornerRadius:16))
                VStack(alignment:.leading,spacing:10) {
                    Text(story.title).font(.title2.bold())
                    Text(sourceLabel(story.source)).font(.caption).foregroundStyle(Theme.accent)
                    Text(story.status ?? story.type).font(.caption).foregroundStyle(.secondary)
                    Button { Task { await store.toggleFavorite(story) } } label: { Label(store.state?.data.favorites.contains(story.key) == true ? "في المفضلة" : "أضف للمفضلة",systemImage:store.state?.data.favorites.contains(story.key) == true ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                    Menu("حالة القراءة") { ForEach([("reading","أقرأ حاليًا"),("completed","مكتمل"),("paused","متوقف"),("planned","أخطط لقراءته")],id:\.0) { pair in Button(pair.1) { Task { await store.setStatus(story,status:pair.0) } } }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let description = story.description, !description.isEmpty { Text(description.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            if !story.genres.isEmpty { Text(story.genres.joined(separator:" · ")).font(.caption).foregroundStyle(Theme.accent).frame(maxWidth:.infinity,alignment:.leading) }
            if let recent = store.state?.data.library.first(where:{$0.mangaId == story.key})?.lastReadChapter {
                NavigationLink { ReaderView(story:story,chapter:story.chapters?.first(where:{$0.number == recent}) ?? Chapter(number:recent,title:"الفصل \(chapterNumber(recent))")) } label: { Label("متابعة الفصل \(chapterNumber(recent))",systemImage:"book.fill").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
            }
            Button { Task { await downloads.enqueue(story) } } label: {
                HStack { if downloads.preparing.contains(story.key) { ProgressView() }; Label(downloads.preparing.contains(story.key) ? "تجهيز جميع الفصول…" : "تحميل القصة كاملة",systemImage:"arrow.down.to.line").bold() }.frame(maxWidth:.infinity).padding(9)
            }.buttonStyle(.borderedProminent).disabled(downloads.preparing.contains(story.key) || !store.online)
            if let job = downloads.jobs.first(where:{$0.id == story.key}) { DownloadSummary(job:job).card() }
            HStack { Text("الفصول · \(story.chapters?.count ?? 0)").font(.title3.bold()); Spacer(); if loading { ProgressView() }; Button { ascending.toggle() } label: { Image(systemName:"arrow.up.arrow.down") }; Button(selecting ? "إلغاء" : "تحديد") { selecting.toggle(); selected.removeAll() } }
            if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("إعادة جلب قائمة الفصول") { Task { await refresh() } } }
            if !store.online { Text("التفاصيل محفوظة. الفصول بعلامة ✓ متاحة بدون إنترنت؛ الفصول الناقصة تحتاج اتصالًا لاستكمال الصور.").font(.caption).foregroundStyle(.secondary) }
            TextField("ابحث برقم الفصل أو عنوانه",text:$query).textFieldStyle(.roundedBorder).keyboardType(.default)
            if selecting {
                HStack { Button("تحديد الكل") { selected = Set(chapters.map(\.id)) }; Spacer(); Button("تحميل \(selected.count) فصل") { let list = chapters.filter { selected.contains($0.id) }; Task { await downloads.enqueue(story,chapters:list) }; selecting = false }.disabled(selected.isEmpty || !store.online) }
            }
            LazyVStack(spacing:2) {
                ForEach(chapters) { chapter in
                    HStack {
                        if selecting { Button { if selected.contains(chapter.id) { selected.remove(chapter.id) } else { selected.insert(chapter.id) } } label: { Image(systemName:selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle") } }
                        NavigationLink { ReaderView(story:story,chapter:chapter) } label: {
                            VStack(alignment:.leading,spacing:5) { Text(chapter.title).font(.subheadline); if store.state?.data.completed.contains(story.key+":"+chapter.id) == true { Text("مقروء").font(.caption2).foregroundStyle(Theme.accent) } }.frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.primary)
                        }
                        if downloads.jobs.first(where:{$0.id == story.key})?.chapters.first(where:{$0.id == chapter.id})?.complete == true { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                        else { Button { Task { await downloads.enqueue(story,chapters:[chapter]) } } label: { Image(systemName:"arrow.down.circle").font(.title3) }.disabled(!store.online) }
                    }.padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
                }
            }
        }.navigationTitle(story.title).navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }.refreshable { await refresh() }
    }
    func refresh() async {
        guard store.online, !loading else { return }; loading = true; defer { loading = false }
        do { let value = try await API.shared.fullSeries(initial.key); detail = value; store.remember(value); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
