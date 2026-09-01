#if os(Linux)
import XCTest
@testable import VVD

final class WaylandCursorTests: XCTestCase {
    func testCommonSystemCursorCasesUsePortableThemeAliases() {
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .text),
            ["text", "xterm"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .wait),
            ["wait", "watch"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .progress),
            ["progress", "left_ptr_watch", "half-busy", "wait", "watch"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .move),
            ["move", "all-scroll", "fleur", "size_all"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .resizeUpLeftDownRight),
            ["nwse-resize", "size_fdiag", "bd_double_arrow"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .resizeUpRightDownLeft),
            ["nesw-resize", "size_bdiag", "fd_double_arrow"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .resizeLeftRight),
            ["ew-resize", "size_hor", "sb_h_double_arrow"]
        )
        XCTAssertEqual(
            WaylandCursorManager.themeNames(for: .resizeUpDown),
            ["ns-resize", "size_ver", "sb_v_double_arrow"]
        )
    }
}
#endif
