import Foundation

let website = URL(string: "https://rany.lat")!
// Hosts the service answered on before; saved absolute URLs from them are
// rewritten to the current origin instead of following a redirect.
let legacyWebsiteHosts: Set<String> = ["wany.site","www.wany.site"]
let sources = ["mangatime", "teamx", "3asq", "starzmanga", "xsano", "mangalik", "azora"]
func chapterNumber(_ n: Double) -> String { n.rounded() == n ? String(format: "%.0f", n) : String(n) }
// Sources often repeat the number inside the title ("الفصل 355.2 355.2"). Show the
// number once and keep any real chapter name after it.
func chapterDisplayTitle(_ title: String, number: Double) -> String {
    let id = chapterNumber(number)
    let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
    let rest = title.split(whereSeparator:\.isWhitespace).map { $0.trimmingCharacters(in:trim) }
        .filter { !$0.isEmpty && !["الفصل","فصل","رقم","Chapter","chapter","Ch","ch",id].contains($0) }
        .joined(separator:" ")
    return rest.isEmpty ? "الفصل \(id)" : "الفصل \(id) · \(rest)"
}
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
    var snapshotOriginalCover: String?
    enum CodingKeys: String, CodingKey {
        case key, source, sourceId, slug, type, url, title, cover, description, status, genres, latest, chapters
        case declaredChapterCount, chapterListComplete, chapterPageCount, sourceTemporarilyUnavailable, snapshotOriginalCover
    }
    var id: String { key }
    var orderedChapters: [Chapter] { (chapters ?? []).sorted { $0.number < $1.number } }
}
struct Chapter: Codable, Hashable, Identifiable {
    var number: Double
    var title: String
    var publishedAt: String?
    var synthetic: Bool?
    var url: String?
    enum CodingKeys: String, CodingKey { case number, title, publishedAt, synthetic, url }
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
    enum CodingKeys: String, CodingKey { case item, number, title, chapterUrl, pages, pageMeta, previous, next }
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
extension JSONValue {
    var publicAccount: Account? {
        guard !self["id"].string.isEmpty else { return nil }
        let avatar = self["avatarId"].string
        let badge = self["badgeType"].string
        return Account(id:self["id"].string,name:self["name"].string,username:self["username"].string,badgeType:badge.isEmpty ? nil : badge,avatarId:avatar.isEmpty ? nil : avatar)
    }
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
    var pendingOpens: [String:ReadingOpenEvent]?
    var pendingSnapshots: [String:WorkSnapshotWrite]?
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
struct APIList: Codable {
    var items: [Story]; var hasMore: Bool; var page: Int
    enum CodingKeys: String, CodingKey { case items, hasMore, page }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        items=c.lossyStories(.items)
        hasMore=(try? c.decodeIfPresent(Bool.self,forKey:.hasMore)) ?? false
        page=Int(c.lenientNumber(.page) ?? 1)
    }
}
struct ResolveResponse: Codable {
    var items: [Story]
    enum CodingKeys: String, CodingKey { case items }
    init(from decoder: Decoder) throws { items=try decoder.container(keyedBy:CodingKeys.self).lossyStories(.items) }
}
struct SeriesResponse: Codable { var item: Story }
struct ChapterResponse: Codable { var chapter: ChapterPayload }
struct ChaptersResponse: Codable {
    var chapters: [Chapter]; var page: Int; var pages: Int
    enum CodingKeys: String, CodingKey { case chapters, page, pages }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        chapters=c.lossyChapters(.chapters)
        page=Int(c.lenientNumber(.page) ?? 1); pages=Int(c.lenientNumber(.pages) ?? 1)
    }
}
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
    var boolean: Bool { if case .bool(let value) = self { return value }; return false }
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
    var edgeOptimized: Bool?
    var quality: String?
    var fallbackFile: String?
    var fallbackBytes: Int64?
    var storedFiles: [String] { [file] + (fallbackFile.map { [$0] } ?? []) }
    var storageBytes: Int64 { bytes + (fallbackBytes ?? 0) }
    var attempts = 0
    var id: String { file }
}
struct ChapterDownload: Codable, Identifiable {
    var chapter: Chapter
    var payload: ChapterPayload?
    var images: [ImageRecord] = []
    var error: String?
    var keepOffline: Bool?
    var expiresAt: Date?
    var requestedQuality: String?
    // Set when pages were fetched in the lighter quality to appear quickly; the
    // chapter is re-fetched in this quality once every page is visible.
    var upgradeQuality: String?
    var saved: Bool { keepOffline != false }
    var id: String { chapter.id }
    var complete: Bool { payload != nil && !images.isEmpty && images.allSatisfy(\.done) }
}
struct DownloadJob: Codable, Identifiable {
    var id: String
    var story: Story
    var chapters: [ChapterDownload]
    var wholeStory: Bool
    var chapterListComplete: Bool
    var activeChapterIDs: [String]?
    var selectionMode: String?
    var paused = false
    var createdAt = Date()
    var error: String?
    var requestedChapters: [ChapterDownload] {
        guard let activeChapterIDs else { return chapters.filter(\.saved) }
        let targets = Set(activeChapterIDs)
        return chapters.filter { $0.saved && targets.contains($0.id) }
    }
    func includes(_ chapterID: String) -> Bool { activeChapterIDs?.contains(chapterID) ?? true }
    var completedChapters: Int { requestedChapters.filter(\.complete).count }
    var remainingChapters: Int { requestedChapters.count - completedChapters }
    var downloadedBytes: Int64 { requestedChapters.flatMap(\.images).reduce(0) { $0 + $1.bytes } }
    var bytes: Int64 { chapters.filter(\.saved).flatMap(\.images).reduce(0) { $0 + $1.storageBytes } }
    var total: Int64? {
        let images = requestedChapters.flatMap(\.images)
        guard chapterListComplete, requestedChapters.allSatisfy({ $0.payload != nil }), !images.isEmpty,
              images.allSatisfy({ $0.done || $0.expected != nil }) else { return nil }
        return images.reduce(0) { $0 + ($1.done ? $1.bytes : ($1.expected ?? 0)) }
    }
    var complete: Bool { chapterListComplete && !requestedChapters.isEmpty && requestedChapters.allSatisfy(\.complete) }
}
struct TransferTag: Codable { var owner: String; var job: String; var chapter: String; var image: String; var quality: String? }

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
        for event in (pendingOpens?.values.map { $0 } ?? []).sorted(by:{$0.openedAt < $1.openedAt}) {
            if let index=data.library.firstIndex(where:{$0.mangaId == event.mangaId}) {
                if event.openedAt >= (data.library[index].lastReadAt ?? 0) { data.library[index].lastReadAt=event.openedAt; data.library[index].lastReadChapter=event.chapter }
                data.library[index].highestReachedChapter=max(data.library[index].highestReachedChapter ?? 0,event.chapter)
            } else { data.library.append(LibraryEntry(mangaId:event.mangaId,status:"reading",addedAt:event.openedAt,updatedAt:event.openedAt,lastReadAt:event.openedAt,lastReadChapter:event.chapter,highestReachedChapter:event.chapter)) }
            if event.openedAt >= (remote.library.compactMap(\.lastReadAt).max() ?? 0) { data.lastOpened=LastOpened(mangaId:event.mangaId,chapter:event.chapter) }
        }
        if let latest = pending.values.max(by: { $0.updatedAt < $1.updatedAt }), latest.updatedAt >= (remote.library.compactMap(\.lastReadAt).max() ?? 0) {
            data.lastOpened = LastOpened(mangaId:latest.mangaId,chapter:latest.chapter)
        }
    }
}

extension AccountState {
    func unreadChapters(in story: Story) -> [Chapter] {
        let completed = Set(data.completed)
        return story.orderedChapters.filter { chapter in
            let key = story.key+":"+chapter.id
            return !completed.contains(key)
                && (data.progress[key]?.percent ?? 0) < 98
                && completedPending?[key] == nil
                && (pending[key]?.percent ?? 0) < 98
        }
    }
}

func storyStatusLabel(_ value: String) -> String {
    switch value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() {
    case "ongoing", "on-going", "publishing": return "مستمر"
    case "completed", "complete", "finished": return "مكتمل"
    case "hiatus": return "متوقف مؤقتًا"
    case "cancelled", "canceled": return "ملغى"
    default: return value
    }
}

// Stable list identity from a server field; duplicates or missing ids fall back to position.
struct IdentifiedJSON: Identifiable { let id: String; let value: JSONValue }
extension Array where Element == JSONValue {
    func identified(by key: (JSONValue) -> String) -> [IdentifiedJSON] {
        var seen = Set<String>()
        return enumerated().map { index,value in
            let id = key(value)
            return IdentifiedJSON(id:!id.isEmpty && seen.insert(id).inserted ? id : "#position-\(index)",value:value)
        }
    }
}

// Sources disagree on types: chapter numbers arrive as numbers or text, titles
// and dates may be null. The website coerces each field (Number(...)) and skips
// only the entries it cannot read; one odd chapter must never hide the rest.
extension Story {
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        key=try c.decode(String.self,forKey:.key)
        source=c.lenientString(.source) ?? ""
        sourceId=c.lenientString(.sourceId)
        slug=c.lenientString(.slug) ?? ""
        type=c.lenientString(.type) ?? ""
        url=c.lenientString(.url) ?? ""
        title=c.lenientString(.title) ?? key
        cover=c.lenientString(.cover) ?? ""
        description=c.lenientString(.description)
        status=c.lenientString(.status)
        genres=((try? c.decodeIfPresent([JSONValue].self,forKey:.genres)) ?? nil)?.compactMap { $0.string.isEmpty ? nil : $0.string } ?? []
        latest=c.lenientNumber(.latest)
        chapters=c.contains(.chapters) ? c.lossyChapters(.chapters) : nil
        declaredChapterCount=c.lenientNumber(.declaredChapterCount).map { Int($0) }
        chapterListComplete=try? c.decodeIfPresent(Bool.self,forKey:.chapterListComplete)
        chapterPageCount=c.lenientNumber(.chapterPageCount).map { Int($0) }
        sourceTemporarilyUnavailable=try? c.decodeIfPresent(Bool.self,forKey:.sourceTemporarilyUnavailable)
        snapshotOriginalCover=c.lenientString(.snapshotOriginalCover)
    }
}
extension Chapter {
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard let value=c.lenientNumber(.number),value.isFinite else {
            throw DecodingError.dataCorruptedError(forKey:.number,in:c,debugDescription:"Chapter without a usable number")
        }
        number=value
        title=c.lenientString(.title) ?? ""
        if title.isEmpty { title="الفصل "+chapterNumber(value) }
        publishedAt=c.lenientString(.publishedAt)
        synthetic=try? c.decodeIfPresent(Bool.self,forKey:.synthetic)
        url=c.lenientString(.url).flatMap { $0.isEmpty ? nil : $0 }
    }
}
extension ChapterPayload {
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        item=try c.decode(Story.self,forKey:.item)
        guard let value=c.lenientNumber(.number) else { throw DecodingError.dataCorruptedError(forKey:.number,in:c,debugDescription:"Chapter without a usable number") }
        number=value
        title=c.lenientString(.title) ?? ("الفصل "+chapterNumber(value))
        chapterUrl=c.lenientString(.chapterUrl)
        pages=((try? c.decodeIfPresent([JSONValue].self,forKey:.pages)) ?? nil)?.compactMap { $0.string.isEmpty ? nil : $0.string } ?? []
        pageMeta=try? c.decodeIfPresent([PageMeta].self,forKey:.pageMeta)
        previous=c.lenientNumber(.previous)
        next=c.lenientNumber(.next)
    }
}
private struct LossyStory: Decodable {
    let value: Story?
    init(from decoder: Decoder) throws { value=try? Story(from:decoder) }
}
private struct LossyChapter: Decodable {
    let value: Chapter?
    init(from decoder: Decoder) throws { value=try? Chapter(from:decoder) }
}
extension KeyedDecodingContainer {
    func lenientNumber(_ key: Key) -> Double? {
        if let value=try? decodeIfPresent(Double.self,forKey:key) { return value }
        guard let text=(try? decodeIfPresent(String.self,forKey:key)) ?? nil else { return nil }
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".")
        if let value=Double(trimmed) { return value }
        // "Chapter 12.5" / "الفصل ١٢": take the first number, including Arabic-Indic digits.
        let western=String(trimmed.map { ch -> Character in
            if let digit=ch.wholeNumberValue,!ch.isASCII { return Character(String(digit)) }
            return ch == "٫" ? "." : ch
        })
        guard let range=western.range(of:#"\d+(\.\d+)?"#,options:.regularExpression) else { return nil }
        return Double(western[range])
    }
    func lenientString(_ key: Key) -> String? {
        if let text=try? decodeIfPresent(String.self,forKey:key) { return text }
        if let number=try? decodeIfPresent(Double.self,forKey:key) { return chapterNumber(number) }
        return nil
    }
    func lossyStories(_ key: Key) -> [Story] {
        ((try? decodeIfPresent([LossyStory].self,forKey:key)) ?? nil)?.compactMap(\.value) ?? []
    }
    func lossyChapters(_ key: Key) -> [Chapter] {
        ((try? decodeIfPresent([LossyChapter].self,forKey:key)) ?? nil)?.compactMap(\.value) ?? []
    }
}

enum SeriesChapters {
    // Two entries for one number: keep the one the reader can open by URL, and
    // a real chapter over a number-only placeholder.
    static func prefer(_ a: Chapter,_ b: Chapter) -> Chapter {
        if (a.synthetic == true) != (b.synthetic == true) { return a.synthetic == true ? b : a }
        if a.url == nil && b.url != nil { return b }
        return a
    }
}
