import XCTest

final class ChapterControlsInteractionTests: XCTestCase {
    func testImageQualityChoicesRespondWithoutNetworkOrAccount() {
        let app=XCUIApplication(); app.launchArguments=["--rany-image-quality-fixture"]; app.launch()
        let original=app.buttons["reader.quality.original"]
        XCTAssertTrue(original.waitForExistence(timeout:15))
        original.tap()
        XCTAssertEqual(app.staticTexts["fixture.quality"].label,"original")
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name="Rany-original-quality-choice"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["reader.quality.high"].tap()
        XCTAssertEqual(app.staticTexts["fixture.quality"].label,"high")
    }

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

        // Bulk actions are behind the reading-tools menu, away from the chapter rows.
        let tools=app.buttons["reading.tools"]
        XCTAssertGreaterThanOrEqual(tools.frame.height,44)
        tools.tap()
        let all=app.buttons["reading.markAll"]
        XCTAssertTrue(all.waitForExistence(timeout:5))
        all.tap()
        XCTAssertEqual(app.staticTexts["fixture.action"].label,"read-all")
        tools.tap()
        let clear=app.buttons["reading.clearStory"]
        XCTAssertTrue(clear.waitForExistence(timeout:5))
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
        let menuClosed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:thirdPage)
        XCTAssertEqual(XCTWaiter.wait(for:[menuClosed],timeout:5),.completed,"Selecting a page must dismiss its menu before the next touch.")
        XCTAssertEqual(app.staticTexts["fixture.page"].label,"3")
        let disabled=app.switches["fixture.disabled"]
        // RTL SwiftUI exposes the whole label row as the switch frame. Tap the
        // actual thumb at the leading physical edge, not the label's center.
        disabled.coordinate(withNormalizedOffset:CGVector(dx:0.07,dy:0.5)).tap()
        XCTAssertEqual(disabled.value as? String,"1")
        XCTAssertFalse(read.isEnabled)
        XCTAssertFalse(tools.isEnabled,"Disabled reading tools must not open their bulk actions.")
    }
}
