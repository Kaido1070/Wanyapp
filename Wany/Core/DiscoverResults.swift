import Foundation

enum DiscoverResults {
    static func append(_ incoming: [Story], to existing: [Story]) -> [Story] {
        var keys = Set(existing.map(\.key))
        return existing + incoming.filter { keys.insert($0.key).inserted }
    }
    static func combine(_ results: [String:[Story]], order: [String]) -> [Story] {
        var merged: [Story] = []
        var keys: Set<String> = []
        let count = order.map { results[$0]?.count ?? 0 }.max() ?? 0
        for index in 0..<count {
            for source in order {
                guard let items = results[source], items.indices.contains(index), keys.insert(items[index].key).inserted else { continue }
                merged.append(items[index])
            }
        }
        return merged
    }
}
