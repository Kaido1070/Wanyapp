import Foundation

struct RanyList: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var iconKey: String
    var itemCount: Int
    var position: Double
    var canManage: Bool?
    enum CodingKeys: String, CodingKey { case id, name, description, iconKey, itemCount, position, canManage }
}
struct RanyProfileSection: Codable, Identifiable {
    var key: String
    var sectionType: String
    var referenceId: String?
    var position: Double
    var isVisible: Bool
    var list: RanyList?
    enum CodingKeys: String, CodingKey { case key, sectionType, referenceId, position, isVisible, list }
    var id: String { key }
    var managed: Bool { sectionType == "favorites" || sectionType == "custom_list" }
    var title: String { sectionType == "favorites" ? "المفضلة" : (list?.name ?? "قائمة") }
    var payload: ProfileSectionInput { ProfileSectionInput(sectionType:sectionType,referenceId:referenceId,isVisible:isVisible) }
}
// The server may send null icons, numeric positions as strings, or omit counts
// (the website itself falls back for each). One such field used to fail the
// whole sections response with "The data couldn't be read because it is missing".
extension RanyList {
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=c.decodeLenientString(.id) ?? ""
        name=try c.decodeIfPresent(String.self,forKey:.name) ?? ""
        description=try? c.decodeIfPresent(String.self,forKey:.description)
        let icon=c.decodeLenientString(.iconKey) ?? ""
        iconKey=icon.isEmpty ? "lists" : icon
        itemCount=Int(c.decodeLenientNumber(.itemCount) ?? 0)
        position=c.decodeLenientNumber(.position) ?? 0
        canManage=try? c.decodeIfPresent(Bool.self,forKey:.canManage)
    }
}
extension RanyProfileSection {
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        sectionType=try c.decode(String.self,forKey:.sectionType)
        referenceId=c.decodeLenientString(.referenceId)
        key=c.decodeLenientString(.key) ?? (sectionType+":"+(referenceId ?? ""))
        position=c.decodeLenientNumber(.position) ?? 0
        isVisible=(try? c.decodeIfPresent(Bool.self,forKey:.isVisible)) ?? true
        list=try? c.decodeIfPresent(RanyList.self,forKey:.list)
    }
}
private extension KeyedDecodingContainer {
    func decodeLenientNumber(_ key: Key) -> Double? {
        if let value=try? decodeIfPresent(Double.self,forKey:key) { return value }
        if let text=try? decodeIfPresent(String.self,forKey:key) { return Double(text) }
        return nil
    }
    func decodeLenientString(_ key: Key) -> String? {
        if let text=try? decodeIfPresent(String.self,forKey:key) { return text }
        if let number=try? decodeIfPresent(Int.self,forKey:key) { return String(number) }
        return nil
    }
}
struct ProfileSectionInput: Encodable { let sectionType: String; let referenceId: String?; let isVisible: Bool }
struct SectionsResponse: Decodable {
    let sections: [RanyProfileSection]
    init(from decoder: Decoder) throws {
        enum Keys: String, CodingKey { case sections }
        sections=(try decoder.container(keyedBy:Keys.self).decodeIfPresent([RanyProfileSection].self,forKey:.sections)) ?? []
    }
}
struct ListResponse: Decodable { let list: RanyList }
struct ListsResponse: Decodable {
    let lists: [RanyList]
    init(from decoder: Decoder) throws {
        enum Keys: String, CodingKey { case lists }
        lists=(try decoder.container(keyedBy:Keys.self).decodeIfPresent([RanyList].self,forKey:.lists)) ?? []
    }
}
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
    // Sections carry only a reference; like the website, name/icon/count come
    // from the user's lists. A custom section whose list is gone is dropped.
    static func joining(_ sections: [RanyProfileSection],lists: [RanyList]?,dropMissing: Bool = true) -> [RanyProfileSection] {
        let byID=Dictionary((lists ?? []).map { ($0.id,$0) },uniquingKeysWith:{ a,_ in a })
        return sections.compactMap { section in
            guard section.sectionType == "custom_list" else { return section }
            guard let reference=section.referenceId,!reference.isEmpty else { return nil }
            var joined=section
            if let list=byID[reference] { joined.list=list } else if dropMissing && lists != nil && section.list == nil { return nil }
            return joined
        }.sorted { $0.position < $1.position }
    }
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
