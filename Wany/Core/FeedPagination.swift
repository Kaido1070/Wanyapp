import Foundation

extension NewFeed {
    func appending(_ incoming: NewFeed) -> NewFeed {
        guard incoming.page>page else { return self }
        return NewFeed(followed:Self.merge(followed,incoming.followed),all:Self.merge(all,incoming.all),hasMore:incoming.hasMore,page:incoming.page)
    }
    private static func merge(_ existing: [FeedGroup],_ incoming: [FeedGroup]) -> [FeedGroup] {
        var result=existing
        for candidate in incoming {
            let candidateKeys=Set(candidate.sourceKeys+[candidate.item.key])
            let matches=result.indices.filter { result[$0].id == candidate.id || !candidateKeys.isDisjoint(with:Set(result[$0].sourceKeys+[result[$0].item.key])) }
            guard let first=matches.first else { result.append(candidate); continue }
            var group=result[first]
            for other in matches.dropFirst().map({ result[$0] }) + [candidate] {
                var sources=Set(group.sourceKeys)
                group.sourceKeys += other.sourceKeys.filter { sources.insert($0).inserted }
                var seen=Set(group.chapters.map(\.id))
                group.chapters += other.chapters.filter { seen.insert($0.id).inserted }
                // Keep both legitimate same-day source editions, as the website does.
            }
            result[first]=group
            for index in matches.dropFirst().reversed() { result.remove(at:index) }
        }
        return result
    }
}
struct ActivityItem: Identifiable {
    let value: JSONValue
    var id: String { value["id"].string.isEmpty ? String(value["id"].number) : value["id"].string }
}
enum ActivityPagination {
    static func append(_ incoming: [ActivityItem],to existing: [ActivityItem]) -> [ActivityItem] {
        var seen=Set(existing.map(\.id)); return existing+incoming.filter { seen.insert($0.id).inserted }
    }
}
