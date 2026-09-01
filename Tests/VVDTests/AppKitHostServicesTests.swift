#if os(macOS)
import AppKit
import XCTest
@testable import VVD

final class AppKitHostServicesTests: XCTestCase {
    func testClipboardRoundTripsAlternateRepresentationsAndConformingTextType() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "com.swiftvvd.tests.clipboard.\(UUID().uuidString)"
            )
        )
        defer { pasteboard.releaseGlobally() }

        let clipboard = AppKitClipboard(pasteboard: pasteboard)
        let string = "Clipboard text 한글"
        let text = Data(string.utf8)
        let customType = "com.swiftvvd.tests.payload"
        let customData = Data([0x00, 0x7f, 0x80, 0xff])
        let emptyType = "com.swiftvvd.tests.empty"

        try clipboard.setData([
            ClipboardContentType.utf8PlainText: text,
            customType: customData,
            emptyType: Data(),
        ])

        XCTAssertTrue(
            clipboard.types.contains(ClipboardContentType.utf8PlainText)
        )
        XCTAssertTrue(clipboard.types.contains(customType))
        XCTAssertTrue(clipboard.types.contains(emptyType))
        XCTAssertTrue(
            clipboard.containsData(forType: ClipboardContentType.utf8PlainText)
        )
        XCTAssertTrue(clipboard.containsData(forType: "public.plain-text"))
        XCTAssertTrue(clipboard.containsData(forType: customType))
        XCTAssertEqual(
            try clipboard.data(forType: ClipboardContentType.utf8PlainText),
            text
        )
        XCTAssertEqual(
            try clipboard.data(forType: "public.plain-text"),
            text
        )
        XCTAssertEqual(try clipboard.data(forType: customType), customData)
        XCTAssertEqual(try clipboard.data(forType: emptyType), Data())
        XCTAssertEqual(pasteboard.string(forType: .string), string)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(string, forType: .string))
        XCTAssertEqual(
            try clipboard.data(forType: ClipboardContentType.utf8PlainText),
            text
        )

        try clipboard.clear()
        XCTAssertTrue(clipboard.types.isEmpty)
        XCTAssertFalse(clipboard.containsData(forType: customType))
        XCTAssertNil(try clipboard.data(forType: customType))
    }

    @MainActor
    func testCursorMappingAndCustomHotSpotClamping() throws {
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
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitHostServicesTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        window.setCursor(.pointingHand, forDeviceID: 0)
        guard case .pointingHand? = window.cursor(forDeviceID: 0) else {
            return XCTFail("Expected the primary pointer cursor override")
        }

        window.setCursor(.crosshair, forDeviceID: 1)
        XCTAssertNil(window.cursor(forDeviceID: 1))
        guard case .pointingHand? = window.cursor(forDeviceID: 0) else {
            return XCTFail("An unsupported device must not change the override")
        }

        window.setCursor(nil, forDeviceID: 0)
        XCTAssertNil(window.cursor(forDeviceID: 0))
    }

    @MainActor
    func testWindowResetsTextCompositionWithOptionalEventEmission() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitHostServicesTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        let textInputClient = try XCTUnwrap(
            window.nsView as? any NSTextInputClient
        )
        let observer = NSObject()
        var events: [KeyboardEvent] = []
        window.addEventObserver(observer) { (event: KeyboardEvent) in
            events.append(event)
        }
        window.enableTextInput(true, forDeviceID: 0)

        textInputClient.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        window.enableTextInput(false, forDeviceID: 0)
        events.removeAll()

        XCTAssertEqual(
            window.resetTextComposition(true, forDeviceID: 0),
            "한"
        )
        XCTAssertTrue(events.isEmpty)

        window.enableTextInput(true, forDeviceID: 0)
        textInputClient.setMarkedText(
            "글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        events.removeAll()

        XCTAssertEqual(
            window.resetTextComposition(true, forDeviceID: 0),
            "글"
        )
        XCTAssertEqual(events.count, 2)
        if events.count == 2 {
            guard case .textInput = events[0].type else {
                return XCTFail("Expected committed text input first")
            }
            XCTAssertEqual(events[0].text, "글")
            guard case .textComposition = events[1].type else {
                return XCTFail("Expected composition reset second")
            }
            XCTAssertEqual(events[1].text, "")
        }
    }
}
#endif
