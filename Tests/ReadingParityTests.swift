import XCTest
@testable import Wany

@MainActor final class ReadingParityTests: XCTestCase {
    func testOpeningIsPersistedWithoutMarkingCompletion() throws {
        let store=AppStore(startServices:false); store.online=false
        let owner="test-open-"+UUID().uuidString; store.state=AccountState(user:Account(id:owner,name:"fixture",username:"fixture"))
        let story=Story(key:"tx:fixture",source:"teamx",slug:"fixture",type:"manga",url:"",title:"Fixture",cover:"",genres:[])
        let payload=ChapterPayload(item:story,number:2.5,title:"chapter",pages:["fixture-page"])
        store.queueChapterOpen(payload)
        XCTAssertTrue(store.state!.data.completed.isEmpty)
        XCTAssertTrue(store.state!.data.progress.isEmpty)
        XCTAssertNotNil(store.state!.pendingOpens?[payload.id])
        let saved=try XCTUnwrap(Disk.read(AccountState.self,owner:owner,name:"account.json"))
        XCTAssertEqual(saved.data.lastOpened?.chapter,2.5)
        XCTAssertEqual(saved.pendingOpens?.count,1)
    }
    func testUnreadRemovalCannotResurrectPendingCompletionOrRemovePrefixNeighbor() {
        var state=AccountState(user:Account(id:"fixture",name:"fixture",username:"fixture"))
        let a=ProgressRecord(mangaId:"tx:story",chapter:1,percent:100,updatedAt:1)
        let b=ProgressRecord(mangaId:"tx:story:other",chapter:1,percent:30,updatedAt:2)
        state.pending=[a.id:a,b.id:b]; state.completedPending=[a.id:a]; state.positions=[a.id:2,b.id:1]
        state.pendingOpens=[a.id:ReadingOpenEvent(mangaId:a.mangaId,chapter:a.chapter,openedAt:1)]
        state.discardPendingReading(mangaId:"tx:story")
        XCTAssertNil(state.pending[a.id]); XCTAssertNil(state.completedPending?[a.id]); XCTAssertNil(state.pendingOpens?[a.id])
        XCTAssertNotNil(state.pending[b.id]); XCTAssertEqual(state.positions[b.id],1)
        state.mergeReadingData(AccountData())
        XCTAssertFalse(state.data.completed.contains(a.id))
    }
    func testOpeningOnlyQueueSurvivesRemoteMergeWithoutInventingPercent() {
        var state=AccountState(user:Account(id:"fixture",name:"fixture",username:"fixture"))
        let event=ReadingOpenEvent(mangaId:"tx:fixture",chapter:4,openedAt:100)
        state.pendingOpens=[event.id:event]; state.mergeReadingData(AccountData())
        XCTAssertEqual(state.data.lastOpened?.chapter,4)
        XCTAssertTrue(state.data.progress.isEmpty); XCTAssertTrue(state.data.completed.isEmpty)
    }
    func testSnapshotCoverUploadUsesImageMimeAndAuthenticatedQuery() throws {
        let api=API(configuration:.ephemeral,credential:"fixture",persistCredentials:false)
        let request=try api.request("/api/work-snapshots/cover",query:["key":"tx:fixture"],method:"PUT",body:Data([1,2]),contentType:"image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Type"),"image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"anytime_session=fixture")
        XCTAssertEqual(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"tx:fixture")
    }
}
