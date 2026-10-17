import Foundation
import Combine
import Network
import UIKit

@MainActor final class AppStore: ObservableObject {
    @Published var enteringAccount = false
    @Published var firstArrival = false
    @Published var incomingFriendRequests = 0
    @Published var state: AccountState?
    @Published var stories: [String:Story] = [:]
    @Published var online = true
    @Published var localSaveFailed = false
    @Published var syncing = false
    @Published var loginRequired = false
    @Published var error: String?
    @Published var loadingFeed = false
    @Published var feedProgress = ""
    @Published var chromeHidden = false
    @Published var readerActive = false
    @Published var bottomBarHeight: CGFloat = 90
    @Published var mainPageVisible = false
    let downloads = Downloads.shared
    private let monitor = NWPathMonitor()
    private var metadataTask: Task<Void,Never>?
    private var metadataToken: UUID?
    private var syncTask: Task<Void,Never>?
    private var refreshTask: Task<Void,Never>?
    private var engine: FeedEngine?
    private var snapshotRetryAfter: [String:Date] = [:]
    private var snapshotSyncID: UUID?
    private var snapshotSyncTask: Task<Void,Never>?
    @Published var readingMutation = false
    private var coverRequests: Set<String> = []
    private var metadataRefreshed: [String: Date] = [:]
    init(startServices: Bool = true) {
        guard startServices else { return }
        if let owner = UserDefaults.standard.string(forKey:"lastAccount") {
            state = Disk.read(AccountState.self,owner:owner,name:"account.json")
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
        Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in await self?.syncProgress(); await self?.refreshFriendRequests() } }
    }
    func persist() {
        guard let state else { return }
        do { try Disk.save(state,owner:state.user.id,name:"account.json"); if localSaveFailed { localSaveFailed = false } } catch { localSaveFailed = true; self.error = "تعذر حفظ التقدم على الجهاز: " + error.localizedDescription }
    }
    private func loadStories(_ owner: String) { stories = Disk.read([String:Story].self,owner:owner,name:"stories.json") ?? [:] }
    func remember(_ story: Story) {
        guard let owner = state?.user.id else { return }
        // List cards must not overwrite a complete offline chapter archive.
        var merged = story
        if let old=stories[story.key],old.cover.hasPrefix("/api/work-snapshots/"),!story.cover.hasPrefix("/api/work-snapshots/") {
            merged.snapshotOriginalCover=story.cover; merged.cover=old.cover
        }
        if let old = stories[story.key], old.chapterListComplete == true, story.chapterListComplete != true { merged.chapters = old.chapters; merged.chapterListComplete = true; merged.chapterPageCount = old.chapterPageCount }
        stories[story.key] = merged
        do { try Disk.save(stories,owner:owner,name:"stories.json") } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
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
        persist(); refreshTask?.cancel(); metadataTask?.cancel(); metadataTask = nil; metadataToken = nil; syncTask?.cancel(); snapshotSyncTask?.cancel(); snapshotSyncTask=nil; snapshotSyncID=nil; snapshotRetryAfter=[:]
        if online { _ = try? await API.shared.raw("/api/logout",method:"POST") }
        incomingFriendRequests=0; API.shared.clear(); downloads.attach(nil); enteringAccount = false; state = nil; stories = [:]; engine = nil
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
        persist(); refreshTask?.cancel(); metadataTask?.cancel(); metadataTask=nil; metadataToken=nil; syncTask?.cancel(); snapshotSyncTask?.cancel(); snapshotSyncTask=nil; snapshotSyncID=nil; snapshotRetryAfter=[:]
        incomingFriendRequests=0; API.shared.clear(); downloads.attach(nil); enteringAccount=false; state=nil; stories=[:]; engine=nil
        UserDefaults.standard.removeObject(forKey:"lastAccount"); loginRequired=false
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
            await flushReadingOpens(owner:owner); scheduleSnapshots()
            let fresh = try await API.shared.get("/api/data",as:DataResponse.self).data
            guard state?.user.id == owner else { return }
            merge(fresh); state?.lastSynced = Date(); persist()
            if let stats = try? await API.shared.get("/api/reading/stats",as:JSONValue.self), state?.user.id == owner { state?.stats = stats["stats"].object; persist() }
            if let profile = try? await API.shared.get("/api/profiles/"+owner,as:JSONValue.self), state?.user.id == owner { state?.profile = profile; incomingFriendRequests=Int(profile["profile"]["pendingFriendRequests"].number); persist() }
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
        guard online, !loginRequired, !syncing, !readingMutation, let owner = state?.user.id, (state?.pending.isEmpty == false || state?.completedPending?.isEmpty == false || state?.pendingOpens?.isEmpty == false || state?.pendingSnapshots?.isEmpty == false) else { return }
        syncing = true; defer { syncing = false }
        do { try await mergeAndPush(owner:owner); await flushReadingOpens(owner:owner); scheduleSnapshots(); state?.lastSynced = Date(); persist() }
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
            persist(); remember(story); queueSnapshot(story); cacheLibrary()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func setStatus(_ story: Story, status: String) async {
        do { try await API.shared.send("/api/library",method:"PUT",value:["mangaId":story.key,"status":status]); queueSnapshot(story); await refresh() } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
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
                await self.restoreSnapshots(slice)
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
            guard state?.user.id == owner, (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data:data) != nil else { return }
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            try Disk.save(story.cover,owner:owner,name:versionName)
            objectWillChange.send()
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
            if kind == "fyp" { state?.fyp = try JSONDecoder().decode(FypSnapshot.self,from:result).recommendations; for r in state?.fyp ?? [] { remember(r.item) } }
            else { state?.newFeed = try JSONDecoder().decode(NewFeed.self,from:result); for r in state?.newFeed?.all ?? [] { remember(r.item) } }
            persist()
        } catch { if !Task.isCancelled, !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
}

extension AppStore {
    func resolveMetadata(_ keys: [String]) async {
        guard online,let owner=state?.user.id else { return }
        let missing=Array(Set(keys.filter { !$0.isEmpty && stories[$0] == nil })).sorted()
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
    private func flushReadingOpens(owner: String) async {
        let pending=(state?.pendingOpens?.values.map { $0 } ?? []).sorted { $0.openedAt < $1.openedAt }
        for event in pending.prefix(40) {
            guard state?.user.id == owner,!Task.isCancelled else { return }
            do {
                try await API.shared.send("/api/reading/open",value:event)
                guard state?.user.id == owner else { return }
                if state?.pendingOpens?[event.id] == event { state?.pendingOpens?.removeValue(forKey:event.id); persist() }
            } catch { if (error as? APIError)?.status == 401 { loginRequired=true }; return }
        }
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
                    if result["needsCover"].boolean,!snapshot.coverUrl.isEmpty {
                        if let story=self.stories[snapshot.mangaId] { await self.cacheCover(story) }
                        guard self.state?.user.id == owner,API.shared.generation == generation,!Task.isCancelled else { return }
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
        for key in Array(Set(keys.isEmpty ? [story.key] : keys)).sorted() {
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
        guard online,!loginRequired,!readingMutation,!syncing,let owner=state?.user.id else { error="انتظر اكتمال المزامنة وتأكد من الاتصال والجلسة ثم أعد المحاولة."; return }
        readingMutation=true; defer { readingMutation=false }
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
            let remote=try await API.shared.get("/api/data",as:DataResponse.self).data
            guard state?.user.id == owner else { return }; merge(remote); persist()
            if !clearWork { queueSnapshot(story) }
        } catch {
            report(error)
            if state?.user.id == owner,let remote=try? await API.shared.get("/api/data",as:DataResponse.self).data,state?.user.id == owner { merge(remote); persist() }
        }
    }
}
private extension ReadingBulkInput {
    func unread(_ chapter: Double) -> [String:JSONValue] { ["mangaId":.string(mangaId),"chapter":.number(chapter)] }
}
