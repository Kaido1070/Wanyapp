import XCTest

final class ChapterControlsInteractionTests: XCTestCase {
    func testChapterButtonEdgesBulkActionsAndPageControlsRespondToTaps() {
        let app=XCUIApplication()
        app.launchArguments=["--rany-chapter-controls-fixture"]
        app.launch()
        let read=app.buttons["reading.toggleChapter"]
        XCTAssertTrue(read.waitForExistence(timeout:15))
        XCTAssertGreaterThanOrEqual(read.frame.height,44)
        XCTAssertGreaterThanOrEqual(read.frame.width,44)
        XCTAssertTrue(read.label.hasPrefix("غير مقروء"))
        read.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.5)).tap()
        XCTAssertTrue(read.label.hasPrefix("مقروء"))
        read.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertTrue(read.label.hasPrefix("غير مقروء"))

        let all=app.buttons["reading.markAll"],clear=app.buttons["reading.clearStory"]
        XCTAssertGreaterThanOrEqual(all.frame.height,44)
        all.tap()
        XCTAssertEqual(app.staticTexts["fixture.action"].label,"read-all")
        clear.tap()
        XCTAssertEqual(app.staticTexts["fixture.action"].label,"clear-all")

        let next=app.buttons["reading.page.next"],previous=app.buttons["reading.page.previous"]
        XCTAssertFalse(previous.isEnabled)
        next.tap()
        XCTAssertEqual(app.staticTexts["fixture.page"].label,"2")
        next.tap()
        XCTAssertEqual(app.staticTexts["fixture.page"].label,"3")
        XCTAssertFalse(next.isEnabled)
        previous.tap()
        XCTAssertEqual(app.staticTexts["fixture.page"].label,"2")
        let selector=app.descendants(matching:.any)["reading.page.select"].firstMatch
        XCTAssertTrue(selector.isHittable)
        XCTAssertGreaterThanOrEqual(selector.frame.height,44)
        selector.tap()
        let thirdPage=app.buttons["3"].firstMatch
        XCTAssertTrue(thirdPage.waitForExistence(timeout:5))
        thirdPage.tap()
        XCTAssertEqual(app.staticTexts["fixture.page"].label,"3")
        let disabled=app.switches["fixture.disabled"]
        // RTL SwiftUI exposes the whole label row as the switch frame. Tap the
        // actual thumb at the leading physical edge, not the label's center.
        disabled.coordinate(withNormalizedOffset:CGVector(dx:0.07,dy:0.5)).tap()
        XCTAssertEqual(disabled.value as? String,"1")
        XCTAssertFalse(read.isEnabled)
        XCTAssertFalse(all.isEnabled)
        XCTAssertFalse(clear.isEnabled)
    }
}
