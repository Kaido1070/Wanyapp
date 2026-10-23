import Foundation

struct ReadingOpenEvent: Codable, Equatable {
    let mangaId: String
    let chapter: Double
    let openedAt: Double
    var id: String { mangaId+":"+chapterNumber(chapter) }
}
struct WorkSnapshotWrite: Codable, Equatable {
    let mangaId: String
    let title: String
    let source: String
    let sourceUrl: String
    let coverUrl: String
    let chapter: Double?
    init(story: Story,chapter: Double?) {
        mangaId=story.key; title=story.title; source=story.source; sourceUrl=story.url
        coverUrl=story.snapshotOriginalCover ?? (story.cover.hasPrefix("/api/work-snapshots/") ? "" : story.cover)
        self.chapter=chapter
    }
}
struct ReadingBulkInput: Encodable { let mangaId: String; let chapters: [Double] }
func sourceFromStoryKey(_ key: String) -> String {
    ["mt":"mangatime","tx":"teamx","aq":"3asq","sz":"starzmanga","xs":"xsano","ml":"mangalik","az":"azora"][String(key.split(separator:":").first ?? "")] ?? ""
}

extension AccountState {
    mutating func discardPendingReading(mangaId: String,chapters: Set<Double>? = nil) {
        func matches(_ id: String) -> Bool {
            guard let split=id.lastIndex(of:":"),String(id[..<split]) == mangaId else { return false }
            guard let chapters else { return true }
            return Double(id[id.index(after:split)...]).map { chapters.contains($0) } ?? false
        }
        pending=pending.filter { !matches($0.key) }
        completedPending=completedPending?.filter { !matches($0.key) }
        positions=positions.filter { !matches($0.key) }
        pendingOpens=pendingOpens?.filter { !matches($0.key) }
        if chapters == nil { pendingSnapshots?.removeValue(forKey:mangaId) }
    }
}
