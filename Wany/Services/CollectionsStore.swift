import Foundation
import Combine

@MainActor final class CollectionsStore: ObservableObject {
    @Published var sections: [RanyProfileSection] = []
    @Published var busy=false
    @Published var message: String?
    private var owner: String?
    var managed: [RanyProfileSection] { sections.filter(\.managed) }
    func load(_ store: AppStore) async {
        guard !busy,let id=store.state?.user.id else { return }
        if owner != id { sections=[]; message=nil; owner=id }
        sections=Disk.read([RanyProfileSection].self,owner:id,name:"collections/sections.json") ?? sections
        guard store.online else { return }
        busy=true; defer { busy=false }
        do {
            let value=try await API.shared.get("/api/profile/sections",as:SectionsResponse.self)
            guard store.state?.user.id == id else { return }
            sections=value.sections.sorted { $0.position < $1.position }; try Disk.save(sections,owner:id,name:"collections/sections.json")
        } catch { if !isRequestCancellation(error) { message=error.localizedDescription; store.report(error) } }
    }
    func save(_ proposed: [RanyProfileSection],store: AppStore) async {
        guard !busy,store.online,let id=store.state?.user.id else { return }
        let previous=sections; sections=proposed; busy=true; message=nil; defer { busy=false }
        struct Payload: Encodable { let sections: [ProfileSectionInput] }
        do {
            let response=try await API.shared.getMutation("/api/profile/sections",value:Payload(sections:proposed.map(\.payload)),method:"PUT")
            guard store.state?.user.id == id else { return }
            let value=try JSONDecoder().decode(SectionsResponse.self,from:JSONEncoder().encode(response))
            sections=value.sections.sorted { $0.position < $1.position }; try Disk.save(sections,owner:id,name:"collections/sections.json")
            message="تم حفظ الترتيب والظهور."; NotificationCenter.default.post(name:.ranyCollectionsChanged,object:id)
        } catch { sections=previous; if !isRequestCancellation(error) { message=error.localizedDescription; store.report(error) } }
    }
}
