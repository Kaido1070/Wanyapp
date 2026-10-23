import SwiftUI

struct ListsView: View {
    @Environment(AppStore.self) private var store
    @StateObject private var collections=CollectionsStore()
    @State private var editor=false
    var body: some View {
        WanyScroll {
            HStack { Text("قوائمي").font(.largeTitle.bold()); Spacer(); Button("قائمة جديدة",systemImage:"plus") { editor=true }.disabled(!store.online) }
            ForEach(collections.managed) { section in
                VStack(alignment:.leading,spacing:12) {
                    HStack {
                        if section.sectionType == "favorites" { Label("المفضلة",systemImage:"heart") }
                        else { WanyLink(.listDetail(id:section.referenceId ?? "",title:section.title)) { Label(section.title,systemImage:ListIcons.symbol(section.list?.iconKey ?? "lists")).foregroundStyle(.primary) } }
                        Spacer()
                        Menu {
                            Button(section.isVisible ? "إخفاء القسم" : "إظهار القسم",systemImage:section.isVisible ? "eye.slash" : "eye") { toggle(section) }
                            Button("نقل للأعلى",systemImage:"arrow.up") { move(section,delta:-1) }
                            Button("نقل للأسفل",systemImage:"arrow.down") { move(section,delta:1) }
                        } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.disabled(collections.busy || !store.online)
                    }
                    if let description=section.list?.description,!description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                    HStack { Text("\(section.list?.itemCount ?? store.state?.data.favorites.count ?? 0) قصة"); if !section.isVisible { Label("مخفي في أقسامك",systemImage:"eye.slash") } }.font(.caption2).foregroundStyle(.secondary)
                }.card().draggable(section.id)
                .dropDestination(for:String.self) { ids,_ in drop(ids.first,onto:section); return ids.first != nil }
            }
            Text("اسحب القسم لتغيير ترتيبه، أو استخدم قائمة الخيارات. يُحفظ الترتيب نفسه في الموقع.").font(.caption).foregroundStyle(.secondary)
            if collections.busy { ProgressView() }
            if let message=collections.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.task(id:store.state?.user.id) { await collections.load(store) }.refreshable { await collections.load(store) }
        .sheet(isPresented:$editor,onDismiss:{ Task { await collections.load(store) } }) { ListEditorSheet() }
        .onReceive(NotificationCenter.default.publisher(for:.ranyCollectionsChanged)) { _ in Task { await collections.load(store) } }
    }
    private func toggle(_ section: RanyProfileSection) {
        var proposed=collections.sections; guard let index=proposed.firstIndex(where:{$0.id == section.id}) else { return }
        proposed[index].isVisible.toggle(); Task { await collections.save(proposed,store:store) }
    }
    private func move(_ section: RanyProfileSection,delta: Int) {
        let managed=collections.managed; guard let from=managed.firstIndex(where:{$0.id == section.id}) else { return }
        let reordered=SectionOrder.moving(managed,from:from,to:from+delta)
        Task { await collections.save(SectionOrder.replacingManaged(collections.sections,with:reordered),store:store) }
    }
    private func drop(_ id: String?,onto target: RanyProfileSection) {
        guard let id,let from=collections.managed.firstIndex(where:{$0.id == id}),let to=collections.managed.firstIndex(where:{$0.id == target.id}),from != to else { return }
        let ordered=SectionOrder.moving(collections.managed,from:from,to:to)
        Task { await collections.save(SectionOrder.replacingManaged(collections.sections,with:ordered),store:store) }
    }
}

struct ListEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var list: RanyList? = nil
    var addingStory: Story? = nil
    var onCreated: (String)->Void = { _ in }
    @State private var name=""
    @State private var description=""
    @State private var icon="lists"
    @State private var busy=false
    @State private var error: String?
    @State private var createdID: String?
    @State private var saveTask: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            WanyScroll {
                VStack(alignment:.leading,spacing:18) {
                    TextField("اسم القائمة · حتى 80 حرفًا",text:$name)
                    TextField("وصف القائمة · حتى 500 حرف",text:$description,axis:.vertical).lineLimit(3...6)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:52))]) {
                        ForEach(ListIcons.keys,id:\.self) { key in
                            Button { icon=key } label: { Image(systemName:ListIcons.symbol(key)).frame(width:46,height:46).background(icon == key ? Theme.accent.opacity(0.25) : .clear,in:RoundedRectangle(cornerRadius:12)) }.accessibilityLabel(key)
                        }
                    }
                    if let error { Text(error).foregroundStyle(.orange).font(.caption) }
                    if busy { ProgressView() }
                    Button(createdID == nil ? (list == nil ? "إنشاء القائمة" : "حفظ التعديلات") : "إعادة محاولة إضافة القصة") { saveTask=Task { await save() } }
                        .disabled(!ListEditorInput(name:name,description:description,iconKey:icon).valid || busy || !store.online)
                }.card()
            }.navigationTitle(list == nil ? "قائمة جديدة" : "تعديل القائمة").disabled(busy)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("إغلاق") { dismiss() } } }
        }.environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
        .onAppear { if let list { name=list.name; description=list.description ?? ""; icon=list.iconKey } }
        .onDisappear { saveTask?.cancel(); saveTask=nil }
    }
    private func save() async {
        guard let owner=store.state?.user.id,!busy else { return }; busy=true; error=nil; defer { busy=false }
        do {
            let id: String
            if let createdID { id=createdID }
            else {
                let result=try await API.shared.getMutation(list.map { "/api/lists/"+apiComponent($0.id) } ?? "/api/lists",value:ListEditorInput(name:name.trimmingCharacters(in:.whitespacesAndNewlines),description:description,iconKey:icon),method:list == nil ? "POST" : "PUT")
                guard !Task.isCancelled,store.state?.user.id == owner else { return }; id=result["list"]["id"].string
                guard !id.isEmpty else { throw APIError(message:"لم يرجع الخادم معرّف القائمة",status:0) }
                if list == nil { createdID=id }
            }
            if let story=addingStory { store.queueSnapshot(story); try await API.shared.send("/api/lists/"+apiComponent(id)+"/items",value:["mangaId":story.key]) }
            guard !Task.isCancelled,store.state?.user.id == owner else { return }
            NotificationCenter.default.post(name:.ranyCollectionsChanged,object:owner); onCreated(id); dismiss()
        } catch { if !Task.isCancelled,store.state?.user.id == owner,!isRequestCancellation(error) { self.error=createdID == nil ? error.localizedDescription : "أُنشئت القائمة، وتعذرت إضافة القصة. أعد المحاولة لإضافتها دون تكرار القائمة."; store.report(error) } }
    }
}

struct ListDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String
    let title: String
    @StateObject private var page=CachedPage()
    @State private var adding=false
    @State private var editing=false
    @State private var deleting=false
    @State private var busy=false
    @State private var visible=false
    var keys: [String] { page.value["items"].array.map { $0["mangaId"].string } }
    var list: RanyList? { try? JSONDecoder().decode(RanyList.self,from:JSONEncoder().encode(page.value["list"])) }
    var canManage: Bool { page.value["list"]["canManage"].boolean }
    var body: some View {
        WanyScroll {
            HStack {
                Label(list?.name ?? title,systemImage:ListIcons.symbol(list?.iconKey ?? "lists")).font(.title2.bold()); Spacer()
                if canManage {
                    Menu {
                        Button("إضافة قصص",systemImage:"plus") { adding=true }
                        Button("تعديل الاسم والوصف والأيقونة",systemImage:"pencil") { editing=true }
                        Button("حذف القائمة",systemImage:"trash",role:.destructive) { deleting=true }
                    } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.disabled(!store.online || busy)
                }
            }
            if let text=list?.description,!text.isEmpty { Text(text).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(keys,id:\.self) { key in
                HStack {
                    if let story=store.stories[key] { WanyLink(.story(story)) { HStack { CoverView(story:story).frame(width:42,height:60).clipShape(RoundedRectangle(cornerRadius:6)); Text(story.title).foregroundStyle(.primary) } } }
                    else { Text(key).font(.caption) }
                    Spacer()
                    if canManage {
                        Menu {
                            Button("نقل للأعلى") { reorder(key,delta:-1) }
                            Button("نقل للأسفل") { reorder(key,delta:1) }
                            Button("إزالة من القائمة",role:.destructive) { mutate("/api/lists/"+apiComponent(id)+"/items/"+apiComponent(key),method:"DELETE") }
                        } label: { Image(systemName:"line.3.horizontal").frame(width:44,height:44) }.disabled(!store.online || busy)
                    }
                }.card().draggable(canManage ? key : "")
                    .dropDestination(for:String.self) { values,_ in guard canManage,let moved=values.first,let from=keys.firstIndex(of:moved),let to=keys.firstIndex(of:key) else { return false }; reorder(moved,delta:to-from); return true }
            }
            if busy || page.loading { ProgressView() }
            if let error=page.error { Text(error).foregroundStyle(.orange); Button("إعادة المحاولة") { Task { await load() } } }
        }.navigationTitle(list?.name ?? title).onAppear { visible=true }.onDisappear { visible=false }.task(id:store.state?.user.id) { await load() }.refreshable { await load() }
        .sheet(isPresented:$adding,onDismiss:{ Task { await load() } }) { AddStoriesToListView(id:id) }
        .sheet(isPresented:$editing,onDismiss:{ Task { await load() } }) { if let list { ListEditorSheet(list:list) } }
        .confirmationDialog("حذف القائمة بالكامل؟",isPresented:$deleting,titleVisibility:.visible) { Button("حذف القائمة",role:.destructive) { mutate("/api/lists/"+apiComponent(id),method:"DELETE",exit:true) }; Button("إلغاء",role:.cancel) {} } message: { Text("لا تُحذف القصص أو تقدم قراءتك.") }
    }
    private func load() async { await page.load("/api/lists/"+apiComponent(id),store:store); await store.resolveMetadata(keys) }
    private func mutate(_ path: String,method: String,exit: Bool = false) {
        guard !busy else { return }; busy=true
        let owner=store.state?.user.id
        Task { @MainActor in
            defer { busy=false }
            do {
                _=try await API.shared.raw(path,method:method)
                guard owner == store.state?.user.id else { return }
                NotificationCenter.default.post(name:.ranyCollectionsChanged,object:owner)
                if exit {
                    // A late response must not close whichever page replaced this one.
                    if visible { dismiss() }
                } else { await load() }
            } catch { store.report(error) }
        }
    }
    private func reorder(_ key: String,delta: Int) {
        guard !busy,let from=keys.firstIndex(of:key),keys.indices.contains(from+delta),store.online else { return }
        let next=SectionOrder.moving(keys,from:from,to:from+delta), index=from+delta
        var body=["mangaId":key]
        if index+1 < next.count { body["beforeId"]=next[index+1] }
        else if index>0 { body["afterId"]=next[index-1] }
        busy=true; let owner=store.state?.user.id
        Task { @MainActor in
            defer { busy=false }
            do { try await API.shared.send("/api/lists/"+apiComponent(id)+"/reorder",method:"PUT",value:body); guard owner == store.state?.user.id else { return }; await load(); NotificationCenter.default.post(name:.ranyCollectionsChanged,object:owner) }
            catch { store.report(error); await load() }
        }
    }
}

struct StoryListPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let story: Story
    @StateObject private var page=CachedPage()
    @StateObject private var membership=CachedPage()
    @State private var creating=false
    @State private var busy=false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Button("إنشاء قائمة وإضافة هذه القصة",systemImage:"plus") { creating=true }
                ForEach(Array(page.value["lists"].array.enumerated()),id:\.offset) { _,list in
                    let id=list["id"].string
                    Button { Task { await add(id) } } label: {
                        HStack { Label(list["name"].string,systemImage:ListIcons.symbol(list["iconKey"].string)); Spacer(); if membership.value["listIds"].array.map(\.string).contains(id) { Image(systemName:"checkmark") } }
                    }.disabled(busy || membership.value["listIds"].array.map(\.string).contains(id))
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }.scrollContentBackground(.hidden).ranyClearNavigation().navigationTitle("إضافة إلى قائمة").disabled(!store.online)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("تم") { dismiss() } } }
                .task { await load() }
        }.environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
        .sheet(isPresented:$creating,onDismiss:{ Task { await load() } }) { ListEditorSheet(addingStory:story) }
    }
    private func load() async { await page.load("/api/lists",store:store); await membership.load("/api/lists/membership/"+apiComponent(story.key),store:store) }
    private func add(_ id: String) async {
        busy=true; defer { busy=false }
        do { try await API.shared.send("/api/lists/"+apiComponent(id)+"/items",value:["mangaId":story.key]); store.queueSnapshot(story); await load(); NotificationCenter.default.post(name:.ranyCollectionsChanged,object:store.state?.user.id) }
        catch { self.error=error.localizedDescription; store.report(error) }
    }
}
