import XCTest
@testable import VVD

final class MouseEventTests: XCTestCase {
    func testMouseEventMetadataDefaultsToNoClickOrModifiers() {
        let event = MouseEvent(
            type: .move,
            window: nil,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: .zero,
            timestamp: 1.0
        )

        XCTAssertEqual(event.clickCount, 0)
        XCTAssertTrue(event.modifiers.isEmpty)
    }
}
