import Foundation
import UIKit
import ImageIO
import Observation

final class TransferDelegate: NSObject, URLSessionDownloadDelegate {
    var progress: ((TransferTag, Int64, Int64, Int64) -> Void)?
    var finished: ((TransferTag, Int64, String?, Bool) -> Void)?
    var backgroundFinished: (() -> Void)?
    func tag(_ task: URLSessionTask) -> TransferTag? {
        guard let text = task.taskDescription, let data = text.data(using:.utf8) else { return nil }
        return try? JSONDecoder().decode(TransferTag.self,from:data)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let t = tag(downloadTask) { progress?(t,bytesWritten,totalBytesWritten,totalBytesExpectedToWrite) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let t = tag(downloadTask) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw APIError(message:"تعذر تحميل الصورة (\((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0))",status:0) }
            guard let source = CGImageSourceCreateWithURL(location as CFURL,nil), CGImageSourceGetCount(source) > 0,
                  CGImageSourceCreateImageAtIndex(source,0,nil) != nil else { throw APIError(message:"الصورة تالفة؛ أعد تحميل الناقص",status:0) }
            let ledger = Disk.read([DownloadJob].self,owner:t.owner,name:"downloads.json") ?? []
            guard ledger.contains(where: { $0.id == t.job && $0.chapters.contains(where: { $0.id == t.chapter && $0.images.contains(where: { $0.file == t.image }) }) }) else { finished?(t,0,nil,false); return }
            let destination = Disk.file(t.owner,t.image)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:destination.path) {
                _ = try FileManager.default.replaceItemAt(destination,withItemAt:location)
            } else { try FileManager.default.moveItem(at:location,to:destination) }
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:destination.path)
            let originalBytes = Int64((try destination.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0)
            let optimized = response.value(forHTTPHeaderField:"X-Wany-Image-Mode") == "edge"
            let bytes = optimized ? originalBytes : ((try? ImageStorage.compact(destination,quality:ImageQuality(rawValue:t.quality ?? "original") ?? .original)) ?? originalBytes)
            finished?(t,bytes,nil,optimized)
        } catch { finished?(t,0,error.localizedDescription,false) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let t = tag(task) { finished?(t,0,error.localizedDescription,false) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { backgroundFinished?() }
}

// Observation keeps transfer churn local: only screens that read jobs re-render,
// and byte progress is folded into jobs at most once per second.
@MainActor @Observable final class Downloads {
    static let shared = Downloads()
    private(set) var jobs: [DownloadJob] = []
    private(set) var speed: Int64 = 0
    private(set) var revision = 0
    var notice: String?
    var preparing: Set<String> = []
    var owner: String?
    var online = true
    var onWiFi = true
    var wifiOnly: Bool = UserDefaults.standard.bool(forKey:"wifiOnly") {
        didSet { UserDefaults.standard.set(wifiOnly,forKey:"wifiOnly"); updateNetwork() }
    }
    @ObservationIgnored private let delegate = TransferDelegate()
    @ObservationIgnored private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier:"site.wany.ios.downloads.v1")
        c.httpMaximumConnectionsPerHost = 3
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.timeoutIntervalForResource = 7 * 24 * 3600
        c.httpShouldSetCookies = false
        return URLSession(configuration:c,delegate:delegate,delegateQueue:nil)
    }()
    // Pages for the chapter being read use a foreground session with more parallel
    // connections: background sessions start each transfer later.
    @ObservationIgnored private lazy var readerSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 6
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration:c,delegate:delegate,delegateQueue:nil)
    }()
    @ObservationIgnored private var fastFallback: [String:Task<Void,Never>] = [:]
    @ObservationIgnored private var ledgerToken: UUID?
    @ObservationIgnored private var active: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var workers: [String: Task<Void,Never>] = [:]
    @ObservationIgnored private var workerTokens: [String:UUID] = [:]
    @ObservationIgnored private var speedSamples: [(Date,Int64,String)] = []
    @ObservationIgnored private var liveBytes: [String:(TransferTag,Int64,Int64)] = [:]
    @ObservationIgnored var readerPriority: String?
    var quality: ImageQuality = ImageQuality(rawValue:UserDefaults.standard.string(forKey:"imageQuality") ?? "balanced") ?? .balanced {
        didSet { UserDefaults.standard.set(quality.rawValue,forKey:"imageQuality") }
    }
    var savedJobs: [DownloadJob] {
        jobs.compactMap { job in
            var value = job; value.chapters = job.chapters.filter(\.saved)
            return value.chapters.isEmpty ? nil : value
        }
    }
    var temporaryBytes: Int64 { jobs.flatMap(\.chapters).filter { !$0.saved }.flatMap(\.images).reduce(0) { $0 + $1.storageBytes } }
    private(set) var compacting = false
    private(set) var compactProgress = ""
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var restored = false
    @ObservationIgnored var backgroundCompletion: (() -> Void)?
    private init() {
        delegate.progress = { tag,delta,total,expected in Task { @MainActor in self.didProgress(tag,delta:delta,total:total,expected:expected) } }
        delegate.finished = { tag,bytes,error,optimized in Task { @MainActor in self.didFinish(tag,bytes:bytes,error:error,optimized:optimized) } }
        delegate.backgroundFinished = { Task { @MainActor in self.backgroundCompletion?(); self.backgroundCompletion = nil } }
        Task { await restoreTasks() }
        Timer.scheduledTimer(withTimeInterval:30,repeats:true) { _ in Task { @MainActor in self.cleanTemporary() } }
        Timer.scheduledTimer(withTimeInterval:1,repeats:true) { _ in Task { @MainActor in self.updateSpeed() } }
    }
    private func restoreTasks() async {
        for task in await session.allTasks {
            if let d = task as? URLSessionDownloadTask, let tag = delegate.tag(task) {
                active[tag.owner + ":" + tag.image] = d
                if tag.owner != owner { d.suspend() }
            }
        }
        restored = true; updateNetwork()
    }
    func attach(_ userID: String?) {
        beginAttach(userID)
        finishAttach(userID,userID.map { Self.loadLedger($0) } ?? [])
    }
    // Launch path: the ledger is decoded and every page file is checked off the main
    // thread (a large library has thousands), so the first screen is not held up.
    func attachInBackground(_ userID: String) {
        beginAttach(userID)
        let token = UUID(); ledgerToken = token
        Task { [weak self] in
            let loaded = await Task.detached(priority:.userInitiated) { Self.loadLedger(userID) }.value
            guard let self, self.owner == userID, self.ledgerToken == token else { return }
            self.ledgerToken = nil
            // Keep any chapter opened while the ledger was loading.
            let opened = self.jobs.filter { job in !loaded.contains { $0.id == job.id } }
            self.finishAttach(userID,loaded+opened)
        }
    }
    private func beginAttach(_ userID: String?) {
        ledgerToken = nil
        workers.values.forEach { $0.cancel() }; workers.removeAll(); workerTokens.removeAll(); preparing.removeAll()
        // Logout suspends existing transfers. Their account-tagged files cannot enter another account.
        for (key, task) in active where !key.hasPrefix((userID ?? "<none>") + ":") { task.suspend() }
        readerPriority = nil
        owner = userID; speedSamples.removeAll(); liveBytes.removeAll(); speed = 0
        jobs = []
    }
    private func finishAttach(_ userID: String?, _ loaded: [DownloadJob]) {
        jobs = loaded
        for j in jobs.indices { for c in jobs[j].chapters.indices where !jobs[j].chapters[c].saved && jobs[j].chapters[c].expiresAt == nil {
            jobs[j].chapters[c].expiresAt = Date().addingTimeInterval(180)
        } }
        cleanTemporary(); persist(); resumePreparations(); pump()
    }
    nonisolated private static func loadLedger(_ userID: String) -> [DownloadJob] {
        var jobs = Disk.read([DownloadJob].self,owner:userID,name:"downloads.json") ?? []
        for j in jobs.indices { for c in jobs[j].chapters.indices { for i in jobs[j].chapters[c].images.indices {
            let page = jobs[j].chapters[c].images[i]
            if page.done && !FileManager.default.fileExists(atPath:Disk.file(userID,page.file).path) {
                jobs[j].chapters[c].images[i].done = false; jobs[j].chapters[c].images[i].bytes = 0
            }
        } } }
        return jobs
    }
    func persist() {
        // Never overwrite the saved ledger with a partial one while it is still loading.
        guard let owner, ledgerToken == nil else { return }
        do { try Disk.save(jobs,owner:owner,name:"downloads.json") } catch { notice = "تعذر حفظ قائمة التنزيل: " + error.localizedDescription }
        lastSaved = Date()
    }
    func enqueue(_ story: Story, chapters: [Chapter]? = nil, unreadOnly: Bool = false, quality chosen: ImageQuality? = nil) async {
        guard let owner else { return }
        let account = owner
        if preparing.contains(story.key) { return }
        preparing.insert(story.key)
        defer { preparing.remove(story.key) }
        do {
            let full: Story
            if chapters == nil { full = try await API.shared.fullSeries(story.key) } else { full = story }
            guard self.owner == account else { return }
            let selected = chapters ?? full.orderedChapters
            guard !selected.isEmpty else { throw APIError(message:"لا توجد فصول للتحميل",status:0) }
            if let index = jobs.firstIndex(where:{$0.id == story.key}) {
                let existing = Set(jobs[index].chapters.map(\.id))
                jobs[index].chapters += selected.filter { !existing.contains($0.id) }.map { ChapterDownload(chapter:$0) }
                for c in jobs[index].chapters.indices where selected.contains(where: { $0.id == jobs[index].chapters[c].id }) {
                    jobs[index].chapters[c].keepOffline = true; jobs[index].chapters[c].expiresAt = nil
                }
                jobs[index].chapters.sort { $0.chapter.number < $1.chapter.number }
                jobs[index].story = full; jobs[index].paused = false; jobs[index].error = nil
                if unreadOnly {
                    // Preserve cached chapters, but stop downloading read chapters from an older full-story queue.
                    jobs[index].activeChapterIDs = selected.map(\.id)
                    jobs[index].selectionMode = "unread"; jobs[index].wholeStory = false
                    workers[story.key]?.cancel(); workers[story.key] = nil; workerTokens[story.key] = nil
                    for task in active.values {
                        if let tag = delegate.tag(task), tag.owner == account, tag.job == story.key, !jobs[index].includes(tag.chapter) { task.cancel() }
                    }
                } else if chapters == nil {
                    jobs[index].activeChapterIDs = nil; jobs[index].selectionMode = nil; jobs[index].wholeStory = true
                } else if let targets = jobs[index].activeChapterIDs {
                    jobs[index].activeChapterIDs = Array(Set(targets + selected.map(\.id)))
                    jobs[index].selectionMode = "selected"
                }
                jobs[index].chapterListComplete = true
            } else {
                jobs.append(DownloadJob(id:story.key,story:full,chapters:selected.map { ChapterDownload(chapter:$0) },wholeStory:chapters == nil,chapterListComplete:true,activeChapterIDs:unreadOnly ? selected.map(\.id) : nil,selectionMode:unreadOnly ? "unread" : nil))
            }
            // The quality picked for this download applies to its not-yet-complete chapters.
            if let chosen, let index = jobs.firstIndex(where:{$0.id == story.key}) {
                let ids = Set(selected.map(\.id))
                for c in jobs[index].chapters.indices where ids.contains(jobs[index].chapters[c].id) && !jobs[index].chapters[c].complete {
                    jobs[index].chapters[c].requestedQuality = chosen.rawValue
                    for i in jobs[index].chapters[c].images.indices where !jobs[index].chapters[c].images[i].done { jobs[index].chapters[c].images[i].quality = chosen.rawValue }
                }
            }
            try Disk.save(full,owner:owner,name:"stories/"+Disk.hash(story.key)+".json")
            persist(); prepare(story.key); pump()
        } catch { notice = error.localizedDescription }
    }
    func usePayload(_ payload: ChapterPayload) {
        readerPriority = payload.id
        guard let owner else { return }
        do { try Disk.save(payload,owner:owner,name:Disk.chapterName(payload.id)) } catch { notice = error.localizedDescription; return }
        let chapter = Chapter(number:payload.number,title:payload.title,url:payload.chapterUrl)
        if !jobs.contains(where:{$0.id == payload.item.key}) {
            jobs.append(DownloadJob(id:payload.item.key,story:payload.item,chapters:[],wholeStory:false,chapterListComplete:true))
        }
        guard let j = jobs.firstIndex(where:{$0.id == payload.item.key}) else { return }
        if !jobs[j].chapters.contains(where:{$0.id == chapter.id}) { jobs[j].chapters.append(ChapterDownload(chapter:chapter,keepOffline:false)) }
        guard let c = jobs[j].chapters.firstIndex(where:{$0.id == chapter.id}) else { return }
        if !jobs[j].chapters[c].saved {
            jobs[j].chapters[c].expiresAt = nil
            for i in jobs[j].chapters[c].images.indices where !jobs[j].chapters[c].images[i].done { jobs[j].chapters[c].images[i].attempts = 0 }
        }
        if jobs[j].chapters[c].payload == nil { install(payload,job:j,chapter:c,owner:owner) }
        persist(); updateNetwork()
        if !jobs[j].chapters[c].saved && !jobs[j].chapters[c].complete { scheduleFastFallback(payload) }
    }
    // Show a chapter quickly: if the chosen quality has not delivered every page within
    // a short window, the missing pages switch to the lighter quality so the chapter
    // appears, then the whole chapter upgrades in the background (old pages stay visible).
    private func scheduleFastFallback(_ payload: ChapterPayload) {
        fastFallback[payload.id]?.cancel()
        fastFallback[payload.id] = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(2500)) } catch { return }
            self?.applyFastFallback(payload)
        }
    }
    private func applyFastFallback(_ payload: ChapterPayload) {
        fastFallback[payload.id] = nil
        guard let owner, readerPriority == payload.id, let j = jobs.firstIndex(where:{$0.id == payload.item.key}),
              let c = jobs[j].chapters.firstIndex(where:{$0.id == chapterNumber(payload.number)}),
              !jobs[j].chapters[c].saved, !jobs[j].chapters[c].complete else { return }
        let target = jobs[j].chapters[c].requestedQuality ?? quality.rawValue
        let light = ImageQuality.balanced.rawValue
        guard target != light else { return }
        var changed = false
        for i in jobs[j].chapters[c].images.indices where !jobs[j].chapters[c].images[i].done && jobs[j].chapters[c].images[i].quality != light {
            // A new file name keeps a late callback from the slower transfer out of this page.
            if let task = active.removeValue(forKey:owner+":"+jobs[j].chapters[c].images[i].file) { task.cancel() }
            jobs[j].chapters[c].images[i].file = Disk.imageName(payload.id,i)+".fast"
            jobs[j].chapters[c].images[i].quality = light
            jobs[j].chapters[c].images[i].attempts = 0; jobs[j].chapters[c].images[i].failure = nil
            jobs[j].chapters[c].images[i].bytes = 0; jobs[j].chapters[c].images[i].expected = nil
            changed = true
        }
        guard changed else { return }
        jobs[j].chapters[c].upgradeQuality = target
        persist(); revision += 1; pump()
    }
    private func install(_ payload: ChapterPayload, job: Int, chapter: Int, owner: String) {
        jobs[job].chapters[chapter].payload = payload; jobs[job].chapters[chapter].error = nil
        let requested=jobs[job].chapters[chapter].requestedQuality
        jobs[job].chapters[chapter].images = payload.pages.enumerated().map { index, remote in
            let file = Disk.imageName(payload.id,index)
            let url = Disk.file(owner,file)
            let size = ((try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            return ImageRecord(remote:remote,file:file,expected:size > 0 ? size : nil,bytes:size,done:size > 0,quality:requested)
        }
    }
    private func prepare(_ key: String) {
        guard workers[key] == nil, let owner, online, !wifiOnly || onWiFi else { return }
        let token = UUID(); workerTokens[key] = token
        workers[key] = Task { [weak self] in
            guard let self else { return }
            defer { if self.workerTokens[key] == token { self.workers[key] = nil; self.workerTokens[key] = nil } }
            while !Task.isCancelled, self.owner == owner, self.online {
                guard let j = self.jobs.firstIndex(where:{$0.id == key}), !self.jobs[j].paused,
                      let c = self.jobs[j].chapters.firstIndex(where:{$0.payload == nil && $0.error == nil && self.jobs[j].includes($0.id)}) else { break }
                let chapter = self.jobs[j].chapters[c].chapter
                do {
                    let payload: ChapterPayload
                    if let cached = Disk.read(ChapterPayload.self,owner:owner,name:Disk.chapterName(key+":"+chapter.id)) { payload = cached }
                    else { payload = try await API.shared.chapter(key,chapter) }
                    try Task.checkCancellation()
                    guard self.owner == owner, let jj = self.jobs.firstIndex(where:{$0.id == key}), let cc = self.jobs[jj].chapters.firstIndex(where:{$0.id == chapter.id}) else { break }
                    try Disk.save(payload,owner:owner,name:Disk.chapterName(payload.id))
                    self.install(payload,job:jj,chapter:cc,owner:owner); self.persist(); self.pump()
                } catch {
                    guard !Task.isCancelled, self.owner == owner, let jj = self.jobs.firstIndex(where:{$0.id == key}), let cc = self.jobs[jj].chapters.firstIndex(where:{$0.id == chapter.id}) else { break }
                    self.jobs[jj].chapters[cc].error = error.localizedDescription; self.persist()
                    // Network loss should wait for reconnection rather than failing every chapter.
                    if (error as? URLError) != nil { break }
                }
            }
        }
    }
    func resumePreparations() {
        for job in jobs where !job.paused && !job.complete { prepare(job.id) }
    }
    func updateNetwork() {
        for (_, task) in active {
            guard let t = delegate.tag(task), t.owner == owner else { continue }
            let job = jobs.first(where:{$0.id == t.job})
            let part = job?.chapters.first(where:{$0.id == t.chapter})
            let temporary = part?.saved == false
            let paused = temporary ? readerPriority != t.job+":"+t.chapter : job?.paused != false || job?.includes(t.chapter) != true
            if paused || (!temporary && wifiOnly && !onWiFi) { task.suspend() } else { task.resume() }
        }
        if online { for j in jobs.indices { for c in jobs[j].chapters.indices where jobs[j].chapters[c].payload == nil { jobs[j].chapters[c].error = nil } }; resumePreparations(); pump() }
    }
    func pause(_ key: String) {
        guard let j = jobs.firstIndex(where:{$0.id == key}) else { return }
        jobs[j].paused = true; workers[key]?.cancel(); workers[key] = nil; workerTokens[key] = nil
        for task in active.values where delegate.tag(task)?.job == key && delegate.tag(task)?.owner == owner { task.suspend() }
        persist(); pump()
    }
    func retry(_ key: String) {
        guard let j = jobs.firstIndex(where:{$0.id == key}) else { return }
        jobs[j].paused = false; jobs[j].error = nil
        for c in jobs[j].chapters.indices {
            jobs[j].chapters[c].error = nil
            for i in jobs[j].chapters[c].images.indices where !jobs[j].chapters[c].images[i].done {
                jobs[j].chapters[c].images[i].failure = nil; jobs[j].chapters[c].images[i].attempts = 0
            }
        }
        persist(); updateNetwork()
    }
    func retryChapter(_ payload: ChapterPayload) {
        usePayload(payload)
        guard let j = jobs.firstIndex(where:{$0.id == payload.item.key}), let c = jobs[j].chapters.firstIndex(where:{$0.id == chapterNumber(payload.number)}) else { return }
        for i in jobs[j].chapters[c].images.indices where !jobs[j].chapters[c].images[i].done { jobs[j].chapters[c].images[i].attempts = 0; jobs[j].chapters[c].images[i].failure = nil }
        if jobs[j].chapters[c].saved { jobs[j].paused = false }; persist(); pump()
    }
    func remove(_ key: String) {
        guard let owner, let job = jobs.first(where:{$0.id == key}) else { return }
        pause(key)
        for task in active.values where delegate.tag(task)?.job == key && delegate.tag(task)?.owner == owner { task.cancel() }
        do {
            for chapter in job.chapters {
                for file in chapter.images.flatMap(\.storedFiles) where FileManager.default.fileExists(atPath:Disk.file(owner,file).path) { try FileManager.default.removeItem(at:Disk.file(owner,file)) }
            }
            jobs.removeAll { $0.id == key }; persist(); revision += 1
        } catch { notice = error.localizedDescription }
    }
    func invalidatePage(_ payload: ChapterPayload, index: Int) {
        guard let owner, let j = jobs.firstIndex(where: { $0.id == payload.item.key }),
              let c = jobs[j].chapters.firstIndex(where: { $0.id == chapterNumber(payload.number) }),
              jobs[j].chapters[c].images.indices.contains(index) else { return }
        let path = jobs[j].chapters[c].images[index].file
        do { if FileManager.default.fileExists(atPath:Disk.file(owner,path).path) { try FileManager.default.removeItem(at:Disk.file(owner,path)) } }
        catch { notice = error.localizedDescription; return }
        jobs[j].chapters[c].images[index].done = false
        jobs[j].chapters[c].images[index].bytes = 0
        jobs[j].chapters[c].images[index].expected = nil
        jobs[j].chapters[c].images[index].attempts = 0
        jobs[j].chapters[c].images[index].failure = "الصورة المحلية تالفة؛ أعد تحميل الناقص"
        persist(); revision += 1
    }
    func leaveChapter(_ id: String) {
        fastFallback[id]?.cancel(); fastFallback[id] = nil
        if readerPriority == id { readerPriority = nil }
        for j in jobs.indices { for c in jobs[j].chapters.indices where jobs[j].id+":"+jobs[j].chapters[c].id == id && !jobs[j].chapters[c].saved {
            jobs[j].chapters[c].expiresAt = Date().addingTimeInterval(180)
            for task in active.values where delegate.tag(task)?.owner == owner && delegate.tag(task)?.job == jobs[j].id && delegate.tag(task)?.chapter == jobs[j].chapters[c].id { task.cancel() }
        } }
        persist(); pump()
    }
    func cleanTemporary(now: Date = Date(), all: Bool = false) {
        guard let owner else { return }
        for j in jobs.indices.reversed() {
            for c in jobs[j].chapters.indices.reversed() {
                let chapter = jobs[j].chapters[c]; let id = jobs[j].id+":"+chapter.id
                guard !chapter.saved, readerPriority != id, all || (chapter.expiresAt.map { $0 <= now } ?? false) else { continue }
                for task in active.values where delegate.tag(task)?.owner == owner && delegate.tag(task)?.job == jobs[j].id && delegate.tag(task)?.chapter == chapter.id { task.cancel() }
                do {
                    for file in chapter.images.flatMap(\.storedFiles) where FileManager.default.fileExists(atPath:Disk.file(owner,file).path) { try FileManager.default.removeItem(at:Disk.file(owner,file)) }
                    let metadata = Disk.file(owner,Disk.chapterName(id))
                    if FileManager.default.fileExists(atPath:metadata.path) { try FileManager.default.removeItem(at:metadata) }
                    jobs[j].chapters.remove(at:c)
                } catch { notice = "تعذر تنظيف الصور المؤقتة: " + error.localizedDescription }
            }
            if jobs[j].chapters.isEmpty { jobs.remove(at:j) }
        }
        persist(); revision += 1
    }
    func compactSaved() async {
        guard !compacting, let account = owner else { return }
        compacting = true; defer { compacting = false; compactProgress = "" }
        let files = savedJobs.flatMap(\.chapters).flatMap(\.images).filter(\.done)
        guard quality != .original else { notice="الجودة الأصلية لا تُضغط. اختر جودة أخرى إذا رغبت بتقليل الحجم."; return }
        let chosen = quality
        var saved: Int64 = 0
        for (index,image) in files.enumerated() {
            guard owner == account, !Task.isCancelled else { break }
            compactProgress = "\(index+1) / \(files.count) صورة"
            let url = Disk.file(account,image.file)
            let size = await Task.detached(priority:.utility) { try? ImageStorage.compact(url,quality:chosen) }.value
            guard owner == account, let size else { continue }
            for j in jobs.indices { for c in jobs[j].chapters.indices { if let i = jobs[j].chapters[c].images.firstIndex(where:{$0.file == image.file && $0.done}) {
                saved += max(0,jobs[j].chapters[c].images[i].bytes-size)
                jobs[j].chapters[c].images[i].bytes = size; jobs[j].chapters[c].images[i].expected = size
                jobs[j].chapters[c].images[i].quality=chosen.rawValue
                jobs[j].chapters[c].requestedQuality=chosen.rawValue
            } } }
            persist()
        }
        revision += 1; notice = "اكتمل تقليل الحجم. تم توفير " + byteLabel(saved)
    }
    func isQualityUpgrade(_ payload: ChapterPayload) -> Bool {
        guard let part=jobs.first(where:{$0.id == payload.item.key})?.chapters.first(where:{$0.id == chapterNumber(payload.number)}) else { return false }
        return part.requestedQuality != nil && !part.complete
    }
    func qualityError(_ payload: ChapterPayload) -> String? {
        guard let job=jobs.first(where:{$0.id == payload.item.key}),let part=job.chapters.first(where:{$0.id == chapterNumber(payload.number)}) else { return nil }
        return job.error ?? part.error ?? part.images.compactMap(\.failure).first
    }
    func redownload(_ payload: ChapterPayload,quality: ImageQuality,announce: Bool = true) {
        guard let owner,let j=jobs.firstIndex(where:{$0.id == payload.item.key}),
              let c=jobs[j].chapters.firstIndex(where:{$0.id == chapterNumber(payload.number)}) else { return }
        let before=jobs
        let old=jobs[j].chapters[c].images
        let token=UUID().uuidString
        jobs[j].chapters[c].payload=payload
        jobs[j].chapters[c].requestedQuality=quality.rawValue
        jobs[j].chapters[c].error=nil
        jobs[j].chapters[c].images=payload.pages.enumerated().map { index,remote in
            let previous=old.indices.contains(index) ? old[index] : nil
            let fallback=previous?.storedFiles.first { FileManager.default.fileExists(atPath:Disk.file(owner,$0).path) }
            let bytes=fallback.flatMap { try? Disk.file(owner,$0).resourceValues(forKeys:[.fileSizeKey]).fileSize }.map(Int64.init)
            return ImageRecord(remote:remote,file:Disk.imageName(payload.id,index)+"."+token,quality:quality.rawValue,fallbackFile:fallback,fallbackBytes:bytes)
        }
        jobs[j].paused=false; jobs[j].error=nil
        if let targets=jobs[j].activeChapterIDs,!targets.contains(chapterNumber(payload.number)) {
            jobs[j].activeChapterIDs=targets+[chapterNumber(payload.number)]; jobs[j].selectionMode="selected"
        }
        do { try Disk.save(jobs,owner:owner,name:"downloads.json") }
        catch { jobs=before; notice="تعذر تجهيز الجودة الجديدة: "+error.localizedDescription; return }
        // New transfer identities make late callbacks unable to replace the new selection.
        for task in active.values where delegate.tag(task)?.owner == owner && delegate.tag(task)?.job == payload.item.key && delegate.tag(task)?.chapter == chapterNumber(payload.number) { task.cancel() }
        let retained=Set(jobs[j].chapters[c].images.flatMap(\.storedFiles))
        for file in old.flatMap(\.storedFiles) where !retained.contains(file) { try? FileManager.default.removeItem(at:Disk.file(owner,file)) }
        revision += 1
        if announce { notice="أضيف تنزيل الفصل بجودة "+quality.label+". تبقى الصور الحالية متاحة حتى يكتمل البديل." }
        pump()
    }
    func redownloadSaved(_ key: String,quality: ImageQuality) {
        guard let j=jobs.firstIndex(where:{$0.id == key}) else { return }
        for c in jobs[j].chapters.indices where jobs[j].chapters[c].saved { jobs[j].chapters[c].requestedQuality=quality.rawValue }
        let payloads=jobs[j].chapters.filter(\.saved).compactMap(\.payload)
        if !jobs[j].wholeStory { jobs[j].activeChapterIDs=jobs[j].chapters.filter(\.saved).map(\.id); jobs[j].selectionMode="selected" }
        persist()
        for payload in payloads { redownload(payload,quality:quality) }
        prepare(key); pump()
    }
    func pageURL(_ payload: ChapterPayload, index: Int) -> URL? {
        guard let owner else { return nil }
        let image=jobs.first(where:{$0.id == payload.item.key})?.chapters.first(where:{$0.id == chapterNumber(payload.number)})?.images
        let files=image.flatMap { $0.indices.contains(index) ? $0[index].storedFiles : nil } ?? [Disk.imageName(payload.id,index)]
        return files.map { Disk.file(owner,$0) }.first { FileManager.default.fileExists(atPath:$0.path) }
    }
    private func pump() {
        guard restored, online, let owner else { return }
        var count = active.values.filter { $0.state == .running && delegate.tag($0)?.owner == owner }.count
        let jobOrder = jobs.indices.sorted { (readerPriority?.hasPrefix(jobs[$0].id+":") == true ? 0 : 1) < (readerPriority?.hasPrefix(jobs[$1].id+":") == true ? 0 : 1) }
        for j in jobOrder {
            let chapterOrder = jobs[j].chapters.indices.sorted { (jobs[j].id+":"+jobs[j].chapters[$0].id == readerPriority ? 0 : 1) < (jobs[j].id+":"+jobs[j].chapters[$1].id == readerPriority ? 0 : 1) }
            for c in chapterOrder {
                let part = jobs[j].chapters[c]
                if part.saved {
                    guard !jobs[j].paused, jobs[j].includes(part.id), !wifiOnly || onWiFi else { continue }
                } else { guard readerPriority == jobs[j].id+":"+part.id else { continue } }
                guard let payload = jobs[j].chapters[c].payload else { continue }
                for i in jobs[j].chapters[c].images.indices {
                    if count >= (part.saved ? 3 : 6) { return }
                    let image = jobs[j].chapters[c].images[i]
                    guard !image.done, image.attempts < 3, active[owner+":"+image.file] == nil else { continue }
                    do {
                        let free = (try? Disk.root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
                        guard free > 80 * 1024 * 1024 else { jobs[j].error = "المساحة المتاحة منخفضة؛ أفرغ مساحة ثم استكمل"; jobs[j].paused = true; persist(); return }
                        let chosen=ImageQuality(rawValue:image.quality ?? part.requestedQuality ?? quality.rawValue) ?? quality
                        var req = try API.shared.imageRequest(source:payload.item.source,url:image.remote,referer:payload.chapterUrl ?? payload.item.url,quality:chosen)
                        if part.requestedQuality != nil { req.cachePolicy = .reloadIgnoringLocalCacheData }
                        let tag = TransferTag(owner:owner,job:jobs[j].id,chapter:jobs[j].chapters[c].id,image:image.file,quality:chosen.rawValue)
                        let task = (part.saved ? session : readerSession).downloadTask(with:req)
                        task.taskDescription = String(data:try JSONEncoder().encode(tag),encoding:.utf8)
                        jobs[j].chapters[c].images[i].attempts += 1
                        jobs[j].chapters[c].images[i].failure = nil
                        active[owner+":"+image.file] = task; count += 1
                        persist(); task.resume()
                    } catch { jobs[j].error = error.localizedDescription }
                }
            }
        }
    }
    func speedFor(_ job: String) -> Int64 {
        _ = speed // Observed once per second, so a visible summary refreshes even while bytes stall.
        let samples = speedSamples.filter { $0.2 == job && $0.0 > Date().addingTimeInterval(-4) }
        return Int64(Double(samples.reduce(0) { $0 + $1.1 }) / max(1,Date().timeIntervalSince(samples.first?.0 ?? Date())))
    }
    private func updateSpeed() {
        let cutoff = Date().addingTimeInterval(-4); speedSamples.removeAll { $0.0 < cutoff }
        let duration = max(1,Date().timeIntervalSince(speedSamples.first?.0 ?? Date()))
        let value = Int64(Double(speedSamples.reduce(0) { $0 + $1.1 }) / duration)
        if speed != value { speed = value }
        flushProgress()
    }
    // Fold buffered byte counts into the observed jobs once per tick.
    private func flushProgress() {
        guard !liveBytes.isEmpty else { return }
        let pending = liveBytes; liveBytes.removeAll()
        for (tag,total,expected) in pending.values {
            guard tag.owner == owner, let j = jobs.firstIndex(where:{$0.id == tag.job}), let c = jobs[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = jobs[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}), !jobs[j].chapters[c].images[i].done else { continue }
            jobs[j].chapters[c].images[i].bytes = total
            if expected > 0 { jobs[j].chapters[c].images[i].expected = expected }
        }
        if Date().timeIntervalSince(lastSaved) > 2 { persist() }
    }
    private func didProgress(_ tag: TransferTag, delta: Int64, total: Int64, expected: Int64) {
        guard tag.owner == owner else { return }
        liveBytes[tag.owner+":"+tag.image] = (tag,total,expected)
        speedSamples.append((Date(),delta,tag.job))
    }
    func didFinish(_ tag: TransferTag, bytes: Int64, error: String?, optimized: Bool) {
        active.removeValue(forKey:tag.owner+":"+tag.image)
        liveBytes.removeValue(forKey:tag.owner+":"+tag.image)
        if tag.owner != owner {
            // A suspended account may receive one last callback. Persist it only in its own directory.
            var other = Disk.read([DownloadJob].self,owner:tag.owner,name:"downloads.json") ?? []
            if let j = other.firstIndex(where:{$0.id == tag.job}), let c = other[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = other[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}) {
                other[j].chapters[c].images[i].done = error == nil; other[j].chapters[c].images[i].bytes = bytes
                other[j].chapters[c].images[i].failure = error
                other[j].chapters[c].images[i].edgeOptimized = optimized
                other[j].chapters[c].images[i].quality=tag.quality
                if error == nil {
                    if let file=other[j].chapters[c].images[i].fallbackFile { try? FileManager.default.removeItem(at:Disk.file(tag.owner,file)) }
                    other[j].chapters[c].images[i].fallbackFile=nil; other[j].chapters[c].images[i].fallbackBytes=nil
                }
                try? Disk.save(other,owner:tag.owner,name:"downloads.json")
            } else if !other.flatMap(\.chapters).flatMap(\.images).flatMap(\.storedFiles).contains(tag.image) {
                try? FileManager.default.removeItem(at:Disk.file(tag.owner,tag.image))
            }
            return
        }
        guard let j = jobs.firstIndex(where:{$0.id == tag.job}), let c = jobs[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = jobs[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}) else {
            if !jobs.flatMap(\.chapters).flatMap(\.images).contains(where:{$0.fallbackFile == tag.image}) {
                try? FileManager.default.removeItem(at:Disk.file(tag.owner,tag.image))
            }
            return
        }
        jobs[j].chapters[c].images[i].done = error == nil
        jobs[j].chapters[c].images[i].bytes = bytes
        jobs[j].chapters[c].images[i].failure = error
        jobs[j].chapters[c].images[i].edgeOptimized = optimized
        jobs[j].chapters[c].images[i].quality=tag.quality
        if error == nil {
            jobs[j].chapters[c].images[i].expected = bytes
            if let file=jobs[j].chapters[c].images[i].fallbackFile { try? FileManager.default.removeItem(at:Disk.file(tag.owner,file)) }
            jobs[j].chapters[c].images[i].fallbackFile=nil; jobs[j].chapters[c].images[i].fallbackBytes=nil
        }
        persist(); revision += 1
        // Every page is visible in the lighter quality: upgrade in the background.
        if error == nil, jobs[j].chapters[c].complete, let target = jobs[j].chapters[c].upgradeQuality,
           let upgrade = ImageQuality(rawValue:target), let payload = jobs[j].chapters[c].payload {
            jobs[j].chapters[c].upgradeQuality = nil
            if readerPriority == jobs[j].id+":"+jobs[j].chapters[c].id { redownload(payload,quality:upgrade,announce:false); return }
            persist()
        }
        if error != nil { Task { try? await Task.sleep(for:.seconds(2)); self.pump() } } else { pump() }
    }
}
