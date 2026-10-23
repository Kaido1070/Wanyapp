import XCTest
@testable import Wany

// Chapter lists must match the website: every chapter the site shows is listed,
// whatever types the source uses, and a partial source never empties the list.
@MainActor final class ChapterSyncTests: XCTestCase {
    private func client() -> API {
        let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[APIStubProtocol.self]
        return API(configuration:config,credential:"fixture",persistCredentials:false)
    }
    override func tearDown() { APIStubProtocol.handler=nil; super.tearDown() }

    func testSeriesDecodesTextNumbersNullTitlesAndSkipsOnlyUnreadableChapters() throws {
        let json=#"{"item":{"key":"aq:hunter","source":"3asq","title":"Hunter","latest":"390","genres":null,"chapters":[{"number":"1","title":null},{"number":2,"title":"2","url":"https://3asq/2"},{"number":"الفصل ٣","synthetic":true},{"number":null,"title":"broken"},{"number":"4.5","title":"","url":""}]}}"#
        let story=try JSONDecoder().decode(SeriesResponse.self,from:Data(json.utf8)).item
        XCTAssertEqual(story.orderedChapters.map(\.number),[1,2,3,4.5])
        XCTAssertEqual(story.latest,390); XCTAssertEqual(story.genres,[])
        XCTAssertEqual(story.orderedChapters[0].title,"الفصل 1")
        XCTAssertNil(story.orderedChapters[3].url)
    }
    func testOneBrokenStoryDoesNotHideTheRestOfAPage() throws {
        let json=#"{"items":[{"key":"aq:a","title":"A"},{"title":"no key"},{"key":"aq:b","title":"B","chapters":[{"number":"7"}]}],"hasMore":true,"page":"2"}"#
        let list=try JSONDecoder().decode(APIList.self,from:Data(json.utf8))
        XCTAssertEqual(list.items.map(\.key),["aq:a","aq:b"]); XCTAssertEqual(list.page,2); XCTAssertTrue(list.hasMore)
    }
    func testNumberOnlyChaptersAndShortDeclaredCountsStillListEveryChapter() async throws {
        let api=client()
        APIStubProtocol.handler={ request in
            let path=request.url!.path
            if path == "/api/source/series" {
                return (200,[:],Data(#"{"item":{"key":"aq:hunter","source":"3asq","title":"Hunter","declaredChapterCount":400,"chapterListComplete":false,"chapters":[{"number":1,"synthetic":true},{"number":2,"synthetic":true}]}}"#.utf8))
            }
            if path == "/api/source/chapters-page" { return (500,[:],Data(#"{"message":"page failed"}"#.utf8)) }
            return (404,[:],Data())
        }
        let story=try await api.fullSeries("aq:hunter")
        XCTAssertEqual(story.orderedChapters.map(\.number),[1,2],"Number-only chapters open by number on the site and must be listed.")
        XCTAssertEqual(story.chapterListComplete,false,"A short list is shown and flagged, never thrown away.")
    }
    func testChapterPagesAddToTheSeriesListAndKeepReadableEntries() async throws {
        let api=client()
        APIStubProtocol.handler={ request in
            let url=request.url!
            let page=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "page" }?.value
            switch (url.path,page) {
            case ("/api/source/series",_):
                return (200,[:],Data(#"{"item":{"key":"tx:w","source":"teamx","title":"W","chapterPageCount":2,"chapters":[{"number":3,"title":"3","synthetic":true}]}}"#.utf8))
            case ("/api/source/chapters-page","1"):
                return (200,[:],Data(#"{"chapters":[{"number":3,"title":"3","url":"https://tx/3"},{"number":2,"title":"2","url":"https://tx/2"}],"page":1,"pages":2}"#.utf8))
            case ("/api/source/chapters-page","2"):
                return (200,[:],Data(#"{"chapters":[{"number":"1","title":"1","url":"https://tx/1"}],"page":"2","pages":"2"}"#.utf8))
            default: return (404,[:],Data())
            }
        }
        let story=try await api.fullSeries("tx:w")
        XCTAssertEqual(story.orderedChapters.map(\.number),[1,2,3])
        XCTAssertEqual(story.orderedChapters.last?.url,"https://tx/3"); XCTAssertNotEqual(story.orderedChapters.last?.synthetic,true)
        XCTAssertEqual(story.chapterListComplete,true)
    }
}
