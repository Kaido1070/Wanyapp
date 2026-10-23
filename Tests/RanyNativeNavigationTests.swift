import XCTest
import SwiftUI
@testable import Wany

@MainActor final class RanyNativeNavigationTests: XCTestCase {
    private let story = Story(key:"tx:one",source:"teamx",slug:"one",type:"manhwa",url:"",title:"One",cover:"",genres:[])
    func testEachTabKeepsItsOwnStack() {
        var tabs = RanyTabNavigation()
        XCTAssertEqual(tabs.selection,.profile)
        tabs.paths[.profile] = [.stats,.friends]
        tabs.select(.discover)
        tabs.paths[.discover] = [.story(story)]
        tabs.select(.profile)
        XCTAssertEqual(tabs.paths[.profile],[.stats,.friends],"Switching tabs must keep each tab's place.")
        XCTAssertEqual(tabs.paths[.discover],[.story(story)])
    }
    func testReselectingTabPopsToRootThenScrollsToTop() {
        var tabs = RanyTabNavigation()
        tabs.select(.discover)
        tabs.paths[.discover] = [.story(story),.reader(story,Chapter(number:1,title:"1"))]
        tabs.select(.discover)
        XCTAssertEqual(tabs.paths[.discover],[],"The first tap on the current tab returns to its first page.")
        XCTAssertEqual(tabs.scrollRequests[.discover] ?? 0,0)
        tabs.select(.discover)
        XCTAssertEqual(tabs.scrollRequests[.discover],1,"A tap on an already-root tab scrolls it to the top.")
        XCTAssertNil(tabs.scrollRequests[.profile])
    }
    func testAccountResetClearsEveryStack() {
        var tabs = RanyTabNavigation()
        tabs.paths = [.profile:[.settings,.updates],.new:[.story(story)]]
        tabs.reset()
        XCTAssertTrue(tabs.paths.isEmpty)
    }
    func testRoutesAreValueIdentified() {
        XCTAssertEqual(RanyRoute.story(story),RanyRoute.story(story))
        XCTAssertNotEqual(RanyRoute.listDetail(id:"1",title:"A"),RanyRoute.listDetail(id:"2",title:"A"))
        XCTAssertEqual(RanyTab.allCases.count,5)
    }
    func testReadingCalendarWeeksStartOnSundayWithSevenSlots() {
        // 2026-09-24 is a Thursday in UTC+3: four empty slots precede it.
        let now=ISO8601DateFormatter().date(from:"2026-10-23T12:00:00+03:00")!
        let weeks=ReadingCalendar.weeks(ReadingCalendar.days(recent:[],now:now))
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks.first?.prefix(4).allSatisfy { $0 == nil },true)
        XCTAssertEqual(weeks.first?[4]?.key,"2026-09-24")
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count,30)
    }
    func testChapterTitleShowsTheNumberOnce() {
        XCTAssertEqual(chapterDisplayTitle("الفصل 355.2 355.2",number:355.2),"الفصل 355.2")
        XCTAssertEqual(chapterDisplayTitle("الفصل 1 الفصل رقم 1",number:1),"الفصل 1")
        XCTAssertEqual(chapterDisplayTitle("355.2",number:355.2),"الفصل 355.2")
        XCTAssertEqual(chapterDisplayTitle("الفصل 12 - بداية الرحلة",number:12),"الفصل 12 · بداية الرحلة")
        XCTAssertEqual(chapterDisplayTitle("الفصل 1: 10 سيوف",number:1),"الفصل 1 · 10 سيوف")
    }
    func testAvatarSearchHandlesSpacesCaseAndArabic() {
        XCTAssertTrue(RanyAvatarGrid.matches("Monkey D. Luffy",query:"  luffy  "))
        XCTAssertTrue(RanyAvatarGrid.matches("ون بيس",query:"بيس"))
        XCTAssertTrue(RanyAvatarGrid.matches("One Piece",query:"  "))
        XCTAssertFalse(RanyAvatarGrid.matches("Naruto",query:"Luffy"))
    }
}
