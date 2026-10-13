import Foundation
import UIKit
import ImageIO
import Combine

final class TransferDelegate: NSObject, URLSessionDownloadDelegate {
    var progress: ((TransferTag, Int64, Int64, Int64) -> Void)?
    var finished: ((TransferTag, Int64, String?) -> Void)?
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
            let destination = Disk.file(t.owner,t.image)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:destination.path) { try FileManager.default.removeItem(at:destination) }
            try FileManager.default.moveItem(at:location,to:destination)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:destination.path)
            let bytes = (try destination.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
            finished?(t,Int64(bytes),nil)
        } catch { finished?(t,0,error.localizedDescription) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let t = tag(task) { finished?(t,0,error.localizedDescription) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { backgroundFinished?() }
}

@MainActor final class Downloads: ObservableObject {
    static let shared = Downloads()
    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var speed: Int64 = 0
    @Published private(set) var revision = 0
    @Published var notice: String?
    @Published var preparing: Set<String> = []
    var owner: String?
    var online = true
    var onWiFi = true
    var wifiOnly: Bool {
        get { UserDefaults.standard.bool(forKey:"wifiOnly") }
        set { UserDefaults.standard.set(newValue,forKey:"wifiOnly"); updateNetwork() }
    }
    private let delegate = TransferDelegate()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier:"site.wany.ios.downloads.v1")
        c.httpMaximumConnectionsPerHost = 3
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.timeoutIntervalForResource = 7 * 24 * 3600
        c.httpShouldSetCookies = false
        return URLSession(configuration:c,delegate:delegate,delegateQueue:nil)
    }()
    private var active: [String: URLSessionDownloadTask] = [:]
    private var workers: [String: Task<Void,Never>] = [:]
    private var speedSamples: [(Date,Int64,String)] = []
    var readerPriority: String?
    private var lastSaved = Date.distantPast
    private var restored = false
    var backgroundCompletion: (() -> Void)?
    private init() {
        delegate.progress = { tag,delta,total,expected in Task { @MainActor in self.didProgress(tag,delta:delta,total:total,expected:expected) } }
        delegate.finished = { tag,bytes,error in Task { @MainActor in self.didFinish(tag,bytes:bytes,error:error) } }
        delegate.backgroundFinished = { Task { @MainActor in self.backgroundCompletion?(); self.backgroundCompletion = nil } }
        Task { await restoreTasks() }
        Timer.scheduledTimer(withTimeInterval:1,repeats:true) { _ in Task { @MainActor in self.updateSpeed() } }
    }
    private func restoreTasks() async {
        for task in await session.allTasks {
            if let d = task as? URLSessionDownloadTask, let tag = delegate.tag(task) { active[tag.owner + ":" + tag.image] = d }
        }
        restored = true; pump()
    }
    func attach(_ userID: String?) {
        workers.values.forEach { $0.cancel() }; workers.removeAll(); preparing.removeAll()
        // Logout suspends existing transfers. Their account-tagged files cannot enter another account.
        for (key, task) in active where !key.hasPrefix((userID ?? "<none>") + ":") { task.suspend() }
        owner = userID; speedSamples.removeAll(); speed = 0
        jobs = userID.flatMap { Disk.read([DownloadJob].self,owner:$0,name:"downloads.json") } ?? []
        if let userID {
            for j in jobs.indices { for c in jobs[j].chapters.indices { for i in jobs[j].chapters[c].images.indices {
                let page = jobs[j].chapters[c].images[i]
                if page.done && !FileManager.default.fileExists(atPath:Disk.file(userID,page.file).path) {
                    jobs[j].chapters[c].images[i].done = false; jobs[j].chapters[c].images[i].bytes = 0
                }
            } } }
        }
        resumePreparations(); pump()
    }
    func persist() {
        guard let owner else { return }
        do { try Disk.save(jobs,owner:owner,name:"downloads.json") } catch { notice = "تعذر حفظ قائمة التنزيل: " + error.localizedDescription }
        lastSaved = Date()
    }
    func enqueue(_ story: Story, chapters: [Chapter]? = nil) async {
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
                jobs[index].chapters.sort { $0.chapter.number < $1.chapter.number }
                jobs[index].story = full; jobs[index].paused = false; jobs[index].error = nil
                jobs[index].wholeStory = jobs[index].wholeStory || chapters == nil
                jobs[index].chapterListComplete = true
            } else {
                jobs.append(DownloadJob(id:story.key,story:full,chapters:selected.map { ChapterDownload(chapter:$0) },wholeStory:chapters == nil,chapterListComplete:true))
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
        if !jobs[j].chapters.contains(where:{$0.id == chapter.id}) { jobs[j].chapters.append(ChapterDownload(chapter:chapter)) }
        guard let c = jobs[j].chapters.firstIndex(where:{$0.id == chapter.id}) else { return }
        if jobs[j].chapters[c].payload == nil { install(payload,job:j,chapter:c,owner:owner) }
        persist(); pump()
    }
    private func install(_ payload: ChapterPayload, job: Int, chapter: Int, owner: String) {
        jobs[job].chapters[chapter].payload = payload; jobs[job].chapters[chapter].error = nil
        jobs[job].chapters[chapter].images = payload.pages.enumerated().map { index, remote in
            let file = Disk.imageName(payload.id,index)
            let url = Disk.file(owner,file)
            let size = ((try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            return ImageRecord(remote:remote,file:file,expected:size > 0 ? size : nil,bytes:size,done:size > 0)
        }
    }
    private func prepare(_ key: String) {
        guard workers[key] == nil, let owner, online, !wifiOnly || onWiFi else { return }
        workers[key] = Task { [weak self] in
            guard let self else { return }
            defer { self.workers[key] = nil }
            while !Task.isCancelled, self.owner == owner, self.online {
                guard let j = self.jobs.firstIndex(where:{$0.id == key}), !self.jobs[j].paused,
                      let c = self.jobs[j].chapters.firstIndex(where:{$0.payload == nil && $0.error == nil}) else { break }
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
            let paused = jobs.first(where:{$0.id == t.job})?.paused ?? true
            if paused || (wifiOnly && !onWiFi) { task.suspend() } else { task.resume() }
        }
        if online { for j in jobs.indices { for c in jobs[j].chapters.indices where jobs[j].chapters[c].payload == nil { jobs[j].chapters[c].error = nil } }; resumePreparations(); pump() }
    }
    func pause(_ key: String) {
        guard let j = jobs.firstIndex(where:{$0.id == key}) else { return }
        jobs[j].paused = true; workers[key]?.cancel(); workers[key] = nil
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
        jobs[j].paused = false; persist(); pump()
    }
    func remove(_ key: String) {
        guard let owner, let job = jobs.first(where:{$0.id == key}) else { return }
        pause(key)
        for task in active.values where delegate.tag(task)?.job == key && delegate.tag(task)?.owner == owner { task.cancel() }
        do {
            for chapter in job.chapters {
                for image in chapter.images where FileManager.default.fileExists(atPath:Disk.file(owner,image.file).path) { try FileManager.default.removeItem(at:Disk.file(owner,image.file)) }
            }
            jobs.removeAll { $0.id == key }; persist(); revision += 1
        } catch { notice = error.localizedDescription }
    }
    func pageURL(_ payload: ChapterPayload, index: Int) -> URL? {
        guard let owner else { return nil }
        let u = Disk.file(owner,Disk.imageName(payload.id,index)); return FileManager.default.fileExists(atPath:u.path) ? u : nil
    }
    private func pump() {
        guard restored, online, let owner, !wifiOnly || onWiFi else { return }
        var count = active.values.filter { $0.state == .running && delegate.tag($0)?.owner == owner }.count
        let jobOrder = jobs.indices.sorted { (readerPriority?.hasPrefix(jobs[$0].id+":") == true ? 0 : 1) < (readerPriority?.hasPrefix(jobs[$1].id+":") == true ? 0 : 1) }
        for j in jobOrder where !jobs[j].paused {
            let chapterOrder = jobs[j].chapters.indices.sorted { (jobs[j].id+":"+jobs[j].chapters[$0].id == readerPriority ? 0 : 1) < (jobs[j].id+":"+jobs[j].chapters[$1].id == readerPriority ? 0 : 1) }
            for c in chapterOrder {
                guard let payload = jobs[j].chapters[c].payload else { continue }
                for i in jobs[j].chapters[c].images.indices {
                    if count >= 3 { return }
                    let image = jobs[j].chapters[c].images[i]
                    guard !image.done, image.attempts < 3, active[owner+":"+image.file] == nil else { continue }
                    do {
                        let free = (try? Disk.root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
                        guard free > 80 * 1024 * 1024 else { jobs[j].error = "المساحة المتاحة منخفضة؛ أفرغ مساحة ثم استكمل"; jobs[j].paused = true; persist(); return }
                        let req = try API.shared.imageRequest(source:payload.item.source,url:image.remote,referer:payload.chapterUrl ?? payload.item.url)
                        let tag = TransferTag(owner:owner,job:jobs[j].id,chapter:jobs[j].chapters[c].id,image:image.file)
                        let task = session.downloadTask(with:req)
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
        let samples = speedSamples.filter { $0.2 == job && $0.0 > Date().addingTimeInterval(-4) }
        return Int64(Double(samples.reduce(0) { $0 + $1.1 }) / max(1,Date().timeIntervalSince(samples.first?.0 ?? Date())))
    }
    private func updateSpeed() {
        let cutoff = Date().addingTimeInterval(-4); speedSamples.removeAll { $0.0 < cutoff }
        let duration = max(1,Date().timeIntervalSince(speedSamples.first?.0 ?? Date()))
        speed = Int64(Double(speedSamples.reduce(0) { $0 + $1.1 }) / duration)
    }
    private func didProgress(_ tag: TransferTag, delta: Int64, total: Int64, expected: Int64) {
        guard tag.owner == owner, let j = jobs.firstIndex(where:{$0.id == tag.job}), let c = jobs[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = jobs[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}) else { return }
        jobs[j].chapters[c].images[i].bytes = total
        if expected > 0 { jobs[j].chapters[c].images[i].expected = expected }
        speedSamples.append((Date(),delta,tag.job)); updateSpeed()
        if Date().timeIntervalSince(lastSaved) > 2 { persist() }
    }
    private func didFinish(_ tag: TransferTag, bytes: Int64, error: String?) {
        active.removeValue(forKey:tag.owner+":"+tag.image)
        if tag.owner != owner {
            // A suspended account may receive one last callback. Persist it only in its own directory.
            var other = Disk.read([DownloadJob].self,owner:tag.owner,name:"downloads.json") ?? []
            if let j = other.firstIndex(where:{$0.id == tag.job}), let c = other[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = other[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}) {
                other[j].chapters[c].images[i].done = error == nil; other[j].chapters[c].images[i].bytes = bytes
                other[j].chapters[c].images[i].failure = error
                try? Disk.save(other,owner:tag.owner,name:"downloads.json")
            }
            return
        }
        guard let j = jobs.firstIndex(where:{$0.id == tag.job}), let c = jobs[j].chapters.firstIndex(where:{$0.id == tag.chapter}), let i = jobs[j].chapters[c].images.firstIndex(where:{$0.file == tag.image}) else { return }
        jobs[j].chapters[c].images[i].done = error == nil
        jobs[j].chapters[c].images[i].bytes = bytes
        jobs[j].chapters[c].images[i].failure = error
        if error == nil { jobs[j].chapters[c].images[i].expected = bytes }
        persist(); revision += 1
        if error != nil { Task { try? await Task.sleep(for:.seconds(2)); self.pump() } } else { pump() }
    }
}
