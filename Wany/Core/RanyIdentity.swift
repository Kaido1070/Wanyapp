import Foundation

// Keep the persisted bundle ID, account folders and server endpoints stable during rebranding.
enum RanyIdentity {
    static let name = "Rany"
    static let phrase = "READ ANYTIME"
    static let abbreviation = "RANY"
    static let displayName = "𝓡𝓐𝓝𝓨"
    static let displayPhrase = "𝓡𝓔𝓐𝓓 𝓐𝓝𝓨𝓣𝓘𝓜𝓔"
    static let displayMark = "𝓡"
    static let displayLetters = Array(displayPhrase)
    static let fontName = "RanyScript"
    static let maxBackdropCovers = 14
    static let maxBackdropCandidates = 48
    // R from READ and ANY from ANYTIME are the same four elements throughout the intro.
    static let retainedIndices = [0, 5, 6, 7]
    static let letters = Array(phrase)
    static func latinRun(_ character: Character) -> Bool { character.unicodeScalars.allSatisfy { $0.value < 128 } }
}

struct RanyBackdropCandidate: Hashable, Codable, Sendable {
    let key: String
    let cover: String
}

enum RanyBackdropPlan {
    static func candidates(data: AccountData, stories: [String:Story]) -> [RanyBackdropCandidate] {
        let reading = data.library.filter { $0.status == "reading" }.sorted {
            let a = $0.lastReadAt ?? $0.updatedAt, b = $1.lastReadAt ?? $1.updatedAt
            return a == b ? $0.mangaId < $1.mangaId : a > b
        }.map(\.mangaId)
        // Favorites are followed works too; completed/dropped library entries never displace current reading.
        let keys = reading + data.favorites.sorted()
        var seen = Set<String>(), seenTitles = Set<String>()
        return keys.compactMap { key -> RanyBackdropCandidate? in
            guard seen.insert(key).inserted, let story = stories[key], !story.cover.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
            let title = story.title.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
            guard title.isEmpty || seenTitles.insert(title).inserted else { return nil }
            return RanyBackdropCandidate(key:key,cover:story.cover)
        }.prefix(RanyIdentity.maxBackdropCandidates).map { $0 }
    }
}
