import Foundation
import Network
import UIKit
import ImageIO
import Observation

// Observation tracks each property separately: a screen re-renders only when a
// value it actually reads changes (feed progress never redraws the profile).
@MainActor @Observable final class AppStore {
    var enteringAccount = false
    var firstArrival = false
    var state: AccountState? {
        didSet { if accountID != state?.user.id { accountID = state?.user.id } }
    }
    // Screens that only care who is signed in read this instead of the whole account state.
    private(set) var accountID: String?
    var stories: [String:Story] = [:]
    var online = true
    var localSaveFailed = false
    var syncing = false
    var loginRequired = false
    var error: String?
    // A failed automatic sync is shown quietly in the top banner instead of an alert.
    var syncProblem: String?
    var loadingFeed = false
    // When each feed was last fetched in this launch; a saved copy shows at once and is refreshed behind it.
    var feedLoadedAt: [String:Date] = [:]
    var feedProgress = ""
    var feedError: String?
    var incomingFriendRequests = 0
    var unreadMessages = 0
    var readingMutation = false
    var chromeHidden = false
    var showingNameStory = false
    var readerActive = false
    // The wallpaper pauses while content scrolls or a page transition runs.
    var backdropHeld = false
    // Bumped when a cover file lands on disk, so visible covers reload once.
    private(set) var coverRevision = 0
    // Bumped when library-related data changes; drives the debounced ambience refresh.
    private(set) var libraryRevision = 0
    @ObservationIgnored let downloads = Downloads.shared
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var metadataTask: Task<Void,Never>?
    @ObservationIgnored private var metadataToken: UUID?
    @ObservationIgnored private var syncTask: Task<Void,Never>?
    @ObservationIgnored private var refreshTask: Task<Void,Never>?
    @ObservationIgnored private var engine: FeedEngine?
    @ObservationIgnored private var coverRequests: Set<String> = []
    @ObservationIgnored private var refreshOwner: String?
    @ObservationIgnored private var favoriteBusy: Set<String> = []
    @ObservationIgnored private var friendTick = 0
    @ObservationIgnored private var seriesInFlight: [String:Task<Story,Error>] = [:]
    @ObservationIgnored private var seriesSave: Task<Void,Never>?
    @ObservationIgnored private var seriesFetched: [String:Double] = (UserDefaults.standard.dictionary(forKey:"rany.seriesFetched") as? [String:Double]) ?? [:]
    @ObservationIgnored private var storiesSave: Task<Void,Never>?
    @ObservationIgnored private var accountSave: Task<Void,Never>?
    @ObservationIgnored private var storiesOwner: String?
    @ObservationIgnored private var scrollHold = false
    @ObservationIgnored private var navigationHold: Task<Void,Never>?
    @ObservationIgnored private var snapshotRetryAfter: [String:Date] = [:]
    @ObservationIgnored private var snapshotSyncID: UUID?
    @ObservationIgnored private var snapshotSyncTask: Task<Void,Never>?
    init(startServices: Bool = true) {
        guard startServices else { return }
        if let owner = UserDefaults.standard.string(forKey:"lastAccount") {
            state = Disk.read(AccountState.self,owner:owner,name:"account.json")
            accountID = state?.user.id // Observers do not run inside init.
            if state != nil { loadStories(owner); downloads.attachInBackground(owner); firstArrival = UserDefaults.standard.bool(forKey:"rany.firstArrival."+owner) }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.online
                self.online = path.status == .satisfied
                self.downloads.online = self.online; self.downloads.onWiFi = path.usesInterfaceType(.wifi)
                self.downloads.updateNetwork()
                if self.online && (wasOffline || self.state?.lastSynced == nil) { await self.refresh(quiet:true) }
            }
        }
        monitor.start(queue:DispatchQueue(label:"Wany.network"))
        Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            await self.syncProgress()
            // Friend requests are checked every two minutes, not on every sync tick.
            self.friendTick += 1
            if self.friendTick % 4 == 0 { await self.refreshFriendRequests() }
        } }
    }
    // Reading progress saves often; encode and write it off the main thread, coalesced.
    func persist() {
        guard let owner = state?.user.id else { return }
        accountSave?.cancel()
        // While reading, positions change every few seconds and the account file grows with
        // every chapter read, so writes are gathered for a few seconds; leaving the app or
        // the account still saves at once (persistNow).
        let delay = readerActive ? 4000 : 250
        accountSave = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(delay)) } catch { return }
            guard let self, let snapshot = self.state, snapshot.user.id == owner else { return }
            let failure = await Task.detached(priority:.utility) { () -> String? in
                do { try Disk.save(snapshot,owner:owner,name:"account.json"); return nil } catch { return error.localizedDescription }
            }.value
            self.finishSave(failure)
        }
    }
    // Leaving the app or the account must not depend on a pending background write.
    func persistNow() {
        accountSave?.cancel(); accountSave = nil
        guard let state else { return }
        do { try Disk.save(state,owner:state.user.id,name:"account.json"); finishSave(nil) } catch { finishSave(error.localizedDescription) }
    }
    private func finishSave(_ failure: String?) {
        if let failure { localSaveFailed = true; self.error = "تعذر حفظ التقدم على الجهاز: " + failure }
        else if localSaveFailed { localSaveFailed = false }
    }
    // The story archive can hold thousands of chapters; decode it off the main thread.
    private func loadStories(_ owner: String) {
        stories = [:]; storiesOwner = nil; storiesSave?.cancel()
        Task { [weak self] in
            let loaded = await Task.detached(priority:.userInitiated) { Disk.read([String:Story].self,owner:owner,name:"stories.json") ?? [:] }.value
            guard let self, self.state?.user.id == owner else { return }
            // Keep stories remembered while the archive was loading.
            self.stories = loaded.merging(self.stories) { _,new in new }
            self.storiesOwner = owner
            self.libraryRevision += 1
            if !self.stories.isEmpty && self.stories.count != loaded.count { self.scheduleStoriesSave() }
        }
    }
    func remember(_ story: Story) {
        guard state?.user.id != nil else { return }
        // List cards must not overwrite a complete offline chapter archive.
        var merged = story
        if let old=stories[story.key],old.cover.hasPrefix("/api/work-snapshots/"),!story.cover.hasPrefix("/api/work-snapshots/") {
            merged.snapshotOriginalCover=story.cover; merged.cover=old.cover
        }
        // A partial list (a list card, or a source page that failed) only adds chapters
        // to what is already known; nothing previously fetched disappears.
        if let old = stories[story.key], story.chapterListComplete != true, let known = old.chapters, !known.isEmpty {
            var byNumber = Dictionary(known.map { ($0.id,$0) },uniquingKeysWith:SeriesChapters.prefer)
            for c in story.chapters ?? [] { byNumber[c.id] = byNumber[c.id].map { SeriesChapters.prefer($0,c) } ?? c }
            merged.chapters = byNumber.values.sorted { $0.number < $1.number }
            if old.chapterListComplete == true && (story.chapters ?? []).count <= known.count { merged.chapterListComplete = true; merged.chapterPageCount = old.chapterPageCount }
        }
        // Lightweight list cards carry no description or genres; keep the saved ones so
        // a story opened offline still shows its details.
        if let old = stories[story.key] {
            if (merged.description ?? "").isEmpty, let saved = old.description, !saved.isEmpty { merged.description = saved }
            if merged.genres.isEmpty && !old.genres.isEmpty { merged.genres = old.genres }
            if merged.status == nil { merged.status = old.status }
        }
        guard stories[story.key] != merged else { return }
        stories[story.key] = merged
        libraryRevision += 1
        scheduleStoriesSave()
    }
    // Coalesce bursts of remembered stories into one background encode and write.
    private func scheduleStoriesSave() {
        guard let owner = storiesOwner, owner == state?.user.id else { return }
        storiesSave?.cancel()
        storiesSave = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(400)) } catch { return }
            guard let self, self.storiesOwner == owner else { return }
            let snapshot = self.stories
            let failure = await Task.detached(priority:.utility) { () -> String? in
                do { try Disk.save(snapshot,owner:owner,name:"stories.json"); return nil } catch { return error.localizedDescription }
            }.value
            if let failure, self.state?.user.id == owner { self.error = failure }
        }
    }
    func setScrolling(_ moving: Bool) {
        guard scrollHold != moving else { return }
        scrollHold = moving; updateBackdropHold()
    }
    func holdBackdropForNavigation() {
        navigationHold?.cancel()
        navigationHold = Task { [weak self] in
            self?.updateBackdropHold(navigating:true)
            do { try await Task.sleep(for:.milliseconds(650)) } catch { return }
            self?.navigationHold = nil; self?.updateBackdropHold()
        }
    }
    private func updateBackdropHold(navigating: Bool = false) {
        let held = scrollHold || navigating || navigationHold != nil
        if backdropHeld != held { backdropHeld = held }
    }
    func login(username: String, password: String, freshAccount: Bool = false) async {
        guard online else { error = "تسجيل الدخول لأول مرة يحتاج إنترنت"; return }
        do {
            refreshTask?.cancel()
            metadataTask?.cancel(); metadataTask = nil; metadataToken = nil
            API.shared.generation = UUID(); engine = nil
            let body = try JSONEncoder().encode(["username":username.precomposedStringWithCompatibilityMapping.trimmingCharacters(in:.whitespacesAndNewlines).lowercased(),"password":password])
            let response = try JSONDecoder().decode(SessionResponse.self,from:await API.shared.raw("/api/login",method:"POST",body:body))
            guard let user = response.user else { throw APIError(message:"بيانات الدخول غير صحيحة",status:401) }
            firstArrival = freshAccount || UserDefaults.standard.bool(forKey:"rany.newAccount."+username.precomposedStringWithCompatibilityMapping.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()) || UserDefaults.standard.bool(forKey:"rany.firstArrival."+user.id)
            if firstArrival { UserDefaults.standard.set(true,forKey:"rany.firstArrival."+user.id) }
            persistNow()
            enteringAccount = true
            state = Disk.read(AccountState.self,owner:user.id,name:"account.json") ?? AccountState(user:user)
            state?.user = user; loginRequired = false
            UserDefaults.standard.set(user.id,forKey:"lastAccount")
            loadStories(user.id); downloads.attach(user.id); persist()
            await refresh(quiet:true)
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func register(username: String, password: String, confirmation: String, question: String, answer: String) async -> Bool {
        guard online else { error = "إنشاء الحساب يحتاج إنترنت"; return false }
        do {
            let value = ["username":username.precomposedStringWithCompatibilityMapping.trimmingCharacters(in:.whitespacesAndNewlines).lowercased(),"password":password,"confirmPassword":confirmation,"securityQuestion":question,"securityAnswer":answer]
            try await API.shared.send("/api/register",value:value)
            UserDefaults.standard.set(true,forKey:"rany.newAccount."+value["username"]!)
            return true
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription }; return false }
    }
    func completeAccountArrival() {
        if let user = state?.user {
            UserDefaults.standard.removeObject(forKey:"rany.firstArrival."+user.id)
            UserDefaults.standard.removeObject(forKey:"rany.newAccount."+user.username.lowercased())
        }
        firstArrival = false; enteringAccount = false
    }
    func logout() async {
        persistNow(); refreshTask?.cancel(); metadataTask?.cancel(); metadataTask = nil; metadataToken = nil; syncTask?.cancel(); snapshotSyncTask?.cancel(); snapshotSyncTask=nil; snapshotSyncID=nil; snapshotRetryAfter=[:]
        if online { _ = try? await API.shared.raw("/api/logout",method:"POST") }
        incomingFriendRequests=0; unreadMessages=0; syncProblem=nil; API.shared.clear(); downloads.attach(nil); enteringAccount = false; state = nil; stories = [:]; storiesOwner = nil; storiesSave?.cancel(); engine = nil
        UserDefaults.standard.removeObject(forKey:"lastAccount"); loginRequired = false
    }
    func sessionRenewed() { engine=nil; metadataTask?.cancel(); metadataTask=nil; metadataToken=nil }
    func report(_ error: Error) {
        guard !isRequestCancellation(error) else { return }
        if (error as? APIError)?.status == 401 { loginRequired=true }
        self.error=error.localizedDescription
    }
    func logoutAllDevices() async throws {
        guard online,let owner=state?.user.id else { throw APIError(message:"تحتاج هذه العملية اتصالًا وجلسة صالحة",status:0) }
        try await API.shared.send("/api/logout-all",value:[String:String]())
        guard state?.user.id == owner else { return }
        persistNow(); refreshTask?.cancel(); metadataTask?.cancel(); metadataTask=nil; metadataToken=nil; syncTask?.cancel(); snapshotSyncTask?.cancel(); snapshotSyncTask=nil; snapshotSyncID=nil; snapshotRetryAfter=[:]
        incomingFriendRequests=0; unreadMessages=0; syncProblem=nil; API.shared.clear(); downloads.attach(nil); enteringAccount=false; state=nil; stories=[:]; storiesOwner=nil; storiesSave?.cancel(); engine=nil
        UserDefaults.standard.removeObject(forKey:"lastAccount"); loginRequired=false
    }
    // quiet: started by the app itself (launch, return, reconnect); a failure goes to the
    // banner instead of interrupting with an alert.
    func refresh(quiet: Bool = false) async {
        // A refresh already running for this account answers this request too; one left
        // over from a previous account (cancelled at logout) never does.
        func joinRunning() async -> Bool {
            guard let running = refreshTask, !running.isCancelled, refreshOwner != nil, refreshOwner == state?.user.id else { return false }
            await running.value
            // Someone asked for this refresh: a failure of the automatic one it joined is
            // shown as a message, as for any refresh they start.
            if !quiet, let problem = syncProblem { syncProblem = nil; error = problem }
            return true
        }
        if await joinRunning() { return }
        // A tap during a background sync waits for it instead of being dropped silently.
        var waited = 0
        while online, syncing || readingMutation, waited < 150 {
            do { try await Task.sleep(for:.milliseconds(200)) } catch { return }
            waited += 1
            if await joinRunning() { return }
        }
        guard online, let owner = state?.user.id, !syncing, !readingMutation else { return }
        syncing = true
        // SwiftUI can cancel its refresh task when its view changes. The account owns this sync.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshAccount(owner:owner,quiet:quiet)
        }
        refreshTask = task; refreshOwner = owner
        await task.value
        if refreshTask == task { refreshTask = nil; refreshOwner = nil }
        syncing = false
    }
    // Statistics are read only on the statistics page; each sync used to recompute
    // them on the server for nothing.
    func refreshStats() async {
        guard online, !loginRequired, let owner = state?.user.id else { return }
        if let stats = try? await API.shared.get("/api/reading/stats",as:JSONValue.self), state?.user.id == owner { state?.stats = stats["stats"].object; persist() }
    }
    private func refreshAccount(owner: String, quiet: Bool) async {
        do {
            let session = try await API.shared.get("/api/session",as:SessionResponse.self)
            guard state?.user.id == owner else { return }
            guard let user = session.user, user.id == owner else { loginRequired = true; return }
            state?.user = user; loginRequired = false
            let pushed = try await mergeAndPush(owner:owner)
            let opened = await flushReadingOpens(owner:owner); scheduleSnapshots()
            // mergeAndPush already read the account; read it again only when this sync changed it.
            if pushed || opened {
                let fresh = try await accountData(owner:owner)
                guard state?.user.id == owner else { return }
                merge(fresh)
            }
            state?.lastSynced = Date(); persist()
            if let profile = try? await API.shared.get("/api/profiles/"+owner,as:JSONValue.self), state?.user.id == owner { state?.profile = profile; incomingFriendRequests=Int(profile["profile"]["pendingFriendRequests"].number); persist() }
            syncProblem = nil
            cacheLibrary()
        } catch {
            guard !Task.isCancelled, !isRequestCancellation(error), state?.user.id == owner else { return }
            if (error as? APIError)?.status == 401 { loginRequired = true }
            else if quiet { syncProblem = error.localizedDescription }
            else { syncProblem = nil; self.error = error.localizedDescription }
        }
    }
    private func merge(_ remote: AccountData) {
        guard var current = state else { return }
        current.mergeReadingData(remote); state = current
        libraryRevision += 1
    }
    // The server refuses this record for good (its data is invalid); retrying can never succeed,
    // so it must not hold back the records after it. Outages, rate limits and auth keep it queued.
    private func isPermanentRejection(_ error: Error) -> Bool {
        guard let status = (error as? APIError)?.status else { return false }
        return [400,413,422].contains(status)
    }
    @discardableResult
    private func mergeAndPush(owner: String) async throws -> Bool {
        var changed = false
        let remote = try await accountData(owner:owner)
        guard state?.user.id == owner else { throw CancellationError() }
        merge(remote)
        let completions = state?.completedPending?.values.map { $0 } ?? []
        let progress = state?.pending.values.map { $0 } ?? []
        let pending = (completions + progress.filter { !completions.contains($0) }).sorted { $0.updatedAt < $1.updatedAt }
        for record in pending {
            guard state?.user.id == owner else { throw CancellationError() }
            if let server = remote.progress[record.id], server.updatedAt > record.updatedAt {
                if state?.pending[record.id] == record { state?.pending.removeValue(forKey:record.id) }
                if state?.completedPending?[record.id] == record { state?.completedPending?.removeValue(forKey:record.id) }
                continue
            }
            do { try await API.shared.send("/api/progress",method:"PUT",value:record) }
            catch where isPermanentRejection(error) {}
            guard state?.user.id == owner else { throw CancellationError() }
            changed = true
            // Do not remove a newer local edit made while this request was in flight.
            if state?.pending[record.id] == record { state?.pending.removeValue(forKey:record.id) }
            if state?.completedPending?[record.id] == record { state?.completedPending?.removeValue(forKey:record.id) }
            persist()
        }
        return changed
    }
    func syncProgress() async {
        guard online, !loginRequired, !syncing, !readingMutation, let owner = state?.user.id, (state?.pending.isEmpty == false || state?.completedPending?.isEmpty == false || state?.pendingOpens?.isEmpty == false || state?.pendingSnapshots?.isEmpty == false) else { return }
        syncing = true; defer { syncing = false }
        do { try await mergeAndPush(owner:owner); await flushReadingOpens(owner:owner); scheduleSnapshots(); state?.lastSynced = Date(); syncProblem = nil; persist() }
        catch { if (error as? APIError)?.status == 401 { loginRequired = true } }
    }
    func record(_ payload: ChapterPayload, page: Int, percent: Double) {
        guard var current = state, !payload.pages.isEmpty else { return }
        let record = ProgressRecord(mangaId:payload.item.key,chapter:payload.number,percent:min(100,max(0,percent)),updatedAt:milliseconds())
        current.positions[payload.id] = page
        current.data.progress[record.id] = record; current.pending[record.id] = record
        current.data.lastOpened = LastOpened(mangaId:payload.item.key,chapter:payload.number)
        if let i = current.data.library.firstIndex(where:{$0.mangaId == payload.item.key}) {
            current.data.library[i].lastReadAt = record.updatedAt; current.data.library[i].lastReadChapter = payload.number
            current.data.library[i].highestReachedChapter = max(current.data.library[i].highestReachedChapter ?? 0,payload.number)
        } else { current.data.library.append(LibraryEntry(mangaId:payload.item.key,status:"reading",addedAt:record.updatedAt,updatedAt:record.updatedAt,lastReadAt:record.updatedAt,lastReadChapter:payload.number,highestReachedChapter:payload.number)) }
        if percent >= 98 {
            if !current.data.isCompleted(record.id) { current.data.completed.append(record.id) }
            if current.completedPending?[record.id] == nil {
                if current.completedPending == nil { current.completedPending = [:] }
                current.completedPending?[record.id] = record
            }
        }
        state = current; persist()
    }
    func downloadUnread(_ story: Story, quality: ImageQuality? = nil) async {
        guard online, let owner = state?.user.id, !loginRequired else {
            error = "تحميل الفصول يحتاج اتصالًا وجلسة دخول صالحة"; return
        }
        do {
            let full = try await series(story.key,maxAge:60)
            // Refresh website completions, retaining unsynced local completions and partial progress.
            let remote = try await accountData(owner:owner)
            guard state?.user.id == owner else { return }
            merge(remote); persist(); remember(full)
            guard let current = state else { return }
            let unread = current.unreadChapters(in:full)
            guard !unread.isEmpty else { downloads.notice = "جميع فصول هذه القصة مقروءة؛ لا توجد فصول غير مقروءة للتحميل"; return }
            await downloads.enqueue(full,chapters:unread,unreadOnly:true,quality:quality)
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func toggleFavorite(_ story: Story) async {
        guard let state else { return }
        guard online else { error = "تعديل المفضلة يحتاج اتصالًا؛ تقدم القراءة محفوظ أوفلاين"; return }
        let owner = state.user.id
        // A second tap while the first request runs would add the story twice.
        guard favoriteBusy.insert(owner+story.key).inserted else { return }
        defer { favoriteBusy.remove(owner+story.key) }
        do {
            if state.data.favorites.contains(story.key) {
                _ = try await API.shared.raw("/api/favorites/" + story.key.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!,method:"DELETE")
                guard self.state?.user.id == owner else { return }; self.state?.data.favorites.removeAll { $0 == story.key }
            } else {
                try await API.shared.send("/api/favorites",value:["mangaId":story.key])
                guard self.state?.user.id == owner else { return }
                if self.state?.data.favorites.contains(story.key) == false { self.state?.data.favorites.append(story.key) }
            }
            persist(); remember(story); libraryRevision += 1; queueSnapshot(story); cacheLibrary()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func setStatus(_ story: Story, status: String) async {
        do { try await API.shared.send("/api/library",method:"PUT",value:["mangaId":story.key,"status":status]); queueSnapshot(story); await refresh() } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func cacheLibrary() {
        guard metadataTask == nil, let current = state, online else { return }
        let owner = current.user.id
        // Currently-reading and favorite stories first, so their full details (description,
        // chapters) are saved for offline use before the rest of the library.
        let reading = current.data.library.filter { $0.status == "reading" }.sorted { ($0.lastReadAt ?? $0.updatedAt) > ($1.lastReadAt ?? $1.updatedAt) }.map(\.mangaId)
        var seen = Set<String>()
        let keys = (reading + current.data.favorites + current.data.library.map(\.mangaId)).filter { seen.insert($0).inserted }
        let token = UUID(); metadataToken = token
        metadataTask = Task { [weak self] in
            guard let self else { return }; defer { if self.metadataToken == token { self.metadataTask = nil; self.metadataToken = nil } }
            // Resolve lightweight cards first so a slow source never holds up the profile.
            for start in stride(from:0,to:keys.count,by:40) {
                if Task.isCancelled || self.state?.user.id != owner { return }
                let slice = Array(keys[start..<min(start+40,keys.count)])
                await self.restoreSnapshots(slice)
                if let r = try? await API.shared.get("/api/source/resolve",query:["keys":slice.joined(separator:",")],as:ResolveResponse.self) {
                    guard self.state?.user.id == owner else { return }; for item in r.items { self.remember(item) }
                }
            }
            for key in keys {
                if Task.isCancelled || self.state?.user.id != owner || !self.online { return }
                if let story = self.stories[key] { await self.cacheCover(story) }
                // Chapter lists refresh in the background at most every six hours, across launches.
                if self.seriesFresh(key,owner:owner,maxAge:21600) { continue }
                if let story = try? await self.series(key,maxAge:21600) { guard self.state?.user.id == owner else { return }; await self.cacheCover(story) }
            }
        }
    }
    func cacheCover(_ story: Story) async {
        guard let owner = state?.user.id, online else { return }
        let key = owner+story.key
        let file = Disk.file(owner,Disk.coverName(story.key))
        let versionName = "covers/"+Disk.hash(story.key)+".json"
        let oldURL = Disk.read(String.self,owner:owner,name:versionName)
        guard (!FileManager.default.fileExists(atPath:file.path) || (oldURL != nil && oldURL != story.cover)), !coverRequests.contains(key), !story.cover.isEmpty else { return }
        coverRequests.insert(key); defer { coverRequests.remove(key) }
        do {
            let (data,response) = try await URLSession.shared.data(for:API.shared.imageRequest(source:story.source,url:story.cover,referer:story.url))
            guard state?.user.id == owner, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let cover = story.cover
            // Validate and write the image off the main thread.
            try await Task.detached(priority:.utility) {
                guard CGImageSourceCreateWithData(data as CFData,nil).flatMap({ CGImageSourceCreateImageAtIndex($0,0,nil) }) != nil else { throw CancellationError() }
                try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
                try Disk.save(cover,owner:owner,name:versionName)
            }.value
            guard state?.user.id == owner else { return }
            coverRevision += 1; libraryRevision += 1
        } catch { /* A failed cover remains retryable and never clears a saved cover. */ }
    }
    func loadFeed(_ kind: String, page: Int = 1) async {
        guard online, !loadingFeed, let current = state else { return }
        if kind == "new",page>1 {
            guard let previous=state?.newFeed,previous.hasMore,page == previous.page+1 else { return }
        }
        loadingFeed = true; feedError=nil; defer { loadingFeed = false }
        if engine == nil { engine = FeedEngine() }
        do {
            let result = try await engine!.run(kind,data:current.data,user:current.user.id,page:page) { [weak self] text in
                guard let self else { return }
                if let p = try? JSONDecoder().decode(JSONValue.self,from:Data(text.utf8)) {
                    self.feedProgress = p["label"].string.isEmpty ? "جاري تجهيز اقتراحاتك \(Int(p.number))٪" : "\(p["label"].string) · \(Int(p["completed"].number))/\(Int(p["total"].number))"
                }
            }
            guard state?.user.id == current.user.id else { return }
            if kind == "fyp" {
                let recommendations = try await Task.detached(priority:.userInitiated) { try JSONDecoder().decode(FypSnapshot.self,from:result).recommendations }.value
                guard state?.user.id == current.user.id else { return }
                state?.fyp = recommendations; for r in recommendations { remember(r.item) }
            } else {
                let incoming = try await Task.detached(priority:.userInitiated) { try JSONDecoder().decode(NewFeed.self,from:result) }.value
                guard state?.user.id == current.user.id else { return }
                guard incoming.page == page else { throw APIError(message:"أُعيدت صفحة غير متوقعة؛ أعد المحاولة",status:0) }
                if page>1,let previous=state?.newFeed { state?.newFeed=previous.appending(incoming) }
                else { state?.newFeed=incoming }
                for r in incoming.all { remember(r.item) }
            }
            if page == 1 { feedLoadedAt[kind+":"+current.user.id] = Date() }
            persist()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.feedError = error.localizedDescription } }
    }
}

extension AppStore {
    // «جديد» covers the last 24 hours, so a saved copy goes stale quickly: reload it on the
    // first visit of a launch, when it is empty, and after a quarter of an hour.
    func newFeedNeedsReload(now: Date = Date()) -> Bool {
        guard let state else { return false }
        guard let feed=state.newFeed,!feed.all.isEmpty,let loaded=feedLoadedAt["new:"+state.user.id] else { return true }
        return now.timeIntervalSince(loaded) > 15*60
    }
    func resolveMetadata(_ keys: [String]) async {
        guard online,let owner=state?.user.id else { return }
        let missing=Array(Set(keys.filter { !$0.isEmpty && (stories[$0] == nil || stories[$0]?.title == $0) })).sorted()
        await restoreSnapshots(missing)
        for start in stride(from:0,to:missing.count,by:40) {
            guard !Task.isCancelled,state?.user.id == owner else { return }
            if let result=try? await API.shared.get("/api/source/resolve",query:["keys":missing[start..<min(start+40,missing.count)].joined(separator:",")],as:ResolveResponse.self),state?.user.id == owner {
                for story in result.items { remember(story) }
            }
        }
    }
}
func apiComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters:CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-_.~"))) ?? ""
}

extension AppStore {
    func refreshFriendRequests() async {
        guard online,let owner=state?.user.id,UIApplication.shared.applicationState == .active else { return }
        if let value=try? await API.shared.get("/api/friends/requests",as:JSONValue.self),state?.user.id == owner { incomingFriendRequests=Int(value["incomingCount"].number) }
    }
}

extension AppStore {
    func queueChapterOpen(_ payload: ChapterPayload) {
        guard var current=state else { return }
        let event=ReadingOpenEvent(mangaId:payload.item.key,chapter:payload.number,openedAt:milliseconds())
        if current.pendingOpens == nil { current.pendingOpens=[:] }; current.pendingOpens?[event.id]=event
        current.data.lastOpened=LastOpened(mangaId:event.mangaId,chapter:event.chapter)
        if let index=current.data.library.firstIndex(where:{$0.mangaId == event.mangaId}) {
            current.data.library[index].lastReadChapter=event.chapter; current.data.library[index].lastReadAt=event.openedAt
            current.data.library[index].highestReachedChapter=max(current.data.library[index].highestReachedChapter ?? 0,event.chapter)
        } else { current.data.library.append(LibraryEntry(mangaId:event.mangaId,status:"reading",addedAt:event.openedAt,updatedAt:event.openedAt,lastReadAt:event.openedAt,lastReadChapter:event.chapter,highestReachedChapter:event.chapter)) }
        state=current; queueSnapshot(payload.item,chapter:payload.number); persist()
    }
    func queueSnapshot(_ story: Story,chapter: Double? = nil) {
        guard state != nil else { return }
        if state?.pendingSnapshots == nil { state?.pendingSnapshots=[:] }
        let currentChapter=chapter ?? state?.data.library.first(where:{$0.mangaId == story.key})?.lastReadChapter
        state?.pendingSnapshots?[story.key]=WorkSnapshotWrite(story:story,chapter:currentChapter); persist(); scheduleSnapshots()
    }
    @discardableResult
    private func flushReadingOpens(owner: String) async -> Bool {
        let pending=(state?.pendingOpens?.values.map { $0 } ?? []).sorted { $0.openedAt < $1.openedAt }
        var sent = false
        for event in pending.prefix(40) {
            guard state?.user.id == owner,!Task.isCancelled else { return sent }
            do {
                try await API.shared.send("/api/reading/open",value:event)
            } catch where isPermanentRejection(error) {
                // Dropped like a sent event: one invalid event never blocks the queue behind it.
            } catch { if (error as? APIError)?.status == 401 { loginRequired=true }; return sent }
            guard state?.user.id == owner else { return sent }
            sent = true
            if state?.pendingOpens?[event.id] == event { state?.pendingOpens?.removeValue(forKey:event.id); persist() }
        }
        return sent
    }
    private func scheduleSnapshots() {
        guard snapshotSyncTask == nil,online,!loginRequired,let owner=state?.user.id,state?.pendingSnapshots?.isEmpty == false else { return }
        let token=UUID(),generation=API.shared.generation; snapshotSyncID=token
        snapshotSyncTask=Task { [weak self] in
            guard let self else { return }; defer { if self.snapshotSyncID == token { self.snapshotSyncTask=nil; self.snapshotSyncID=nil } }
            let pending=Array((self.state?.pendingSnapshots ?? [:]).values.filter { (self.snapshotRetryAfter[owner+"|"+$0.mangaId] ?? .distantPast) <= Date() }.prefix(4))
            for snapshot in pending {
                guard self.state?.user.id == owner,API.shared.generation == generation,!Task.isCancelled else { return }
                do {
                    let result=try await API.shared.getMutation("/api/work-snapshots",value:snapshot)
                    // The server saved a fresh copy of the cover (missing, changed or
                    // corrected): take its new address now so the phone's copy is replaced.
                    if result["archived"].boolean {
                        await self.restoreSnapshots([snapshot.mangaId])
                        if let story=self.stories[snapshot.mangaId] { await self.cacheCover(story) }
                    }
                    if result["needsCover"].boolean,!snapshot.coverUrl.isEmpty {
                        if let story=self.stories[snapshot.mangaId] { await self.cacheCover(story) }
                        guard self.state?.user.id == owner,API.shared.generation == generation,!Task.isCancelled else { return }
                        // The server archives covers itself; it asks only when it could not.
                        // Send the saved image only if it came from this exact address: an
                        // older image (a source page once showed another story's poster)
                        // must never be archived under the new address.
                        let savedFrom=Disk.read(String.self,owner:owner,name:"covers/"+Disk.hash(snapshot.mangaId)+".json")
                        guard savedFrom == snapshot.coverUrl else { if self.state?.pendingSnapshots?[snapshot.mangaId] == snapshot { self.state?.pendingSnapshots?.removeValue(forKey:snapshot.mangaId); self.persist() }; continue }
                        let file=Disk.file(owner,Disk.coverName(snapshot.mangaId))
                        guard let image=UIImage(contentsOfFile:file.path) else { continue }
                        let scale=min(1,640/max(image.size.width,image.size.height)), format=UIGraphicsImageRendererFormat(); format.scale=1
                        let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
                        let thumbnail=UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
                        guard let data=thumbnail.jpegData(compressionQuality:0.86) else { continue }
                        _=try await API.shared.raw("/api/work-snapshots/cover",query:["key":snapshot.mangaId],method:"PUT",body:data,contentType:"image/jpeg")
                    }
                    guard self.state?.user.id == owner,API.shared.generation == generation,!Task.isCancelled else { return }
                    if self.state?.pendingSnapshots?[snapshot.mangaId] == snapshot { self.state?.pendingSnapshots?.removeValue(forKey:snapshot.mangaId); self.persist() }
                } catch { if (error as? APIError)?.status == 401 { self.loginRequired=true; return }; self.snapshotRetryAfter[owner+"|"+snapshot.mangaId]=Date().addingTimeInterval(300) }
            }
        }
    }
    func restoreSnapshots(_ keys: [String]) async {
        guard online,let owner=state?.user.id,!keys.isEmpty else { return }
        for start in stride(from:0,to:keys.count,by:40) {
            guard let value=try? await API.shared.get("/api/work-snapshots",query:["keys":keys[start..<min(start+40,keys.count)].joined(separator:",")],as:JSONValue.self),state?.user.id == owner else { return }
            for snapshot in value["snapshots"].array {
                let key=snapshot["mangaId"].string; guard !key.isEmpty else { continue }
                let original=snapshot["originalCoverUrl"].string
                var story=stories[key] ?? Story(key:key,source:sourceFromStoryKey(key),slug:String(key.split(separator:":").dropFirst().joined(separator:":")),type:"archived",url:snapshot["sourceUrl"].string,title:snapshot["title"].string,cover:"",genres:[])
                if !snapshot["title"].string.isEmpty { story.title=snapshot["title"].string }
                if !snapshot["coverUrl"].string.isEmpty { story.cover=snapshot["coverUrl"].string }
                else if story.cover.isEmpty { story.cover=original }
                if !original.isEmpty { story.snapshotOriginalCover=original }
                if !snapshot["source"].string.isEmpty { story.source=snapshot["source"].string }
                remember(story)
            }
        }
    }
    func manualReadChapter(_ story: Story,chapter: Double) async {
        await readingCommand(story,chapter:nil,chapters:[chapter],clearWork:false,singleRead:chapter)
    }
    func manualUnreadGroup(_ story: Story,keys: [String]) async {
        guard let owner=state?.user.id else { return }
        for key in Array(Set(keys.isEmpty ? [story.key] : keys)).sorted() {
            guard state?.user.id == owner,!Task.isCancelled else { return }
            var variant=story; variant.key=key; variant.source=sourceFromStoryKey(key)
            await manualUnread(variant)
        }
    }
    func manualRead(_ story: Story,chapters: [Double]) async {
        await readingCommand(story,chapter:nil,chapters:chapters,clearWork:false)
    }
    func manualUnread(_ story: Story,chapter: Double? = nil) async {
        await readingCommand(story,chapter:chapter,chapters:[],clearWork:chapter == nil)
    }
    private func readingCommand(_ story: Story,chapter: Double?,chapters: [Double],clearWork: Bool,singleRead: Double? = nil) async {
        // A second tap while the first is still running is simply ignored.
        guard !readingMutation else { return }
        guard online,!loginRequired,let owner=state?.user.id else { error="تأكد من الاتصال والجلسة ثم أعد المحاولة."; return }
        readingMutation=true; defer { readingMutation=false }
        // A sync in progress finishes first; the tap is carried out after it instead of refused.
        var waited=0
        while syncing,waited<150 { do { try await Task.sleep(for:.milliseconds(200)) } catch { return }; waited+=1 }
        guard state?.user.id == owner else { return }
        guard !syncing else { error="المزامنة تأخرت؛ أعد المحاولة بعد لحظات."; return }
        // The sync it waited for may have ended the session or the connection may have dropped.
        guard online,!loginRequired else { error="تأكد من الاتصال والجلسة ثم أعد المحاولة."; return }
        do {
            // Drain older local events first; an unread command must not be undone by our own queue.
            try await mergeAndPush(owner:owner); await flushReadingOpens(owner:owner)
            if let singleRead { try await API.shared.send("/api/progress",method:"PUT",value:ProgressRecord(mangaId:story.key,chapter:singleRead,percent:100,updatedAt:milliseconds())) }
            else if clearWork { try await API.shared.send("/api/reading/unread-work",value:["mangaId":story.key]) }
            else if let chapter { try await API.shared.send("/api/reading/unread",value:ReadingBulkInput(mangaId:story.key,chapters:[]).unread(chapter)) }
            else {
                let ordered=Array(Set(chapters.filter { $0.isFinite && $0 >= 0 })).sorted()
                for start in stride(from:0,to:ordered.count,by:500) {
                    try await API.shared.send("/api/reading/read-bulk",value:ReadingBulkInput(mangaId:story.key,chapters:Array(ordered[start..<min(start+500,ordered.count)])))
                }
            }
            guard state?.user.id == owner else { return }
            if var current=state {
                let numbers=Set(chapters + (chapter.map { [$0] } ?? []))
                current.discardPendingReading(mangaId:story.key,chapters:clearWork ? nil : numbers)
                state=current
            }
            let remote=try await accountData(owner:owner)
            guard state?.user.id == owner else { return }; merge(remote); state?.newFeed=nil; persist()
            if !clearWork { queueSnapshot(story) }
        } catch {
            report(error)
            if state?.user.id == owner,let remote=try? await accountData(owner:owner),state?.user.id == owner { merge(remote); persist() }
        }
    }
}
private extension ReadingBulkInput {
    func unread(_ chapter: Double) -> [String:JSONValue] { ["mangaId":.string(mangaId),"chapter":.number(chapter)] }
}

// Chapter lists are reused for a few minutes instead of being fetched again on every
// screen (story page, reader, back again); identical requests in flight are shared.
extension AppStore {
    func seriesFresh(_ key: String, owner: String, maxAge: TimeInterval) -> Bool {
        guard let at = seriesFetched[owner+"|"+key], stories[key]?.chapters?.isEmpty == false else { return false }
        return Date().timeIntervalSince1970 - at < maxAge
    }
    func series(_ key: String, maxAge: TimeInterval = 300, force: Bool = false) async throws -> Story {
        guard let owner = state?.user.id else { return try await API.shared.fullSeries(key) }
        if !force, seriesFresh(key,owner:owner,maxAge:maxAge), let saved = stories[key] { return saved }
        let id = owner+"|"+key
        if let running = seriesInFlight[id] { return try await running.value }
        let task = Task { try await API.shared.fullSeries(key) }
        seriesInFlight[id] = task
        defer { if seriesInFlight[id] == task { seriesInFlight[id] = nil } }
        let value = try await task.value
        guard state?.user.id == owner else { throw CancellationError() }
        remember(value)
        let now = Date().timeIntervalSince1970
        seriesFetched[id] = now
        scheduleSeriesSave()
        return stories[key] ?? value
    }
    // Saved once after a burst of fetches (the background library pass makes many), keeping
    // only the 1000 most recent entries.
    private func scheduleSeriesSave() {
        seriesSave?.cancel()
        seriesSave = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(2)) } catch { return }
            guard let self else { return }
            if self.seriesFetched.count > 1200 {
                self.seriesFetched = Dictionary(uniqueKeysWithValues:self.seriesFetched.sorted { $0.value > $1.value }.prefix(1000).map { ($0.key,$0.value) })
            }
            UserDefaults.standard.set(self.seriesFetched,forKey:"rany.seriesFetched")
        }
    }
}

// The account is read with only the progress changed since the last read, so
// a refresh costs a few database rows instead of one per chapter ever read.
// A full read still happens on first use, once a day, and whenever the
// server answers in full (after a deletion, for example).
extension AppStore {
    func accountData(owner: String) async throws -> AccountData {
        let now = Date().timeIntervalSince1970 * 1000
        var since: Double?
        if let synced = state?.dataSyncedAt, let full = state?.dataFullAt, now >= full, now - full < 86_400_000 { since = synced }
        let response = try await API.shared.get("/api/data",query:since.map { ["since":String(Int64($0))] } ?? [:],as:DataResponse.self)
        guard state?.user.id == owner else { throw CancellationError() }
        if let count = response.unreadMessages { unreadMessages = max(0,count) }
        if response.delta == true {
            // A partial answer can only complete a copy that was asked for.
            guard since != nil, let held = state?.data else { state?.dataSyncedAt = nil; state?.dataFullAt = nil; throw APIError(message:"تعذر تحديث المكتبة الآن.",status:0) }
            state?.dataSyncedAt = response.syncedAt
            return held.applyingChanges(response.data)
        }
        state?.dataSyncedAt = response.syncedAt
        state?.dataFullAt = response.syncedAt == nil ? nil : now
        return response.data
    }
}
