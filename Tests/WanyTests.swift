import XCTest
@testable import Wany

final class WanyTests: XCTestCase {
    func story() -> Story { Story(key:"tx:test",source:"teamx",slug:"test",type:"manhwa",url:"https://example.com/story",title:"Test",cover:"",genres:[]) }
    func testDownloadDoesNotCompleteWithMissingImages() {
        let s = story()
        let payload = ChapterPayload(item:s,number:1,title:"1",pages:["a","b"])
        var c = ChapterDownload(chapter:Chapter(number:1,title:"1"),payload:payload,images:[ImageRecord(remote:"a",file:"a",expected:10,bytes:10,done:true),ImageRecord(remote:"b",file:"b")])
        var job = DownloadJob(id:s.key,story:s,chapters:[c],wholeStory:true,chapterListComplete:true)
        XCTAssertFalse(job.complete); XCTAssertNil(job.total); XCTAssertEqual(job.completedChapters,0); XCTAssertEqual(job.remainingChapters,1)
        c.images[1].expected = 20; job.chapters = [c]
        XCTAssertEqual(job.total,30); XCTAssertFalse(job.complete)
        c.images[1].bytes = 20; c.images[1].done = true; job.chapters = [c]
        XCTAssertTrue(job.complete); XCTAssertEqual(job.bytes,30); XCTAssertEqual(job.completedChapters,1)
    }
    func testIncompleteManifestNeverClaimsFullStory() {
        let job = DownloadJob(id:"x",story:story(),chapters:[],wholeStory:true,chapterListComplete:false)
        XCTAssertFalse(job.complete); XCTAssertNil(job.total)
    }
    func testPendingProgressAndResumePositionSurviveRestart() throws {
        let owner = "test-"+UUID().uuidString
        defer { try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        let record = ProgressRecord(mangaId:"tx:test",chapter:12.5,percent:62.4,updatedAt:12345)
        var state = AccountState(user:Account(id:owner,name:"Tester",username:"test"))
        state.pending[record.id] = record; state.positions[record.id] = 9
        try Disk.save(state,owner:owner,name:"account.json")
        let loaded = try XCTUnwrap(Disk.read(AccountState.self,owner:owner,name:"account.json"))
        XCTAssertEqual(loaded.pending[record.id],record); XCTAssertEqual(loaded.positions[record.id],9)
        XCTAssertNil(Disk.read(AccountState.self,owner:owner+"other",name:"account.json"))
        XCTAssertEqual(record.id,"tx:test:12.5")
    }
    func testDownloadManifestRoundTripPreservesFailuresAndCompletedFiles() throws {
        let owner = "test-"+UUID().uuidString
        defer { try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        let job = DownloadJob(id:"tx:test",story:story(),chapters:[ChapterDownload(chapter:Chapter(number:1,title:"1"),images:[ImageRecord(remote:"url",file:"one",expected:100,bytes:100,done:true),ImageRecord(remote:"url2",file:"two",failure:"offline",attempts:3)])],wholeStory:true,chapterListComplete:true,paused:true)
        try Disk.save([job],owner:owner,name:"downloads.json")
        let restored = try XCTUnwrap(Disk.read([DownloadJob].self,owner:owner,name:"downloads.json")?.first)
        XCTAssertTrue(restored.paused); XCTAssertTrue(restored.chapters[0].images[0].done); XCTAssertEqual(restored.chapters[0].images[1].attempts,3)
    }
    @MainActor func testAPIUsesWanyOriginAndCorrectImageReferer() throws {
        let request = try API.shared.imageRequest(source:"teamx",url:"https://example.com/thumbnail_a.webp",referer:"https://example.com/chapter")
        let c = try XCTUnwrap(URLComponents(url:request.url!,resolvingAgainstBaseURL:false))
        XCTAssertEqual(c.host,"wany.site"); XCTAssertEqual(c.path,"/api/source/image")
        XCTAssertEqual(c.queryItems?.first(where:{$0.name == "referer"})?.value,"https://example.com/chapter")
        XCTAssertEqual(c.queryItems?.first(where:{$0.name == "url"})?.value,"https://example.com/a.webp")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),"https://wany.site")
    }

    func testNewerWebsiteProgressClearsStaleLocalPage() {
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        let old = ProgressRecord(mangaId:"tx:a",chapter:2,percent:10,updatedAt:1000)
        state.data.progress[old.id] = old; state.positions[old.id] = 1
        var remote = AccountData(); remote.progress[old.id] = ProgressRecord(mangaId:"tx:a",chapter:2,percent:80,updatedAt:3000)
        state.mergeReadingData(remote)
        XCTAssertNil(state.positions[old.id]); XCTAssertEqual(state.data.progress[old.id]?.percent,80)
    }
    func testOfflineCompletionSurvivesRereadAndRemoteMerge() throws {
        let owner = "test-"+UUID().uuidString
        defer { try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        var state = AccountState(user:Account(id:owner,name:"U",username:"u"))
        let completed = ProgressRecord(mangaId:"tx:a",chapter:2,percent:100,updatedAt:1000)
        let reread = ProgressRecord(mangaId:"tx:a",chapter:2,percent:20,updatedAt:3000)
        state.completedPending = [completed.id:completed]; state.pending[reread.id] = reread; state.data.completed = [completed.id]
        state.mergeReadingData(AccountData())
        XCTAssertEqual(state.data.progress[reread.id]?.percent,20); XCTAssertTrue(state.data.completed.contains(completed.id)); XCTAssertEqual(state.data.lastOpened?.chapter,2)
        try Disk.save(state,owner:owner,name:"account.json")
        let saved = try XCTUnwrap(Disk.read(AccountState.self,owner:owner,name:"account.json"))
        XCTAssertEqual(saved.completedPending?[completed.id]?.percent,100); XCTAssertEqual(saved.pending[reread.id]?.percent,20)
    }
    @MainActor func testRetryInvalidatesOnlyDamagedPage() throws {
        let downloads = Downloads.shared; let previousOwner = downloads.owner; let wasOnline = downloads.online
        let owner = "test-"+UUID().uuidString; downloads.online = false; downloads.attach(owner)
        defer { downloads.attach(previousOwner); downloads.online = wasOnline; try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        let payload = ChapterPayload(item:story(),number:1,title:"1",pages:["a","b"])
        for i in 0..<2 {
            let file = Disk.file(owner,Disk.imageName(payload.id,i)); try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true); try Data([1,2,3]).write(to:file)
        }
        downloads.usePayload(payload)
        XCTAssertEqual(downloads.jobs.first?.completedChapters,1)
        downloads.invalidatePage(payload,index:1)
        XCTAssertNotNil(downloads.pageURL(payload,index:0)); XCTAssertNil(downloads.pageURL(payload,index:1)); XCTAssertEqual(downloads.jobs.first?.completedChapters,0)
        XCTAssertTrue(downloads.jobs.first?.chapters.first?.images.first?.done == true)
    }

    func testUnreadSelectionKeepsPartialAndSkippedChapters() {
        var work = story(); work.chapters = [1,2,2.5,3,4,5].map { Chapter(number:$0,title:chapterNumber($0)) }
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        state.data.completed = [work.key+":1"]
        let atThreshold = ProgressRecord(mangaId:work.key,chapter:2,percent:98,updatedAt:1000)
        state.data.progress[atThreshold.id] = atThreshold
        let partial = ProgressRecord(mangaId:work.key,chapter:2.5,percent:50,updatedAt:2000)
        state.data.progress[partial.id] = partial
        let pending = ProgressRecord(mangaId:work.key,chapter:4,percent:100,updatedAt:3000)
        state.pending[pending.id] = pending
        let finishedThenReread = ProgressRecord(mangaId:work.key,chapter:5,percent:100,updatedAt:4000)
        state.completedPending = [finishedThenReread.id:finishedThenReread]
        state.pending[finishedThenReread.id] = ProgressRecord(mangaId:work.key,chapter:5,percent:20,updatedAt:5000)
        state.data.library = [LibraryEntry(mangaId:work.key,status:"reading",addedAt:1,updatedAt:1,highestReachedChapter:5)]
        XCTAssertEqual(state.unreadChapters(in:work).map(\.number),[2.5,3])
    }
    func testUnreadSelectionCombinesWebsiteAndOfflineCompletions() {
        var work = story(); work.chapters = [1,2,3].map { Chapter(number:Double($0),title:String($0)) }
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        let local = ProgressRecord(mangaId:work.key,chapter:1,percent:100,updatedAt:2000)
        state.completedPending = [local.id:local]; state.pending[local.id] = local
        var remote = AccountData(); remote.completed = [work.key+":2"]
        state.mergeReadingData(remote)
        XCTAssertEqual(state.unreadChapters(in:work).map(\.number),[3])
        state.data.completed.append(work.key+":3")
        XCTAssertTrue(state.unreadChapters(in:work).isEmpty)
    }
    func testUnreadQueueCountsOnlyRequestedChaptersAndPreservesCachedPages() {
        let work = story()
        let readPayload = ChapterPayload(item:work,number:1,title:"1",pages:["read"])
        let unreadPayload = ChapterPayload(item:work,number:2,title:"2",pages:["unread"])
        let read = ChapterDownload(chapter:Chapter(number:1,title:"1"),payload:readPayload,images:[ImageRecord(remote:"read",file:"read",bytes:10,done:true)])
        var unread = ChapterDownload(chapter:Chapter(number:2,title:"2"),payload:unreadPayload,images:[ImageRecord(remote:"unread",file:"unread",expected:20)])
        var job = DownloadJob(id:work.key,story:work,chapters:[read,unread],wholeStory:false,chapterListComplete:true,activeChapterIDs:["2"],selectionMode:"unread")
        XCTAssertFalse(job.includes("1")); XCTAssertTrue(job.includes("2"))
        XCTAssertEqual(job.completedChapters,0); XCTAssertEqual(job.remainingChapters,1)
        XCTAssertEqual(job.bytes,10); XCTAssertEqual(job.downloadedBytes,0); XCTAssertEqual(job.total,20)
        unread.images[0].bytes = 20; unread.images[0].done = true; job.chapters[1] = unread
        XCTAssertTrue(job.complete); XCTAssertEqual(job.completedChapters,1)
        XCTAssertEqual(job.bytes,30); XCTAssertEqual(job.downloadedBytes,20); XCTAssertTrue(job.chapters[0].complete)
    }

    func testLegacyDownloadManifestStillSelectsEveryChapter() throws {
        let job = DownloadJob(id:"tx:test",story:story(),chapters:[ChapterDownload(chapter:Chapter(number:1,title:"1")),ChapterDownload(chapter:Chapter(number:2,title:"2"))],wholeStory:true,chapterListComplete:true)
        let encoded = try JSONEncoder().encode(job)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        legacy.removeValue(forKey:"activeChapterIDs"); legacy.removeValue(forKey:"selectionMode")
        let restored = try JSONDecoder().decode(DownloadJob.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(restored.activeChapterIDs); XCTAssertNil(restored.selectionMode)
        XCTAssertEqual(restored.requestedChapters.count,2); XCTAssertTrue(restored.includes("1")); XCTAssertTrue(restored.includes("2"))
    }
}
