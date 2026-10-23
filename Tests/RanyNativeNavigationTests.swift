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
    func testAvatarSearchHandlesSpacesCaseAndArabic() {
        XCTAssertTrue(RanyAvatarGrid.matches("Monkey D. Luffy",query:"  luffy  "))
        XCTAssertTrue(RanyAvatarGrid.matches("ون بيس",query:"بيس"))
        XCTAssertTrue(RanyAvatarGrid.matches("One Piece",query:"  "))
        XCTAssertFalse(RanyAvatarGrid.matches("Naruto",query:"Luffy"))
    }
}
