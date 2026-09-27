#if os(macOS)
import AppKit
import XCTest
@testable import VVD

final class AppKitCursorTests: XCTestCase {
    @MainActor
    func testCursorMappingAndCustomHotSpotClamping() throws {
        _ = NSApplication.shared
        XCTAssertTrue(makeAppKitCursor(.arrow) === NSCursor.arrow)
        XCTAssertTrue(makeAppKitCursor(.text) === NSCursor.iBeam)
        XCTAssertTrue(makeAppKitCursor(.wait) === NSCursor.arrow)
        XCTAssertTrue(makeAppKitCursor(.crosshair) === NSCursor.crosshair)
        XCTAssertTrue(makeAppKitCursor(.progress) === NSCursor.arrow)
        XCTAssertTrue(
            makeAppKitCursor(.resizeLeftRight) === NSCursor.columnResize
        )
        XCTAssertTrue(
            makeAppKitCursor(.resizeUpDown) === NSCursor.rowResize
        )
        XCTAssertTrue(makeAppKitCursor(.move) === NSCursor.openHand)
        XCTAssertTrue(
            makeAppKitCursor(.notAllowed) === NSCursor.operationNotAllowed
        )
        XCTAssertTrue(
            makeAppKitCursor(.pointingHand) === NSCursor.pointingHand
        )
        XCTAssertNotNil(makeAppKitCursor(.resizeUpLeftDownRight))
        XCTAssertNotNil(makeAppKitCursor(.resizeUpRightDownLeft))

        let image = Image(
            width: 2,
            height: 3,
            pixelFormat: .rgba8,
            data: Data(repeating: 0xff, count: 2 * 3 * 4)
        )
        let custom = try XCTUnwrap(
            makeAppKitCursor(
                .custom(image, hotSpot: CGPoint(x: 100, y: -4))
            )
        )
        XCTAssertEqual(custom.image.size, NSSize(width: 2, height: 3))
        XCTAssertEqual(custom.hotSpot, NSPoint(x: 1, y: 0))

        let nonFinite = try XCTUnwrap(
            makeAppKitCursor(
                .custom(
                    image,
                    hotSpot: CGPoint(
                        x: CGFloat.infinity,
                        y: CGFloat.nan
                    )
                )
            )
        )
        XCTAssertEqual(nonFinite.hotSpot, NSPoint.zero)
    }

    @MainActor
    func testWindowStoresCursorOverridePerPrimaryPointer() throws {
        let previousNativeCursor = NSCursor.current
        defer { previousNativeCursor.set() }
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitCursorTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        window.setCursor(.resizeLeftRight, forDeviceID: 0)
        guard case .resizeLeftRight? = window.cursor(forDeviceID: 0) else {
            return XCTFail("Expected the primary pointer cursor override")
        }

        window.setCursor(.crosshair, forDeviceID: 1)
        XCTAssertNil(window.cursor(forDeviceID: 1))
        guard case .resizeLeftRight? = window.cursor(forDeviceID: 0) else {
            return XCTFail("An unsupported device must not change the override")
        }

        NSCursor.columnResize.set()
        window.setCursor(nil, forDeviceID: 0)
        XCTAssertNil(window.cursor(forDeviceID: 0))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
    }
}
#endif
