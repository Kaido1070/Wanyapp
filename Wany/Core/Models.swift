import Foundation

let website = URL(string: "https://wany.site")!
let sources = ["mangatime", "teamx", "3asq", "starzmanga", "xsano", "mangalik", "azora"]
func chapterNumber(_ n: Double) -> String { n.rounded() == n ? String(format: "%.0f", n) : String(n) }
func milliseconds() -> Double { Date().timeIntervalSince1970 * 1000 }
func byteLabel(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
func sourceLabel(_ source: String) -> String { ["teamx":"Team-X", "mangatime":"MangaTime", "3asq":"3asq", "starzmanga":"StarzManga", "xsano":"XSano", "mangalik":"MangaLik", "azora":"Azora"][source] ?? source }

struct Story: Codable, Hashable, Identifiable {
    var key: String
    var source: String
    var sourceId: String?
    var slug: String
    var type: String
    var url: String
    var title: String
    var cover: String
    var description: String?
    var status: String?
    var genres: [String]
    var latest: Double?
    var chapters: [Chapter]?
    var declaredChapterCount: Int?
    var chapterListComplete: Bool?
    var chapterPageCount: Int?
    var sourceTemporarilyUnavailable: Bool?
    var id: String { key }
    var orderedChapters: [Chapter] { (chapters ?? []).sorted { $0.number < $1.number } }
}
struct Chapter: Codable, Hashable, Identifiable {
    var number: Double
    var title: String
    var publishedAt: String?
    var synthetic: Bool?
    var url: String?
    var id: String { chapterNumber(number) }
}
struct ChapterPayload: Codable, Hashable {
    var item: Story
    var number: Double
    var title: String
    var chapterUrl: String?
    var pages: [String]
    var pageMeta: [PageMeta]?
    var previous: Double?
    var next: Double?
    var id: String { item.key + ":" + chapterNumber(number) }
}
struct PageMeta: Codable, Hashable { var url: String; var width: Double?; var height: Double? }
struct Account: Codable, Identifiable {
    var id: String
    var name: String
    var username: String
    var badgeType: String?
    var profileVisibility: String?
    var avatarId: String?
    var role: String?
}
struct LibraryEntry: Codable {
    var mangaId: String
    var status: String
    var addedAt: Double
    var updatedAt: Double
    var lastReadAt: Double?
    var lastReadChapter: Double?
    var highestReachedChapter: Double?
}
struct ProgressRecord: Codable, Equatable {
    var mangaId: String
    var chapter: Double
    var percent: Double
    var updatedAt: Double
    var id: String { mangaId + ":" + chapterNumber(chapter) }
}
struct LastOpened: Codable { var mangaId: String; var chapter: Double }
struct AccountData: Codable {
    var version = 3
    var favorites: [String] = []
    var library: [LibraryEntry] = []
    var progress: [String: ProgressRecord] = [:]
    var completed: [String] = []
    var lastOpened: LastOpened?
}
struct AccountState: Codable {
    var user: Account
    var data = AccountData()
    var pending: [String: ProgressRecord] = [:]
    var completedPending: [String:ProgressRecord]?
    var positions: [String: Int] = [:]
    var stats: [String: JSONValue] = [:]
    var profile: JSONValue?
    var fyp: [Recommendation] = []
    var newFeed: NewFeed?
    var lastSynced: Date?
}
struct Recommendation: Codable, Identifiable {
    var item: Story
    var sourceKeys: [String]
    var reason: String
    var id: String { item.key }
}
struct FeedChapter: Codable, Identifiable {
    var identity: String; var number: Double; var title: String
    var releaseAt: Double; var read: Bool; var sourceKey: String; var sourceLabel: String
    var id: String { sourceKey + ":" + identity }
}
struct FeedGroup: Codable, Identifiable {
    var id: String; var item: Story; var sourceKeys: [String]; var chapters: [FeedChapter]
}
struct NewFeed: Codable { var followed: [FeedGroup]; var all: [FeedGroup]; var hasMore: Bool; var page: Int }
struct FypSnapshot: Codable { var recommendations: [Recommendation] }
struct APIList: Codable { var items: [Story]; var hasMore: Bool; var page: Int }
struct ResolveResponse: Codable { var items: [Story] }
struct SeriesResponse: Codable { var item: Story }
struct ChapterResponse: Codable { var chapter: ChapterPayload }
struct ChaptersResponse: Codable { var chapters: [Chapter]; var page: Int; var pages: Int }
struct SessionResponse: Codable { var user: Account? }
struct DataResponse: Codable { var data: AccountData }
struct OK: Codable { var ok: Bool? }

// Flexible server-owned profile, lists and statistics fields; never synthesize badges.
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    subscript(_ key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    var string: String { if case .string(let s) = self { return s }; return "" }
    var number: Double { if case .number(let n) = self { return n }; return 0 }
    var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSONValue] { if case .object(let a) = self { return a }; return [:] }
}

struct ImageRecord: Codable, Identifiable {
    var remote: String
    var file: String
    var expected: Int64?
    var bytes: Int64 = 0
    var done = false
    var failure: String?
    var attempts = 0
    var id: String { file }
}
struct ChapterDownload: Codable, Identifiable {
    var chapter: Chapter
    var payload: ChapterPayload?
    var images: [ImageRecord] = []
    var error: String?
    var id: String { chapter.id }
    var complete: Bool { payload != nil && !images.isEmpty && images.allSatisfy(\.done) }
}
struct DownloadJob: Codable, Identifiable {
    var id: String
    var story: Story
    var chapters: [ChapterDownload]
    var wholeStory: Bool
    var chapterListComplete: Bool
    var paused = false
    var createdAt = Date()
    var error: String?
    var completedChapters: Int { chapters.filter(\.complete).count }
    var remainingChapters: Int { chapters.count - completedChapters }
    var bytes: Int64 { chapters.flatMap(\.images).reduce(0) { $0 + $1.bytes } }
    var total: Int64? {
        let images = chapters.flatMap(\.images)
        guard chapterListComplete, chapters.allSatisfy({ $0.payload != nil }), !images.isEmpty,
              images.allSatisfy({ $0.done || $0.expected != nil }) else { return nil }
        return images.reduce(0) { $0 + ($1.done ? $1.bytes : ($1.expected ?? 0)) }
    }
    var complete: Bool { chapterListComplete && !chapters.isEmpty && chapters.allSatisfy(\.complete) }
}
struct TransferTag: Codable { var owner: String; var job: String; var chapter: String; var image: String }

// The local reading ledger retains both an offline completion and a newer reread.
// Merge uses event timestamps; page indices from an older device position are discarded.
extension AccountState {
    mutating func mergeReadingData(_ remote: AccountData) {
        let previouslyCompleted = Set(data.completed)
        for (key, progress) in remote.progress {
            if progress.updatedAt > (data.progress[key]?.updatedAt ?? 0),
               progress.updatedAt > (pending[key]?.updatedAt ?? 0) { positions.removeValue(forKey:key) }
        }
        data = remote
        for record in pending.values {
            let server = data.progress[record.id]
            guard server == nil || record.updatedAt >= server!.updatedAt else { continue }
            data.progress[record.id] = record
            if (record.percent >= 98 || previouslyCompleted.contains(record.id)) && !data.completed.contains(record.id) { data.completed.append(record.id) }
            if let i = data.library.firstIndex(where: { $0.mangaId == record.mangaId }) {
                if record.updatedAt >= (data.library[i].lastReadAt ?? 0) {
                    data.library[i].lastReadAt = record.updatedAt; data.library[i].lastReadChapter = record.chapter
                }
                data.library[i].highestReachedChapter = max(data.library[i].highestReachedChapter ?? 0,record.chapter)
            } else {
                data.library.append(LibraryEntry(mangaId:record.mangaId,status:"reading",addedAt:record.updatedAt,updatedAt:record.updatedAt,lastReadAt:record.updatedAt,lastReadChapter:record.chapter,highestReachedChapter:record.chapter))
            }
        }
        for record in completedPending?.values.map({ $0 }) ?? [] {
            if !data.completed.contains(record.id) { data.completed.append(record.id) }
        }
        if let latest = pending.values.max(by: { $0.updatedAt < $1.updatedAt }), latest.updatedAt >= (remote.library.compactMap(\.lastReadAt).max() ?? 0) {
            data.lastOpened = LastOpened(mangaId:latest.mangaId,chapter:latest.chapter)
        }
    }
}
