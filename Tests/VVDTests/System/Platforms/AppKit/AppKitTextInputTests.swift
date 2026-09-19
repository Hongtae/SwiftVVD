#if os(macOS)
import AppKit
import XCTest
@testable import VVD

final class AppKitTextInputTests: XCTestCase {
    @MainActor
    func testWindowResetsTextCompositionWithOptionalEventEmission() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitTextInputTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        let textInputClient = try XCTUnwrap(window.view)
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
