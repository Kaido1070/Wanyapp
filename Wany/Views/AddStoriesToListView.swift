import SwiftUI

struct AddStoriesToListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    @StateObject private var page = CachedPage()
    @State private var query = ""
    @State private var busy: Set<String> = []
    var members: Set<String> { Set(page.value["items"].array.map { $0["mangaId"].string }) }
    var stories: [Story] { store.stories.values.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.sorted { $0.title < $1.title } }
    var body: some View {
        NavigationStack {
            List(stories) { story in
                Button { Task { await add(story) } } label: {
                    HStack(spacing:14) {
                        Text(story.title).foregroundStyle(.primary)
                        Spacer()
                        if busy.contains(story.key) { ProgressView() }
                        else { Image(systemName:members.contains(story.key) ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(Theme.accent) }
                    }.frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(members.contains(story.key) || busy.contains(story.key) || !store.online)
            }.scrollContentBackground(.hidden).ranyClearNavigation().searchable(text:$query,prompt:"ابحث في قصصك")
                .navigationTitle("إضافة قصص للقائمة")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("تم") { dismiss() } } }
                .task { await page.load("/api/lists/"+id,store:store) }
        }.ranyClearNavigation().environment(\.layoutDirection,.rightToLeft)
    }
    func add(_ story: Story) async {
        guard !busy.contains(story.key) else { return }
        busy.insert(story.key); defer { busy.remove(story.key) }
        do { try await API.shared.send("/api/lists/"+id+"/items",value:["mangaId":story.key]); store.queueSnapshot(story); await page.load("/api/lists/"+id,store:store) }
        catch { if !isRequestCancellation(error) { store.error = error.localizedDescription } }
    }
}
