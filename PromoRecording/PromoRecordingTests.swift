import XCTest

// Drives the real app through the scenes of the promotional video while the
// simulator screen is recorded. It runs only from the promo recording workflow,
// which supplies a short-lived demo session; each scene prints a timestamp so the
// recording can be cut precisely.
final class PromoRecordingTests: XCTestCase {
    private let app = XCUIApplication()
    private func mark(_ scene: String) { print("PROMO-MARK \(scene) \(String(format:"%.3f",Date().timeIntervalSince1970))") }
    private func pause(_ seconds: Double) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    private func button(_ prefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch }
    private func tab(_ name: String) { app.tabBars.buttons[name].tap() }
    private func scroll(_ times: Int,gap: Double = 1.6) { for _ in 0..<times { app.swipeUp(velocity:.slow); pause(gap) } }

    func testRecordPromo() throws {
        let session = ProcessInfo.processInfo.environment["RANY_PROMO_SESSION"] ?? ""
        try XCTSkipIf(session.isEmpty,"Runs only from the promo recording workflow.")
        continueAfterFailure = true
        app.launchEnvironment["RANY_PROMO_SESSION"] = session
        app.launchEnvironment["RANY_PROMO_HIDE_SOURCES"] = "1"
        app.launch()
        mark("launch")

        // Arrival: the app's own opening, then «حسابي» with «أقرأ حاليًا».
        let resume = button("وصلت للفصل")
        XCTAssertTrue(resume.waitForExistence(timeout:120))
        pause(6); mark("profile")
        app.swipeUp(velocity:.slow); pause(3)
        mark("resume-tap")
        if !resume.isHittable { app.swipeUp(velocity:.slow); pause(1.5) }
        resume.tap()

        // Reader: real pages of the chapter, read from where it stopped.
        pause(7); mark("reader")
        scroll(5,gap:2.2)
        app.swipeDown(velocity:.slow); pause(1.2)
        let back = app.buttons["العودة للفصول"]
        if back.waitForExistence(timeout:5) { back.tap() } else { app.swipeRight() }
        pause(2.5)

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
