import SwiftUI

struct DiscoveryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: CatalogFilter
    @Binding var source: String
    @State private var draft=CatalogFilter()
    var body: some View {
        NavigationStack {
            Form {
                Section("المصدر") { Picker("المصدر",selection:$draft.source) { Text("كل المصادر").tag("all"); ForEach(sources,id:\.self) { Text(sourceLabel($0)).tag($0) } } }
                Section("نوع العمل") { Picker("النوع",selection:$draft.type) { Text("الكل").tag("all"); ForEach(CatalogRules.options.types) { Text($0.label).tag($0.id) } } }
                Section("حالة النشر") { Picker("الحالة",selection:$draft.status) { Text("الكل").tag("all"); ForEach(CatalogRules.options.statuses) { Text($0.label).tag($0.id) } } }
                Section("التصنيفات") {
                    Text("يُقبل أي تصنيف مختار، مع تطبيق النوع والحالة والمصدر معًا.").font(.caption).foregroundStyle(.secondary)
                    ForEach(CatalogRules.options.genres) { genre in
                        Toggle(genre.label,isOn:Binding(get:{ draft.genres.contains(genre.id) },set:{ value in if value { draft.genres.append(genre.id) } else { draft.genres.removeAll { $0 == genre.id } } }))
                    }
                }
            }.scrollContentBackground(.hidden).ranyClearNavigation().navigationTitle("فلاتر الاستكشاف")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("تطبيق") { draft.genres=Array(Set(draft.genres)).sorted(); filter=draft; source=draft.source; dismiss() } }
                    ToolbarItem(placement:.bottomBar) { Button("مسح الفلاتر") { draft=CatalogFilter() } }
                }
        }.environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark)
        .onAppear { draft=filter; draft.source=source }
    }
}
struct MergedStoryGrid: View {
    let stories: [Story]
    var showReadingProgress=false
    @State private var groups: [StorySourceGroup] = []
    var body: some View {
        LazyVGrid(columns:[GridItem(.flexible(),alignment:.top),GridItem(.flexible(),alignment:.top)],alignment:.leading,spacing:20) {
            ForEach(groups) { group in StoryCard(story:group.primary,showReadingProgress:showReadingProgress,sourceKeys:group.items.map(\.key)) }
        }.task(id:stories) { let value=await CatalogRules.groups(stories); if !Task.isCancelled { groups=value } }
    }
}
