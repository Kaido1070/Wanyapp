import XCTest
@testable import Wany

@MainActor final class FeedAndStatsTests: XCTestCase {
    private func story(_ key: String) -> Story { Story(key:key,source:sourceFromStoryKey(key),slug:key,type:"manga",url:"",title:"Fixture",cover:"",genres:[]) }
    private func chapter(_ source: String,_ identity: String) -> FeedChapter { FeedChapter(identity:identity,number:1,title:identity,releaseAt:1,read:false,sourceKey:source,sourceLabel:source) }
    func testNewPageAppendPreservesPriorIdentityAndSourceEditions() {
        let first=FeedGroup(id:"tx:a",item:story("tx:a"),sourceKeys:["tx:a"],chapters:[chapter("tx:a","1")])
        let other=FeedGroup(id:"tx:other",item:story("tx:other"),sourceKeys:["tx:other"],chapters:[chapter("tx:other","1")])
        let merged=FeedGroup(id:"aq:b|tx:a",item:story("tx:a"),sourceKeys:["tx:a","aq:b"],chapters:[chapter("tx:a","1"),chapter("aq:b","1"),chapter("tx:a","2")])
        let one=NewFeed(followed:[first],all:[first],hasMore:true,page:1)
        let two=NewFeed(followed:[merged],all:[merged,other],hasMore:false,page:2)
        let result=one.appending(two)
        XCTAssertEqual(result.all.map(\.id),["tx:a","tx:other"])
        XCTAssertEqual(result.all[0].chapters.count,3)
        XCTAssertEqual(result.page,2); XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.appending(two).all[0].chapters.count,3)
    }
    func testActivityOverlappingPagesDoNotDuplicateEvents() {
        func event(_ id: Double) -> ActivityItem { ActivityItem(value:.object(["id":.number(id)])) }
        XCTAssertEqual(ActivityPagination.append([event(2),event(1)],to:[event(3),event(2)]).map(\.id),["3.0","2.0","1.0"])
    }
    func testCalendarUsesWebsiteDayBoundaryAndExactlyThirtyDays() throws {
        let now=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-17T22:30:00Z"))
        let recent: [JSONValue]=[.object(["day":.string("2026-10-18"),"chapters":.number(4)])]
        let days=ReadingCalendar.days(recent:recent,now:now)
        XCTAssertEqual(days.count,30); XCTAssertEqual(Set(days.map(\.key)).count,30)
        XCTAssertEqual(days.last?.key,"2026-10-18"); XCTAssertEqual(days.last?.count,4)
    }
    func testMilestonesAreWebsiteThresholdsAndNoUnearnedRankIsClaimed() throws {
        let chapters=try XCTUnwrap(ReadingMilestones.groups.first { $0.id == "chapters" })
        XCTAssertEqual(chapters.milestones.first?.threshold,10)
        XCTAssertEqual(chapters.milestones.last?.threshold,5000)
        XCTAssertNil(chapters.rank(value:0).current)
        XCTAssertEqual(chapters.rank(value:25).current?.label,"فضي")
        XCTAssertEqual(chapters.rank(value:25).next?.threshold,50)
    }
}
