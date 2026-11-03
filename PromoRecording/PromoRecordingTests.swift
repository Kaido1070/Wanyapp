import XCTest

// Drives the real app through the scenes of the promotional video while the
// simulator screen is recorded. It runs only from the promo recording workflow,
// which supplies a short-lived demo session; each scene prints a timestamp so the
// recording can be cut precisely.
final class PromoRecordingTests: XCTestCase {
    private let app = XCUIApplication()
    private func mark(_ scene: String) { print("PROMO-MARK \(scene) \(String(format:"%.3f",Date().timeIntervalSince1970))") }
    private func pause(_ seconds: Double) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    // Labels can carry an icon name before the text, so match on the text itself.
    private func button(_ text: String) -> XCUIElement { app.buttons.matching(NSPredicate(format:"label CONTAINS %@",text)).firstMatch }
    private func dumpButtons() { for label in app.buttons.allElementsBoundByIndex.prefix(60).map(\.label) where !label.isEmpty { print("PROMO-DEBUG button \(label)") } }
    private func tab(_ name: String) { app.tabBars.buttons[name].tap() }
    private func scroll(_ times: Int,gap: Double = 1.6) { for _ in 0..<times { app.swipeUp(velocity:.slow); pause(gap) } }
    // Lazy grids create cards only near the viewport: drag gently until the element sits clear of the bars.
    private func reveal(_ element: XCUIElement,attempts: Int = 10) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable && element.frame.minY > 140 && element.frame.maxY < app.frame.height*0.8 { return true }
            let start = app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.72))
            start.press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.4)
            pause(1.4)
        }
        return element.exists && element.isHittable
    }
    private func openSoloChapter() {
        // SwiftUI wraps the number in direction isolates: «وصلت للفصل \u{2068}148\u{2069}».
        let solo = app.buttons.matching(NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@","وصلت للفصل","148")).firstMatch
        if !reveal(solo) { dumpButtons(); XCTFail("The Solo Leveling card must come into view.") }
        mark("resume-tap"); solo.tap()
        // The catch-up question for earlier chapters is answered "later" so the pages stay clear.
        let later = button("لاحقًا")
        if later.waitForExistence(timeout:30) { later.tap() }
    }
    private func leaveReader() {
        app.swipeDown(velocity:.slow); pause(1.2)
        let back = button("العودة للفصول")
        if back.waitForExistence(timeout:5) { back.tap() } else { app.swipeRight() }
        pause(2.5)
    }

    func testRecordPromo() throws {
        let session = ProcessInfo.processInfo.environment["RANY_PROMO_SESSION"] ?? ""
        try XCTSkipIf(session.isEmpty,"Runs only from the promo recording workflow.")
        continueAfterFailure = true
        app.launchEnvironment["RANY_PROMO_SESSION"] = session
        app.launchEnvironment["RANY_PROMO_HIDE_SOURCES"] = "1"
        // Warm-up launch (not used): sign in, load covers, the chapter, the New feed and For You, then quit.
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:120))
        pause(30)
        openSoloChapter(); pause(25); leaveReader()
        tab("جديد"); pause(25); tab("FYP"); pause(30); tab("حسابي"); pause(5)
        app.terminate(); pause(3)

        // Recorded launch: the app's own opening for a returning reader, then «حسابي».
        app.launch(); mark("launch")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:60))
        pause(6); mark("profile")
        openSoloChapter()

        // Reader: real pages of the chapter, read from where it stopped.
        pause(3); mark("reader")
        scroll(5,gap:2.2)
        leaveReader()

        // New chapters: everything new, then only followed stories.
        tab("جديد"); mark("new")
        pause(14); scroll(2,gap:2)
        let followed = app.segmentedControls.buttons["أتابعها"]
        if followed.exists { followed.tap(); mark("new-followed"); pause(4); app.segmentedControls.buttons["الكل"].tap(); pause(2) }

        // For You: suggestions built from the account's reading.
        tab("FYP"); mark("fyp")
        pause(16); scroll(3,gap:2)

        // Statistics, then the profile again.
        tab("حسابي"); pause(2)
        app.swipeDown(velocity:.fast); pause(1.5)
        let stats = button("الإحصائيات")
        if stats.waitForExistence(timeout:8) { stats.tap(); mark("stats"); pause(5); scroll(2,gap:2) }
        tab("حسابي"); pause(1)
        mark("end"); pause(4)
    }
}
