import Foundation
import Combine

@MainActor final class ActivityPager: ObservableObject {
    @Published private(set) var items: [ActivityItem] = []
    @Published private(set) var loading=false
    @Published private(set) var hasMore=true
    @Published private(set) var error: String?
    private var offset=0
    private var token=UUID()
    private var account: String?
    private var selectedPath=""
    func cancel() { token=UUID(); loading=false }
    func load(store: AppStore,friends: Bool,reset: Bool = false) async {
        guard reset || (!loading && hasMore),let owner=store.state?.user.id else { return }
        let path=friends ? "/api/activity/friends" : "/api/activity/me"
        if account != owner || path != selectedPath { items=[]; offset=0; hasMore=true; account=owner; selectedPath=path }
        let request=UUID(); token=request; loading=true; error=nil
        defer { if token == request { loading=false } }
        guard store.online else {
            if !friends { items=(Disk.read([JSONValue].self,owner:owner,name:"activity/me.json") ?? []).map(ActivityItem.init) }
            else { items=[] }
            error=friends ? "تحتاج أنشطة الأصدقاء اتصالًا للتحقق من صلاحية العرض." : "تعرض الأنشطة المحفوظة؛ اتصل لتحميل المزيد."
            return
        }
        let next=reset ? 0 : offset
        do {
            let response=try await API.shared.get(path,query:["limit":"20","offset":String(next)],as:JSONValue.self)
            guard token == request,store.state?.user.id == owner,!Task.isCancelled else { return }
            let incoming=response["events"].array.map(ActivityItem.init)
            items=ActivityPagination.append(incoming,to:reset ? [] : items)
            offset=next+incoming.count; hasMore=response["hasMore"].boolean && !incoming.isEmpty
            if !friends { try? Disk.save(items.map(\.value),owner:owner,name:"activity/me.json") }
            await store.resolveMetadata(incoming.map { $0.value["mangaId"].string })
        } catch {
            guard token == request,!Task.isCancelled else { return }
            self.error=error.localizedDescription
            if (error as? APIError)?.status == 401 { store.report(error) }
        }
    }
}
