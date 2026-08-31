#if os(Linux)
import XCTest
@testable import VVD

final class WaylandClipboardTests: XCTestCase {
    func testPlainTextMIMEAliasesNormalizeToCanonicalType() {
        XCTAssertEqual(
            WaylandClipboard.normalizedTypes([
                "text/plain;charset=utf-8",
                "image/png",
                "text/plain",
                ClipboardContentType.utf8PlainText,
            ]),
            [ClipboardContentType.utf8PlainText, "image/png"]
        )
    }

    func testPlainTextSourceAdvertisesNativeMIMEAliases() {
        let advertised = WaylandClipboard.advertisedMIMETypes(for: [
            "application/x-example",
            ClipboardContentType.utf8PlainText,
        ])

        XCTAssertEqual(
            advertised,
            [
                "application/x-example",
                ClipboardContentType.utf8PlainText,
                "text/plain;charset=utf-8",
                "text/plain",
            ]
        )
    }

    func testOfferedTypeResolutionPrefersExactThenUTF8MIME() {
        let offered = [
            "text/plain",
            "text/plain;charset=utf-8",
            "application/x-example",
        ]

        XCTAssertEqual(
            WaylandClipboard.preferredOfferedType(
                for: "application/x-example",
                in: offered
            ),
            "application/x-example"
        )
        XCTAssertEqual(
            WaylandClipboard.preferredOfferedType(
                for: ClipboardContentType.utf8PlainText,
                in: offered
            ),
            "text/plain;charset=utf-8"
        )
        XCTAssertNil(
            WaylandClipboard.preferredOfferedType(
                for: "application/x-missing",
                in: offered
            )
        )
    }
}
#endif
