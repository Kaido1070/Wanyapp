import SwiftUI

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @StateObject private var pager=ActivityPager()
    @State private var friends=false
    var body: some View {
        WanyScroll {
            Text("النشاط").font(.largeTitle.bold())
            Picker("النشاط",selection:$friends) { Text("نشاطي").tag(false); Text("الأصدقاء").tag(true) }.pickerStyle(.segmented)
            LazyVStack(spacing:14) { ForEach(pager.items) { ActivityEventRow(event:$0.value) } }
            if pager.loading { ProgressView("تحميل النشاط…") }
            if let error=pager.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if pager.hasMore && !pager.loading {
                Button(pager.error == nil ? "تحميل نشاط أقدم" : "إعادة المحاولة") { Task { await pager.load(store:store,friends:friends) } }.disabled(!store.online)
            }
        }.task(id:friends) { await pager.load(store:store,friends:friends,reset:true) }
            .refreshable { await pager.load(store:store,friends:friends,reset:true) }
            .onDisappear { pager.cancel() }
    }
}
