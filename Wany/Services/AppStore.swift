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
    var loadingFeed = false
    var feedProgress = ""
    var chromeHidden = false
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
    @ObservationIgnored private var metadataRefreshed: [String: Date] = [:]
    @ObservationIgnored private var storiesSave: Task<Void,Never>?
    @ObservationIgnored private var accountSave: Task<Void,Never>?
    @ObservationIgnored private var storiesOwner: String?
    @ObservationIgnored private var scrollHold = false
    @ObservationIgnored private var navigationHold: Task<Void,Never>?
    init(startServices: Bool = true) {
        guard startServices else { return }
        if let owner = UserDefaults.standard.string(forKey:"lastAccount") {
            state = Disk.read(AccountState.self,owner:owner,name:"account.json")
            accountID = state?.user.id // Observers do not run inside init.
            if state != nil { loadStories(owner); downloads.attach(owner); firstArrival = UserDefaults.standard.bool(forKey:"rany.firstArrival."+owner) }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.online
                self.online = path.status == .satisfied
                self.downloads.online = self.online; self.downloads.onWiFi = path.usesInterfaceType(.wifi)
                self.downloads.updateNetwork()
                if self.online && (wasOffline || self.state?.lastSynced == nil) { await self.refresh() }
            }
        }
        monitor.start(queue:DispatchQueue(label:"Wany.network"))
        Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in await self?.syncProgress() } }
    }
    // Reading progress saves often; encode and write it off the main thread, coalesced.
    func persist() {
        guard let owner = state?.user.id else { return }
        accountSave?.cancel()
        accountSave = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(250)) } catch { return }
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
        if let old = stories[story.key], old.chapterListComplete == true, story.chapterListComplete != true { merged.chapters = old.chapters; merged.chapterListComplete = true; merged.chapterPageCount = old.chapterPageCount }
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
            await refresh()
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
        persistNow(); refreshTask?.cancel(); metadataTask?.cancel(); metadataTask = nil; metadataToken = nil; syncTask?.cancel()
        if online { _ = try? await API.shared.raw("/api/logout",method:"POST") }
        API.shared.clear(); downloads.attach(nil); enteringAccount = false; state = nil; stories = [:]; storiesOwner = nil; storiesSave?.cancel(); engine = nil
        UserDefaults.standard.removeObject(forKey:"lastAccount"); loginRequired = false
    }
    func refresh() async {
        guard online, let owner = state?.user.id, !syncing else { return }
        syncing = true
        // SwiftUI can cancel its refresh task when its view changes. The account owns this sync.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshAccount(owner:owner)
        }
        refreshTask = task
        await task.value
        refreshTask = nil; syncing = false
    }
    private func refreshAccount(owner: String) async {
        do {
            let session = try await API.shared.get("/api/session",as:SessionResponse.self)
            guard state?.user.id == owner else { return }
            guard let user = session.user, user.id == owner else { loginRequired = true; return }
            state?.user = user; loginRequired = false
            try await mergeAndPush(owner:owner)
            let fresh = try await API.shared.get("/api/data",as:DataResponse.self).data
            guard state?.user.id == owner else { return }
            merge(fresh); state?.lastSynced = Date(); persist()
            if let stats = try? await API.shared.get("/api/reading/stats",as:JSONValue.self), state?.user.id == owner { state?.stats = stats["stats"].object; persist() }
            if let profile = try? await API.shared.get("/api/profiles/"+owner,as:JSONValue.self), state?.user.id == owner { state?.profile = profile; persist() }
            cacheLibrary()
        } catch {
            guard !Task.isCancelled, !isRequestCancellation(error), state?.user.id == owner else { return }
            if (error as? APIError)?.status == 401 { loginRequired = true }
            else { self.error = error.localizedDescription }
        }
    }
    private func merge(_ remote: AccountData) {
        guard var current = state else { return }
        current.mergeReadingData(remote); state = current
        libraryRevision += 1
    }
    private func mergeAndPush(owner: String) async throws {
        let remote = try await API.shared.get("/api/data",as:DataResponse.self).data
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
            try await API.shared.send("/api/progress",method:"PUT",value:record)
            guard state?.user.id == owner else { throw CancellationError() }
            // Do not remove a newer local edit made while this request was in flight.
            if state?.pending[record.id] == record { state?.pending.removeValue(forKey:record.id) }
            if state?.completedPending?[record.id] == record { state?.completedPending?.removeValue(forKey:record.id) }
            persist()
        }
    }
    func syncProgress() async {
        guard online, !loginRequired, !syncing, let owner = state?.user.id, (state?.pending.isEmpty == false || state?.completedPending?.isEmpty == false) else { return }
        syncing = true; defer { syncing = false }
        do { try await mergeAndPush(owner:owner); state?.lastSynced = Date(); persist() }
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
            if !current.data.completed.contains(record.id) { current.data.completed.append(record.id) }
            if current.completedPending?[record.id] == nil {
                if current.completedPending == nil { current.completedPending = [:] }
                current.completedPending?[record.id] = record
            }
        }
        state = current; persist()
    }
    func downloadUnread(_ story: Story) async {
        guard online, let owner = state?.user.id, !loginRequired else {
            error = "تحميل الفصول يحتاج اتصالًا وجلسة دخول صالحة"; return
        }
        do {
            let full = try await API.shared.fullSeries(story.key)
            // Refresh website completions, retaining unsynced local completions and partial progress.
            let remote = try await API.shared.get("/api/data",as:DataResponse.self).data
            guard state?.user.id == owner else { return }
            merge(remote); persist(); remember(full)
            guard let current = state else { return }
            let unread = current.unreadChapters(in:full)
            guard !unread.isEmpty else { downloads.notice = "جميع فصول هذه القصة مقروءة؛ لا توجد فصول غير مقروءة للتحميل"; return }
            await downloads.enqueue(full,chapters:unread,unreadOnly:true)
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func toggleFavorite(_ story: Story) async {
        guard let state else { return }
        guard online else { error = "تعديل المفضلة يحتاج اتصالًا؛ تقدم القراءة محفوظ أوفلاين"; return }
        let owner = state.user.id
        do {
            if state.data.favorites.contains(story.key) {
                _ = try await API.shared.raw("/api/favorites/" + story.key.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!,method:"DELETE")
                guard self.state?.user.id == owner else { return }; self.state?.data.favorites.removeAll { $0 == story.key }
            } else {
                try await API.shared.send("/api/favorites",value:["mangaId":story.key])
                guard self.state?.user.id == owner else { return }; self.state?.data.favorites.append(story.key)
            }
            persist(); remember(story); libraryRevision += 1; cacheLibrary()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func setStatus(_ story: Story, status: String) async {
        do { try await API.shared.send("/api/library",method:"PUT",value:["mangaId":story.key,"status":status]); await refresh() } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func cacheLibrary() {
        guard metadataTask == nil, let current = state, online else { return }
        let owner = current.user.id
        let keys = Array(Set(current.data.favorites + current.data.library.map(\.mangaId)))
        let token = UUID(); metadataToken = token
        metadataTask = Task { [weak self] in
            guard let self else { return }; defer { if self.metadataToken == token { self.metadataTask = nil; self.metadataToken = nil } }
            // Resolve lightweight cards first so a slow source never holds up the profile.
            for start in stride(from:0,to:keys.count,by:40) {
                if Task.isCancelled || self.state?.user.id != owner { return }
                let slice = Array(keys[start..<min(start+40,keys.count)])
                if let r = try? await API.shared.get("/api/source/resolve",query:["keys":slice.joined(separator:",")],as:ResolveResponse.self) {
                    guard self.state?.user.id == owner else { return }; for item in r.items { self.remember(item) }
                }
            }
            for key in keys {
                if Task.isCancelled || self.state?.user.id != owner || !self.online { return }
                if let story = self.stories[key] { await self.cacheCover(story) }
                if let updated = self.metadataRefreshed[owner+key], Date().timeIntervalSince(updated) < 1800 { continue }
                if let story = try? await API.shared.fullSeries(key) { guard self.state?.user.id == owner else { return }; self.remember(story); self.metadataRefreshed[owner+key] = Date(); await self.cacheCover(story) }
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
        loadingFeed = true; defer { loadingFeed = false }
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
                let feed = try await Task.detached(priority:.userInitiated) { try JSONDecoder().decode(NewFeed.self,from:result) }.value
                guard state?.user.id == current.user.id else { return }
                state?.newFeed = feed; for r in feed.all { remember(r.item) }
            }
            persist()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}
