import Foundation

struct RanyList: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var iconKey: String
    var itemCount: Int
    var position: Double
    var canManage: Bool?
}
struct RanyProfileSection: Codable, Identifiable {
    var key: String
    var sectionType: String
    var referenceId: String?
    var position: Double
    var isVisible: Bool
    var list: RanyList?
    var id: String { key }
    var managed: Bool { sectionType == "favorites" || sectionType == "custom_list" }
    var title: String { sectionType == "favorites" ? "المفضلة" : (list?.name ?? "قائمة") }
    var payload: ProfileSectionInput { ProfileSectionInput(sectionType:sectionType,referenceId:referenceId,isVisible:isVisible) }
}
struct ProfileSectionInput: Encodable { let sectionType: String; let referenceId: String?; let isVisible: Bool }
struct SectionsResponse: Decodable { let sections: [RanyProfileSection] }
struct ListResponse: Decodable { let list: RanyList }
struct ListEditorInput: Encodable { var name: String; var description: String; var iconKey: String
    var valid: Bool { (1...80).contains(name.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count) && description.utf16.count <= 500 && ListIcons.keys.contains(iconKey) }
}
enum ListIcons {
    static let keys=["lists","book","star","heart","flame","sword","crown","ghost","moon","bolt","mask","dragon","spark"]
    static func symbol(_ key: String) -> String {
        ["lists":"list.bullet.rectangle","book":"book.closed","star":"star","heart":"heart","flame":"flame","sword":"bolt.shield","crown":"crown","ghost":"eyes","moon":"moon","bolt":"bolt","mask":"theatermasks","dragon":"lizard","spark":"sparkles"][key] ?? "list.bullet.rectangle"
    }
}
enum SectionOrder {
    static func replacingManaged(_ all: [RanyProfileSection],with managed: [RanyProfileSection]) -> [RanyProfileSection] {
        var iterator=managed.makeIterator()
        return all.map { $0.managed ? (iterator.next() ?? $0) : $0 }
    }
    static func moving<T>(_ items: [T],from: Int,to: Int) -> [T] {
        guard items.indices.contains(from),items.indices.contains(to),from != to else { return items }
        var copy=items; let value=copy.remove(at:from); copy.insert(value,at:to); return copy
    }
}
extension Notification.Name {
    static let ranyCollectionsChanged=Notification.Name("rany.collections.changed")
    static let ranyRelationshipsChanged=Notification.Name("rany.relationships.changed")
}
