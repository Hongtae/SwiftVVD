#if os(macOS)
import AppKit
import XCTest
@testable import VVD

final class AppKitClipboardTests: XCTestCase {
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

}
#endif
