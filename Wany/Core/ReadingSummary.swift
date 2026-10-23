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
        let entry = data.library.first { $0.mangaId == story.key }
        // Same rule as the website: continue from the last chapter actually opened
        // (lastReadChapter, updated by every open on any device), then the highest
        // reached. Progress timestamps are not used: marking earlier chapters read
        // stamps them "now", which used to send this button to an old chapter.
        // Local reading not yet synced is real reading too (bulk marking never
        // creates pending records), so a newer one still wins.
        let localReading = pending.values.filter { $0.mangaId == story.key }.max { ($0.updatedAt,$0.chapter) < ($1.updatedAt,$1.chapter) }
        let chapter: Double?
        if let local = localReading, local.updatedAt > (entry?.lastReadAt ?? 0) { chapter = local.chapter }
        else if let saved = entry?.lastReadChapter, saved > 0 { chapter = saved }
        else if let highest = entry?.highestReachedChapter, highest > 0 { chapter = highest }
        else { chapter = records.values.max { ($0.updatedAt,$0.chapter) < ($1.updatedAt,$1.chapter) }?.chapter }
        let chapters = story.orderedChapters
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
