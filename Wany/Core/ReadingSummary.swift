import Foundation

struct StoryReadingSummary {
    var chapter: Double?
    var percent: Double?
    var completedCount: Int
}

extension AccountState {
    func readingSummary(for story: Story) -> StoryReadingSummary {
        let prefix = story.key + ":"
        var records = data.progress.filter { $0.value.mangaId == story.key }
        for record in pending.values where record.mangaId == story.key {
            if record.updatedAt >= (records[record.id]?.updatedAt ?? 0) { records[record.id] = record }
        }
        var completed = Set(data.completed.filter { $0.hasPrefix(prefix) })
        for record in completedPending?.values.map({ $0 }) ?? [] where record.mangaId == story.key { completed.insert(record.id) }
        for record in records.values where record.percent >= 98 { completed.insert(record.id) }
        let latestRecord = records.values.max { $0.updatedAt < $1.updatedAt }
        let entry = data.library.first { $0.mangaId == story.key }
        let chapter: Double?
        if let saved = entry?.lastReadChapter, (entry?.lastReadAt ?? 0) >= (latestRecord?.updatedAt ?? 0) { chapter = saved }
        else { chapter = latestRecord?.chapter ?? entry?.lastReadChapter }
        let chapters = story.orderedChapters.filter { $0.synthetic != true }
        let total: Int?
        let keys: Set<String>?
        if story.chapterListComplete == true, !chapters.isEmpty {
            let ids = Set(chapters.map { prefix + $0.id })
            total = ids.count; keys = ids
        } else if let declared = story.declaredChapterCount, declared > 0 { total = declared; keys = nil }
        else { total = nil; keys = nil }
        let counted = keys.map { completed.intersection($0) } ?? completed
        let partial = records.values.filter { !completed.contains($0.id) && (keys?.contains($0.id) ?? true) }
            .reduce(0.0) { $0 + min(100,max(0,$1.percent)) / 100 }
        let percent = total.map { min(100,max(0,(Double(counted.count) + partial) / Double($0) * 100)) }
        return StoryReadingSummary(chapter:chapter,percent:percent,completedCount:counted.count)
    }
}

func isRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let error = error as NSError
    return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
}
