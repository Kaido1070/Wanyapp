import SwiftUI
import ImageIO

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: Downloads
    @State private var registeredOpen: String?
    @State private var catchupPrompt=false
    @State private var catchupShown=false
    @State private var enteredFromReader=false
    @Environment(\.dismiss) var dismiss
    @Environment(\.ranyNavigator) private var navigator
    let story: Story
    let chapter: Chapter
    @State private var payload: ChapterPayload?
    @State private var error: String?
    @State private var currentPage: Int?
    @State private var interacted = false
    @State private var controls = true
    @State private var scrollDirection = ReaderScrollDirection(revealDistance:288)
    @State private var activeChapter: Chapter?
    @State private var choosingChapter = false
    @State private var choosingQuality = false
    @State private var confirmQualityReload = false
    @State private var chapterQuery = ""
    @State private var headerHeight: CGFloat = 160
    @State private var saveTask: Task<Void,Never>?
    @State private var pageRatios: [Int:CGFloat] = [:]
    @State private var percent: CGFloat = 0
    private func leaveReader() { if let navigator { navigator.pop() } else { dismiss() } }
    var readingChapter: Chapter { activeChapter ?? chapter }
    var chapters: [Chapter] { (store.stories[story.key] ?? story).orderedChapters }
    var previousChapter: Chapter? { neighbor(forward:false) }
    var nextChapter: Chapter? { neighbor(forward:true) }
    var body: some View {
        GeometryReader { screen in
            ZStack(alignment:.top) {
                Color.black.ignoresSafeArea()
                if let payload {
                    ReaderChapterScroll(id:payload.id,endTitle:"نهاية الفصل \(chapterNumber(payload.number))",
                        urls:payload.pages.indices.map { downloads.pageURL(payload,index:$0) },
                        ratios:pageRatios,initialPage:restoredPage(payload),
                        nextTitle:nextChapter.map { "الفصل التالي \($0.id)" },online:store.online,quality:downloads.quality,
                        onNext:{ if let next = nextChapter { open(next) } },onBack:{ leaveReader() },
                        onRetry:{ downloads.retryChapter(payload) },
                        onInvalid:{ downloads.invalidatePage(payload,index:$0) },
                        onPosition:{ page,value,moved in
                            currentPage = page; percent = CGFloat(value)
                            if moved { interacted = true; scheduleSave() }
                        },onScroll:{ offset,moving in
                            if let visible = scrollDirection.update(offset:offset,userScrolling:moving), visible != controls {
                                withAnimation(.easeInOut(duration:0.22)) { controls = visible }
                            }
                        }).id(payload.id)
                        .ignoresSafeArea(.container,edges:.vertical)
                } else if let error { VStack(spacing:20) { EmptyState(icon:"wifi.slash",title:"تعذر فتح الفصل",detail:error); Button("إعادة المحاولة") { Task { await load() } }; Button("العودة") { leaveReader() } }.padding() }
                else { ProgressView("تجهيز الفصل…").frame(maxWidth:.infinity,maxHeight:.infinity) }
                VStack(spacing:10) {
                    HStack {
                        Button { leaveReader() } label: { Image(systemName:"chevron.right").padding(10) }.accessibilityLabel("العودة للفصول")
                        VStack(alignment:.leading,spacing:3) {
                            Text(readingChapter.title).font(RanyTypography.font(.subheadline).bold()).lineLimit(1)
                            if let payload { Text("\((currentPage ?? 0)+1) / \(payload.pages.count)").font(RanyTypography.font(.caption)).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength:8)
                        if let payload {
                            Menu {
                                Button("جودة الصور: \(downloads.quality.label)",systemImage:"photo.badge.checkmark") { choosingQuality=true }
                                Button("إعادة تحميل الصور الناقصة",systemImage:"arrow.clockwise") { downloads.retryChapter(payload) }.disabled(!store.online)
                            } label: {
                                Image(systemName:"slider.horizontal.3").frame(width:44,height:44).contentShape(Rectangle())
                            }.menuActionDismissBehavior(.enabled).accessibilityLabel("جودة الصور وإعادة التحميل")
                        }
                    }
                    HStack(spacing:12) {
                        Button { if let previous = previousChapter { open(previous) } } label: { Label("السابق",systemImage:"chevron.right") }.disabled(previousChapter == nil)
                        Spacer(minLength:0)
                        Button { chapterQuery = ""; choosingChapter = true } label: { Label("اختيار الفصل",systemImage:"list.bullet") }
                        Spacer(minLength:0)
                        Button { if let next = nextChapter { open(next) } } label: { Label("التالي",systemImage:"chevron.left") }.disabled(nextChapter == nil)
                    }.font(RanyTypography.font(.subheadline)).padding(.horizontal,8)
                }.padding(10).background(.ultraThinMaterial)
                    .background(GeometryReader { proxy in Color.clear.preference(key:ReaderHeaderHeightKey.self,value:proxy.size.height) })
                    .onPreferenceChange(ReaderHeaderHeightKey.self) { headerHeight = $0 }
                    .offset(y:controls ? 0 : -(headerHeight + screen.safeAreaInsets.top + 12))
                    .opacity(controls ? 1 : 0).allowsHitTesting(controls)
            }
        }.toolbar(.hidden,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .sheet(isPresented:$choosingChapter) { chapterPicker }
        .sheet(isPresented:$choosingQuality) { qualitySettings }
        .confirmationDialog("هل قرأت الفصول السابقة؟",isPresented:$catchupPrompt,titleVisibility:.visible) {
            Button("تعليم الفصول السابقة كمقروءة") { Task { await store.manualRead(story,chapters:previousUnread) } }.disabled(!store.online || store.syncing || store.readingMutation)
            Button("لاحقًا",role:.cancel) {}
        } message: { Text("يوجد \(previousUnread.count) فصل سابق غير مكتمل. هذه عملية قراءة مستقلة عن التنزيل.") }
        .task(id:readingChapter.id) { await load() }
        .task {
            if store.online, let full = try? await API.shared.fullSeries(story.key), !Task.isCancelled { store.remember(full) }
        }
        .onAppear { store.readerActive = true; store.chromeHidden = true }
        .onDisappear {
            saveTask?.cancel()
            store.readerActive = false; store.chromeHidden = false
            if let payload { downloads.leaveChapter(payload.id) }
            savePosition()
            Task { await store.syncProgress() }
        }
    }
    var qualitySettings: some View {
        NavigationStack {
            Form {
                Section("جودة القراءة والتنزيل") {
                    ImageQualityChoices(selected:downloads.quality,select:{ downloads.quality=$0 })
                }
                Section {
                    Text("تغيير الاختيار يطبق على الصور الجديدة. لتحسين فصل محمل سابقًا، أعد تنزيله بالجودة المختارة. الدقة المتاحة تعتمد على المصدر.")
                        .font(RanyTypography.font(.footnote)).foregroundStyle(.secondary)
                    if let payload {
                        if let issue=downloads.qualityError(payload) { Text(issue).font(RanyTypography.font(.caption)).foregroundStyle(.orange) }
                        if downloads.isQualityUpgrade(payload) {
                            Label("الجودة الجديدة في قائمة التنزيل؛ الصور السابقة تبقى متاحة",systemImage:"arrow.down.circle")
                            Button("إعادة محاولة الصور الناقصة") { downloads.retryChapter(payload) }.disabled(!store.online)
                        }
                        Button("إعادة تنزيل هذا الفصل بجودة \(downloads.quality.label)") { confirmQualityReload=true }.disabled(!store.online)
                    }
                }
            }.navigationTitle("جودة الصور").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("تم") { choosingQuality=false } } }
                .confirmationDialog("إعادة تنزيل صور الفصل؟",isPresented:$confirmQualityReload,titleVisibility:.visible) {
                    Button("تنزيل بجودة \(downloads.quality.label)") { if let payload { downloads.redownload(payload,quality:downloads.quality) } }
                    Button("إلغاء",role:.cancel) {}
                } message: { Text("قد يزيد استهلاك البيانات والمساحة. لن تُحذف الصور الحالية قبل اكتمال البديل، ولن يتغير تقدم قراءتك.") }
        }.environment(\.layoutDirection,.rightToLeft).tint(Theme.accent)
    }
    var chapterPicker: some View {
        NavigationStack {
            List {
                if chapters.isEmpty { Text("قائمة الفصول غير متاحة حاليًا. اتصل بالإنترنت لتحديثها.").foregroundStyle(.secondary) }
                ForEach(chapters.filter { chapterQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(chapterQuery) || $0.id.contains(chapterQuery) }) { item in
                    Button { choosingChapter = false; open(item) } label: {
                        HStack {
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            if item.id == readingChapter.id { Image(systemName:"book.fill").foregroundStyle(Theme.accent) }
                            if downloads.savedJobs.first(where:{$0.id == story.key})?.chapters.first(where:{$0.id == item.id})?.complete == true { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                        }
                    }
                }
            }.searchable(text:$chapterQuery,prompt:"رقم الفصل أو عنوانه")
                .navigationTitle("اختيار الفصل").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("إغلاق") { choosingChapter = false } } }
        }.environment(\.layoutDirection,.rightToLeft)
    }
    private var previousUnread: [Double] {
        guard let state=store.state else { return [] }
        return (payload?.item ?? story).orderedChapters.filter { $0.number < readingChapter.number && !state.data.completed.contains(story.key+":"+$0.id) }.map(\.number)
    }
    private func recordOpen(_ value: ChapterPayload) {
        guard registeredOpen != value.id else { return }; registeredOpen=value.id
        store.queueChapterOpen(value); Task { await store.syncProgress() }
        if !enteredFromReader,!catchupShown,(payload?.item ?? story).chapterListComplete != false,!previousUnread.isEmpty {
            catchupShown=true; catchupPrompt=true
        }
    }
    func neighbor(forward: Bool) -> Chapter? {
        if let index = chapters.firstIndex(where:{$0.id == readingChapter.id}) {
            let target = index + (forward ? 1 : -1)
            return chapters.indices.contains(target) ? chapters[target] : nil
        }
        guard let number = forward ? payload?.next : payload?.previous else { return nil }
        return chapters.first(where:{$0.number == number}) ?? Chapter(number:number,title:"الفصل \(chapterNumber(number))")
    }
    func scheduleSave() {
        saveTask?.cancel()
        let id = payload?.id
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for:.milliseconds(400)) } catch { return }
            guard !Task.isCancelled, payload?.id == id else { return }
            savePosition()
        }
    }
    func cachedRatios(_ value: ChapterPayload, owner: String) -> [Int:CGFloat] {
        var result: [Int:CGFloat] = [:]
        for index in value.pages.indices {
            if let metadata = value.pageMeta, metadata.indices.contains(index), let w = metadata[index].width, let h = metadata[index].height, w > 0, h > 0 { result[index] = CGFloat(h/w) }
            let file = downloads.pageURL(value,index:index) ?? Disk.file(owner,Disk.imageName(value.id,index))
            if let source = CGImageSourceCreateWithURL(file as CFURL,nil), let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
               let w = properties[kCGImagePropertyPixelWidth] as? NSNumber, let h = properties[kCGImagePropertyPixelHeight] as? NSNumber, w.doubleValue > 0, h.doubleValue > 0 {
                result[index] = CGFloat(h.doubleValue/w.doubleValue)
            }
        }
        return result
    }
    func savePosition() {
        guard let payload, interacted else { return }
        let complete = payload.pages.indices.allSatisfy { downloads.pageURL(payload,index:$0) != nil }
        store.record(payload,page:currentPage ?? 0,percent:Double(complete ? percent : min(percent,97)))
    }
    func open(_ target: Chapter) {
        guard target.id != readingChapter.id else { return }
        saveTask?.cancel(); savePosition()
        if let payload { downloads.leaveChapter(payload.id) }
        payload = nil; error = nil; currentPage = nil; interacted = false
        percent = 0; pageRatios = [:]; scrollDirection = ReaderScrollDirection(revealDistance:288); controls = true
        registeredOpen=nil; enteredFromReader=true
        activeChapter = target
        Task { await store.syncProgress() }
    }
    func restoredPage(_ payload: ChapterPayload) -> Int {
        if let p = store.state?.positions[payload.id] { return min(max(0,p),payload.pages.count-1) }
        let progress = store.state?.data.progress[payload.id]?.percent ?? 0
        return min(payload.pages.count-1,max(0,Int(progress/100*Double(payload.pages.count))))
    }
    func load() async {
        error = nil
        guard let owner = store.state?.user.id else { return }
        let requested = readingChapter
        let id = story.key+":"+requested.id
        if let saved = Disk.read(ChapterPayload.self,owner:owner,name:Disk.chapterName(id)) {
            pageRatios = cachedRatios(saved,owner:owner)
            payload = saved; currentPage = restoredPage(saved)
            downloads.usePayload(saved); recordOpen(saved)
            return
        }
        guard store.online else { error = "هذا الفصل غير محمل. اتصل بالإنترنت لتنزيله؛ بقية الفصول المحملة متاحة من التنزيلات."; return }
        do {
            let value = try await API.shared.chapter(story.key,requested)
            guard !Task.isCancelled, readingChapter.id == requested.id, store.state?.user.id == owner else { return }
            pageRatios = cachedRatios(value,owner:owner)
            payload = value; currentPage = restoredPage(value); downloads.usePayload(value); store.remember(value.item); recordOpen(value)
        } catch { if !Task.isCancelled, readingChapter.id == requested.id { self.error = error.localizedDescription } }
    }
}

private struct ReaderHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
