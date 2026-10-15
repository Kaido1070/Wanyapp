import XCTest
import UIKit
@testable import Wany

final class WanyTests: XCTestCase {
    func testPublicFriendIdentityKeepsAvatarAndBadge() {
        let user: JSONValue = .object(["id":.string("friend"),"name":.string("Friend"),"username":.string("reader"),"avatarId":.string("avatar-12"),"badgeType":.string("verified")])
        XCTAssertEqual(user.publicAccount?.avatarId,"avatar-12")
        XCTAssertEqual(user.publicAccount?.badgeType,"verified")
        XCTAssertEqual(user.publicAccount?.username,"reader")
        XCTAssertNil(JSONValue.null.publicAccount)
        XCTAssertNil(JSONValue.object(["id":.string("friend")]).publicAccount?.avatarId)
    }
    @MainActor func testNativeChapterZoomNeverRelayoutsPagesDuringRepeatedZoom() {
        let scroll = ChapterScroll(frame:CGRect(x:0,y:0,width:300,height:600))
        scroll.configure(id:"chapter",urls:Array(repeating:nil,count:30),ratios:Dictionary(uniqueKeysWithValues:(0..<30).map { ($0,CGFloat(2)) }),initialPage:10,nextTitle:nil,online:false)
        scroll.layoutIfNeeded()
        let frames = scroll.tiles.map(\.frame), size = scroll.canvas.bounds.size, layouts = scroll.geometryUpdates
        XCTAssertTrue(scroll.viewForZooming(in:scroll) === scroll.canvas)
        XCTAssertTrue(scroll.pinchGestureRecognizer?.isEnabled == true)
        XCTAssertEqual(scroll.minimumZoomScale,1); XCTAssertEqual(scroll.maximumZoomScale,4)
        for step in 0..<120 {
            let scale = CGFloat(step < 60 ? 60+step : 180-step)/60
            scroll.setZoomScale(scale,animated:false); scroll.layoutIfNeeded()
            XCTAssertEqual(scroll.tiles.map(\.frame),frames)
            XCTAssertEqual(scroll.canvas.bounds.size,size)
            XCTAssertEqual(scroll.geometryUpdates,layouts)
        }
        scroll.stop(); scroll.delegate = nil
    }
    @MainActor func testDownloadAndHeaderUpdatesPreserveNativeZoomAndOffset() {
        let scroll = ChapterScroll(frame:CGRect(x:0,y:0,width:300,height:600))
        let ratios = Dictionary(uniqueKeysWithValues:(0..<8).map { ($0,CGFloat(3)) })
        scroll.configure(id:"chapter",urls:Array(repeating:nil,count:8),ratios:ratios,initialPage:3,nextTitle:nil,online:false); scroll.layoutIfNeeded()
        scroll.setZoomScale(2.5,animated:false); scroll.contentOffset = CGPoint(x:250,y:7000)
        let offset = scroll.contentOffset, layouts = scroll.geometryUpdates
        for _ in 0..<30 {
            scroll.configure(id:"chapter",urls:Array(repeating:nil,count:8),ratios:ratios,initialPage:0,nextTitle:"الفصل التالي",online:true)
            scroll.layoutIfNeeded()
            XCTAssertEqual(scroll.zoomScale,2.5); XCTAssertEqual(scroll.contentOffset,offset)
            XCTAssertEqual(scroll.geometryUpdates,layouts)
        }
        scroll.stop(); scroll.delegate = nil
    }
    @MainActor func testNativeChapterRestoresOnceAndNewChapterResetsZoom() {
        let scroll = ChapterScroll(frame:CGRect(x:0,y:0,width:300,height:600))
        let ratios: [Int:CGFloat] = [0:2,1:3,2:1.5]
        scroll.configure(id:"one",urls:[nil,nil,nil],ratios:ratios,initialPage:2,nextTitle:nil,online:false); scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.contentOffset.y,1500,accuracy:0.01)
        scroll.setZoomScale(2,animated:false)
        scroll.configure(id:"two",urls:[nil,nil,nil],ratios:ratios,initialPage:1,nextTitle:nil,online:false); scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale,1); XCTAssertEqual(scroll.contentOffset.y,600,accuracy:0.01)
        XCTAssertEqual(scroll.tiles.count,3)
        scroll.stop(); scroll.delegate = nil
    }
    @MainActor func testReaderRotationKeepsPageAndZoom() {
        let scroll = ChapterScroll(frame:CGRect(x:0,y:0,width:300,height:600))
        scroll.configure(id:"chapter",urls:[nil,nil,nil,nil],ratios:[0:3,1:3,2:3,3:3],initialPage:1,nextTitle:nil,online:false); scroll.layoutIfNeeded()
        scroll.setZoomScale(2,animated:false); scroll.contentOffset = CGPoint(x:100,y:2100)
        scroll.frame.size = CGSize(width:400,height:600); scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale,2)
        XCTAssertEqual(scroll.contentOffset.y,2800,accuracy:1)
        scroll.stop(); scroll.delegate = nil
    }

    func testReaderVisibilityTracksPagesWithoutSettingAScrollAnchor() {
        let frames = [0:CGRect(x:0,y:-900,width:300,height:800),1:CGRect(x:0,y:-100,width:300,height:600),2:CGRect(x:0,y:500,width:300,height:700)]
        XCTAssertEqual(ReaderPosition.visiblePage(frames:frames),1)
        XCTAssertEqual(ReaderPosition.visiblePage(frames:[2:CGRect(x:0,y:20,width:300,height:600)]),2)
        XCTAssertNil(ReaderPosition.visiblePage(frames:[:]))
    }

    func testDiscoverCarouselOnlyUsesLandscapeArtwork() {
        XCTAssertTrue(DiscoverResults.isWideCover(width:1200,height:500))
        XCTAssertFalse(DiscoverResults.isWideCover(width:400,height:600))
        XCTAssertFalse(DiscoverResults.isWideCover(width:600,height:600))
        XCTAssertFalse(DiscoverResults.isWideCover(width:1200,height:0))
        XCTAssertFalse(DiscoverResults.isWideCover(width:.infinity,height:600))
    }

    @MainActor func testDownloadQualityIsSentToServerWithoutChangingSourceURL() throws {
        let remote = "https://olympustaff.com/wp-content/uploads/chapter/page.jpg"
        let request = try API.shared.imageRequest(source:"teamx",url:remote,referer:"https://olympustaff.com/series/test",quality:.high)
        let query = URLComponents(url:try XCTUnwrap(request.url),resolvingAgainstBaseURL:false)?.queryItems ?? []
        XCTAssertEqual(query.first(where:{$0.name == "quality"})?.value,"high")
        XCTAssertEqual(query.first(where:{$0.name == "url"})?.value,remote)
        XCTAssertEqual(query.first(where:{$0.name == "referer"})?.value,"https://olympustaff.com/series/test")
        let cover = try API.shared.imageRequest(source:"teamx",url:remote)
        XCTAssertFalse((URLComponents(url:try XCTUnwrap(cover.url),resolvingAgainstBaseURL:false)?.queryItems ?? []).contains(where:{$0.name == "quality"}))
    }
    func testLegacyImageRecordsRemainReadableAndOptimizationFlagPersists() throws {
        let old = Data(#"{"remote":"url","file":"image","bytes":5,"done":true,"attempts":0}"#.utf8)
        var image = try JSONDecoder().decode(ImageRecord.self,from:old)
        XCTAssertNil(image.edgeOptimized)
        image.edgeOptimized = true
        XCTAssertEqual(try JSONDecoder().decode(ImageRecord.self,from:JSONEncoder().encode(image)).edgeOptimized,true)
    }

    func testBottomBarRequiresDoubleUpwardTravelAndReaderRequiresTriple() {
        var bottom = ReaderScrollDirection(revealDistance:192)
        var reader = ReaderScrollDirection(revealDistance:288)
        for offset in [CGFloat(1000),1020] {
            _ = bottom.update(offset:offset,userScrolling:true)
            _ = reader.update(offset:offset,userScrolling:true)
        }
        XCTAssertNil(bottom.update(offset:924,userScrolling:true))
        XCTAssertNil(reader.update(offset:924,userScrolling:true))
        XCTAssertEqual(bottom.update(offset:828,userScrolling:true),true)
        XCTAssertNil(reader.update(offset:828,userScrolling:true))
        XCTAssertEqual(reader.update(offset:732,userScrolling:true),true)
    }
    func testStoryStatusIsLocalizedWithoutChangingUnknownLabels() {
        XCTAssertEqual(storyStatusLabel("ongoing"),"مستمر")
        XCTAssertEqual(storyStatusLabel(" Ongoing "),"مستمر")
        XCTAssertEqual(storyStatusLabel("completed"),"مكتمل")
        XCTAssertEqual(storyStatusLabel("مستمر"),"مستمر")
    }
    func testAllSourcesShowsAvailableResultsInBalancedOrder() {
        var first = story(); first.key = "tx:one"
        var second = story(); second.key = "tx:two"
        var other = story(); other.key = "az:one"; other.source = "azora"
        let result = DiscoverResults.combine(["teamx":[first,second],"azora":[other]],order:["teamx","3asq","azora"])
        XCTAssertEqual(result.map(\.key),["tx:one","az:one","tx:two"])
        XCTAssertTrue(DiscoverResults.combine([:],order:sources).isEmpty)
    }
    func testExplorePaginationRemovesRepeatsWithinAndBetweenPages() {
        var first = story(); first.key = "tx:one"
        var second = story(); second.key = "tx:two"
        XCTAssertEqual(DiscoverResults.append([first,second,second],to:[first]).map(\.key),["tx:one","tx:two"])
    }
    @MainActor func testScrollObserverReceivesActualScrollOffset() async throws {
        let window = UIWindow(frame:UIScreen.main.bounds)
        let controller = UIViewController(); window.rootViewController = controller
        let scroll = UIScrollView(frame:window.bounds); scroll.contentSize = CGSize(width:window.bounds.width,height:3000)
        controller.view.addSubview(scroll)
        let content = UIView(frame:CGRect(x:0,y:0,width:window.bounds.width,height:3000)); scroll.addSubview(content)
        let probe = ReaderScrollObserver.Probe(frame:content.bounds); content.addSubview(probe)
        let received = expectation(description:"Actual offset is observed")
        probe.onScroll = { offset,_ in if offset >= 250 { received.fulfill() } }
        window.makeKeyAndVisible()
        defer { probe.observation = nil; window.isHidden = true }
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertTrue(probe.observed === scroll)
        scroll.setContentOffset(CGPoint(x:0,y:300),animated:false)
        await fulfillment(of:[received],timeout:2)
    }
    @MainActor func testTemporaryReadingExpiresWithoutTouchingSavedChaptersOrProgress() throws {
        let downloads = Downloads.shared; let oldOwner = downloads.owner; let online = downloads.online
        let owner = "test-"+UUID().uuidString; downloads.online = false
        defer { downloads.attach(oldOwner); downloads.online = online; try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        let work = story()
        let saved = ChapterPayload(item:work,number:1,title:"1",pages:["a"])
        let temporary = ChapterPayload(item:work,number:2,title:"2",pages:["b"])
        for payload in [saved,temporary] {
            let file = Disk.file(owner,Disk.imageName(payload.id,0))
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data([1,2,3]).write(to:file)
            try Disk.save(payload,owner:owner,name:Disk.chapterName(payload.id))
        }
        let chapters = [ChapterDownload(chapter:Chapter(number:1,title:"1"),payload:saved,images:[ImageRecord(remote:"a",file:Disk.imageName(saved.id,0),bytes:3,done:true)]),ChapterDownload(chapter:Chapter(number:2,title:"2"),payload:temporary,images:[ImageRecord(remote:"b",file:Disk.imageName(temporary.id,0),bytes:3,done:true)],keepOffline:false,expiresAt:Date().addingTimeInterval(1000))]
        try Disk.save([DownloadJob(id:work.key,story:work,chapters:chapters,wholeStory:false,chapterListComplete:true)],owner:owner,name:"downloads.json")
        var state = AccountState(user:Account(id:owner,name:"U",username:"u")); state.positions[temporary.id] = 4
        try Disk.save(state,owner:owner,name:"account.json")
        downloads.attach(owner); downloads.usePayload(temporary)
        downloads.cleanTemporary(now:Date().addingTimeInterval(2000))
        XCTAssertNotNil(downloads.pageURL(temporary,index:0)) // Active chapter stays available.
        downloads.leaveChapter(temporary.id)
        downloads.cleanTemporary(now:Date().addingTimeInterval(120))
        XCTAssertNotNil(downloads.pageURL(temporary,index:0))
        downloads.cleanTemporary(now:Date().addingTimeInterval(200))
        XCTAssertNil(downloads.pageURL(temporary,index:0)); XCTAssertNotNil(downloads.pageURL(saved,index:0))
        XCTAssertNil(Disk.read(ChapterPayload.self,owner:owner,name:Disk.chapterName(temporary.id)))
        XCTAssertEqual(Disk.read(AccountState.self,owner:owner,name:"account.json")?.positions[temporary.id],4)
        XCTAssertEqual(downloads.savedJobs.first?.chapters.count,1)
    }
    @MainActor func testExplicitDownloadPromotesTemporaryFilesWithoutRedownloading() async throws {
        let downloads = Downloads.shared; let oldOwner = downloads.owner; let online = downloads.online
        let owner = "test-"+UUID().uuidString; downloads.online = false; downloads.attach(owner)
        defer { downloads.attach(oldOwner); downloads.online = online; try? FileManager.default.removeItem(at:Disk.folder(owner)) }
        let work = story(); let chapter = Chapter(number:1,title:"1")
        let payload = ChapterPayload(item:work,number:1,title:"1",pages:["a"])
        let file = Disk.file(owner,Disk.imageName(payload.id,0))
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true); try Data([1,2,3]).write(to:file)
        downloads.usePayload(payload); XCTAssertTrue(downloads.savedJobs.isEmpty)
        await downloads.enqueue(work,chapters:[chapter])
        downloads.leaveChapter(payload.id); downloads.cleanTemporary(now:Date().addingTimeInterval(1000),all:true)
        XCTAssertTrue(downloads.savedJobs.first?.complete == true); XCTAssertNotNil(downloads.pageURL(payload,index:0))
        XCTAssertEqual(downloads.savedJobs.first?.bytes,3)
    }
    func testTemporaryImagesDoNotInflateDownloadCounters() {
        let work = story(); let payload = ChapterPayload(item:work,number:1,title:"1",pages:["a"])
        let temp = ChapterDownload(chapter:Chapter(number:1,title:"1"),payload:payload,images:[ImageRecord(remote:"a",file:"a",bytes:500,done:true)],keepOffline:false)
        let job = DownloadJob(id:work.key,story:work,chapters:[temp],wholeStory:false,chapterListComplete:true)
        XCTAssertEqual(job.bytes,0); XCTAssertEqual(job.completedChapters,0); XCTAssertFalse(job.complete)
    }
    func testCompressionReducesLargeJPEGAndPreservesReadableDimensions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        defer { try? FileManager.default.removeItem(at:url) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:2000,height:3000),format:format)
        let image = renderer.image { context in UIColor.white.setFill(); context.fill(CGRect(x:0,y:0,width:2000,height:3000)); UIColor.black.setFill(); context.fill(CGRect(x:100,y:100,width:1800,height:50)) }
        try XCTUnwrap(image.jpegData(compressionQuality:1)).write(to:url)
        let before = Int64(try url.resourceValues(forKeys:[.fileSizeKey]).fileSize!)
        let after = try ImageStorage.compact(url,quality:.balanced)
        XCTAssertLessThan(after,before)
        let decoded = try XCTUnwrap(UIImage(contentsOfFile:url.path))
        XCTAssertEqual(decoded.size.width,1440,accuracy:1); XCTAssertEqual(decoded.size.height/decoded.size.width,1.5,accuracy:0.01)
        XCTAssertEqual(try ImageStorage.compact(url,quality:.original),after)
    }
    func testCancellationIsSilentButRealNetworkErrorsAreNot() {
        XCTAssertTrue(isRequestCancellation(CancellationError()))
        XCTAssertTrue(isRequestCancellation(URLError(.cancelled)))
        XCTAssertFalse(isRequestCancellation(URLError(.timedOut)))
        XCTAssertFalse(isRequestCancellation(APIError(message:"cancelled",status:500)))
    }
    func testStoryProgressCountsFractionalChaptersAndSkippedGaps() throws {
        var work = story(); work.chapterListComplete = true
        work.chapters = [1,2,2.5,10].map { Chapter(number:$0,title:chapterNumber($0)) }
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        state.data.completed = [work.key+":1",work.key+":1"]
        let partial = ProgressRecord(mangaId:work.key,chapter:10,percent:50,updatedAt:2000)
        state.pending[partial.id] = partial
        let summary = state.readingSummary(for:work)
        XCTAssertEqual(summary.chapter,10); XCTAssertEqual(summary.completedCount,1)
        XCTAssertEqual(try XCTUnwrap(summary.percent),37.5,accuracy:0.001)
    }
    func testOfflineCompletionAndRereadKeepStoryProgress() throws {
        var work = story(); work.declaredChapterCount = 2
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        let done = ProgressRecord(mangaId:work.key,chapter:1,percent:100,updatedAt:1000)
        state.completedPending = [done.id:done]
        state.pending[done.id] = ProgressRecord(mangaId:work.key,chapter:1,percent:20,updatedAt:2000)
        let summary = state.readingSummary(for:work)
        XCTAssertEqual(summary.chapter,1); XCTAssertEqual(summary.completedCount,1)
        XCTAssertEqual(try XCTUnwrap(summary.percent),50,accuracy:0.001)
    }
    func testStoryProgressUsesLatestPositionAndIgnoresOtherStories() throws {
        var work = story(); work.declaredChapterCount = 10
        var state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        state.data.library = [LibraryEntry(mangaId:work.key,status:"reading",addedAt:1,updatedAt:1,lastReadAt:3000,lastReadChapter:2,highestReachedChapter:9)]
        let older = ProgressRecord(mangaId:work.key,chapter:9,percent:100,updatedAt:1000)
        state.data.progress[older.id] = older
        state.data.completed = ["tx:other:1"]
        XCTAssertEqual(state.readingSummary(for:work).chapter,2)
        XCTAssertEqual(try XCTUnwrap(state.readingSummary(for:work).percent),10,accuracy:0.001)
        let local = ProgressRecord(mangaId:work.key,chapter:3,percent:50,updatedAt:4000)
        state.pending[local.id] = local
        XCTAssertEqual(state.readingSummary(for:work).chapter,3)
        XCTAssertEqual(try XCTUnwrap(state.readingSummary(for:work).percent),15,accuracy:0.001)
    }
    func testStoryProgressDoesNotGuessTotalFromLatestChapterNumber() {
        var work = story(); work.latest = 125.2
        let state = AccountState(user:Account(id:"u",name:"U",username:"u"))
        XCTAssertNil(state.readingSummary(for:work).percent)
        work.chapterListComplete = true; work.chapters = [Chapter(number:125.2,title:"125.2")]
        XCTAssertEqual(state.readingSummary(for:work).percent,0)
    }
    func testReaderChromeFollowsSlowScrollAndReversal() {
        var direction = ReaderScrollDirection()
        XCTAssertNil(direction.update(offset:500,userScrolling:false))
        XCTAssertNil(direction.update(offset:506,userScrolling:true))
        XCTAssertNil(direction.update(offset:512,userScrolling:true))
        XCTAssertEqual(direction.update(offset:518,userScrolling:true),false)
        // Small upward touches must not reveal the header.
        XCTAssertNil(direction.update(offset:503,userScrolling:true))
        XCTAssertNil(direction.update(offset:460,userScrolling:true))
        // Reversing down resets upward travel; separate corrections do not accumulate.
        XCTAssertNil(direction.update(offset:465,userScrolling:true))
        XCTAssertNil(direction.update(offset:420,userScrolling:true))
        XCTAssertNil(direction.update(offset:380,userScrolling:true))
        XCTAssertEqual(direction.update(offset:369,userScrolling:true),true)
    }
    func testReaderChromeIgnoresRestorationAndRevealsAtTop() {
        var direction = ReaderScrollDirection()
        XCTAssertNil(direction.update(offset:0,userScrolling:false))
        XCTAssertNil(direction.update(offset:3000,userScrolling:false))
        XCTAssertEqual(direction.update(offset:3020,userScrolling:true),false)
        XCTAssertNil(direction.update(offset:12,userScrolling:false))
        XCTAssertEqual(direction.update(offset:10,userScrolling:true),true)
        XCTAssertEqual(direction.update(offset:-20,userScrolling:true),true)
    }
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
        XCTAssertTrue(downloads.jobs.first?.chapters.first?.complete == true)
        downloads.invalidatePage(payload,index:1)
        XCTAssertNotNil(downloads.pageURL(payload,index:0)); XCTAssertNil(downloads.pageURL(payload,index:1)); XCTAssertFalse(downloads.jobs.first?.chapters.first?.complete == true)
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
