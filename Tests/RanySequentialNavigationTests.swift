import XCTest
import SwiftUI
import Combine
@testable import Wany

@MainActor final class RanySequentialNavigationTests: XCTestCase {
    func testPathChangesOnlyWhileInvisibleAndRejectsRepeatedPushes() async throws {
        let navigator = RanyNavigator()
        var observed: [(Int,Double)] = []
        let subscription = navigator.$path.dropFirst().sink { path in observed.append((path.count,navigator.opacity)) }
        defer { subscription.cancel() }
        navigator.push(AnyView(Text("first")))
        navigator.push(AnyView(Text("duplicate")))
        XCTAssertTrue(navigator.transitioning)
        XCTAssertTrue(navigator.path.isEmpty,"The outgoing page must leave before the path changes.")
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(navigator.path.count,1)
        XCTAssertFalse(navigator.transitioning)
        XCTAssertEqual(navigator.opacity,1)
        navigator.pop()
        navigator.pop()
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertTrue(navigator.path.isEmpty)
        XCTAssertFalse(navigator.transitioning)
        XCTAssertEqual(observed.map(\.0),[1,0])
        XCTAssertTrue(observed.allSatisfy { $0.1 == 0 },"Push and pop must both replace content while hidden.")
    }
    func testNestedBackAndAccountResetNeverLeaveAnInvisiblePage() async throws {
        let navigator = RanyNavigator(); navigator.reduceMotion = true
        navigator.push(AnyView(Text("one")))
        try await Task.sleep(for:.milliseconds(100))
        let first = try XCTUnwrap(navigator.path.first)
        navigator.push(AnyView(Text("two")))
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(navigator.path.count,2)
        navigator.pop(ifCurrent:first)
        XCTAssertEqual(navigator.path.count,2,"A late save from a previous route must not pop the current page.")
        navigator.pop(ifCurrent:try XCTUnwrap(navigator.path.last))
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(navigator.path,[first])
        navigator.reduceMotion = false
        navigator.push(AnyView(Text("interrupted")))
        navigator.reset()
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertTrue(navigator.path.isEmpty)
        XCTAssertEqual(navigator.opacity,1)
        XCTAssertFalse(navigator.transitioning)
    }
    func testAvatarSearchHandlesSpacesCaseAndArabic() {
        XCTAssertTrue(RanyAvatarGrid.matches("Monkey D. Luffy",query:"  luffy  "))
        XCTAssertTrue(RanyAvatarGrid.matches("ون بيس",query:"بيس"))
        XCTAssertTrue(RanyAvatarGrid.matches("One Piece",query:"  "))
        XCTAssertFalse(RanyAvatarGrid.matches("Naruto",query:"Luffy"))
    }
}
