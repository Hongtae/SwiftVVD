import XCTest
@testable import VUI

final class GesturePhaseSurfaceTests: XCTestCase {
    func testActiveIncludesEndedButNotPossibleOrFailed() {
        XCTAssertFalse(GesturePhase<Int>.possible(3).isActive)
        XCTAssertTrue(GesturePhase<Int>.active(4).isActive)
        XCTAssertTrue(GesturePhase<Int>.ended(5).isActive)
        XCTAssertFalse(GesturePhase<Int>.failed.isActive)
    }

    func testUnwrappedIgnoresPossiblePayloadAndReturnsActiveOrEndedPayload() {
        XCTAssertNil(GesturePhase<Int>.possible(3).unwrapped)
        XCTAssertEqual(GesturePhase<Int>.active(4).unwrapped, 4)
        XCTAssertEqual(GesturePhase<Int>.ended(5).unwrapped, 5)
        XCTAssertNil(GesturePhase<Int>.failed.unwrapped)
    }

    func testDefaultValueIsFailed() {
        XCTAssertEqual(GesturePhase<Int>.defaultValue, .failed)
    }
}
