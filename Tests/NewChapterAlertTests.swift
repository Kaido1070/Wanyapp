import XCTest
@testable import Wany

@MainActor final class NewChapterAlertTests: XCTestCase {
    private let owner = "alerts-fixture"
    private func feed(_ chapters: [(Double,Bool)]) -> NewFeed {
        let story = Story(key:"aq:hunter",source:"3asq",slug:"hunter",type:"manga",url:"",title:"Hunter",cover:"",genres:[])
        let items = chapters.map { FeedChapter(identity:chapterNumber($0.0),number:$0.0,title:"",releaseAt:1,read:$0.1,sourceKey:story.key,sourceLabel:"3asq") }
        let group = FeedGroup(id:story.key,item:story,sourceKeys:[story.key],chapters:items)
        return NewFeed(followed:[group],all:[group],hasMore:false,page:1)
    }
    func testAlertsAnnounceOnlyNewUnreadFollowedChaptersOnce() async {
        let alerts = NewChapterAlerts.shared
        alerts.forget(owner:owner); alerts.markBaseline(owner:owner)
        let announcedAtStart = await alerts.record(feed([(10,false)]),owner:owner,notify:true)
        XCTAssertEqual(announcedAtStart,0,"Chapters already waiting when alerts are switched on are not announced.")
        let repeated = await alerts.record(feed([(10,false)]),owner:owner,notify:true)
        XCTAssertEqual(repeated,0)
        let next = await alerts.record(feed([(10,false),(11,false),(12,true)]),owner:owner,notify:true)
        XCTAssertEqual(next,1,"Only the new unread chapter is announced.")
        await alerts.record(feed([(13,false)]),owner:owner,notify:false)
        let afterSeen = await alerts.record(feed([(13,false)]),owner:owner,notify:true)
        XCTAssertEqual(afterSeen,0,"A chapter already shown on the New page is not announced later.")
        alerts.forget(owner:owner)
    }
}
