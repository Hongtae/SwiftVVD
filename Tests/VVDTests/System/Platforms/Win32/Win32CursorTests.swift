#if ENABLE_WIN32
import Foundation
import WinSDK
import XCTest
@testable import VVD

final class Win32CursorTests: XCTestCase {
    @MainActor
    func testClientCursorOverrideUsesNativeCursorAndRestoresDefault() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "Win32CursorTests",
                style: .genericWindow,
                delegate: nil
            ) as? Win32Window
        )
        let previousCursor = GetCursor()
        defer {
            SetCursor(previousCursor)
            window.close()
        }

        window.setCursor(.pointingHand, forDeviceID: 0)
        guard case .pointingHand? = window.cursor(forDeviceID: 0) else {
            return XCTFail("Expected the hand cursor override")
        }
        XCTAssertNil(window.cursor(forDeviceID: 1))

        let hWnd = try XCTUnwrap(window.hWnd)
        let setCursorParameter = LPARAM(
            UInt(UInt16(HTCLIENT)) |
            (UInt(UInt16(WM_MOUSEMOVE)) << 16)
        )
        XCTAssertEqual(
            SendMessageW(
                hWnd,
                UINT(WM_SETCURSOR),
                WPARAM(UInt(bitPattern: hWnd)),
                setCursorParameter
            ),
            1
        )

        let handResource = UnsafePointer<WCHAR>(bitPattern: 32649)
        XCTAssertEqual(GetCursor(), LoadCursorW(nil, handResource))

        window.setCursor(nil, forDeviceID: 0)
        XCTAssertNil(window.cursor(forDeviceID: 0))
        SendMessageW(
            hWnd,
            UINT(WM_SETCURSOR),
            WPARAM(UInt(bitPattern: hWnd)),
            setCursorParameter
        )
        let arrowResource = UnsafePointer<WCHAR>(bitPattern: 32512)
        XCTAssertEqual(GetCursor(), LoadCursorW(nil, arrowResource))
    }

    func testCustomCursorCreatesOwnedNativeHandle() {
        let pixels = Data([
            255, 0, 0, 255,
            0, 255, 0, 128,
            0, 0, 255, 128,
            255, 255, 255, 0,
        ])
        let image = Image(
            width: 2,
            height: 2,
            pixelFormat: .rgba8,
            data: pixels
        )
        let cursor = Win32CursorHandle(
            .custom(image, hotSpot: CGPoint(x: 1, y: 1))
        )
        XCTAssertNotNil(cursor)
        let nonFinite = Win32CursorHandle(
            .custom(
                image,
                hotSpot: CGPoint(x: CGFloat.infinity, y: CGFloat.nan)
            )
        )
        XCTAssertNotNil(nonFinite)
    }

    func testCommonSystemCursorCasesUseExpectedNativeResources() throws {
        let mappings: [(Cursor, UInt)] = [
            (.arrow, 32512),
            (.text, 32513),
            (.wait, 32514),
            (.crosshair, 32515),
            (.progress, 32650),
            (.resizeUpLeftDownRight, 32642),
            (.resizeUpRightDownLeft, 32643),
            (.resizeLeftRight, 32644),
            (.resizeUpDown, 32645),
            (.move, 32646),
            (.notAllowed, 32648),
            (.pointingHand, 32649),
        ]

        for (cursor, identifier) in mappings {
            let native = try XCTUnwrap(Win32CursorHandle(cursor))
            let resource = UnsafePointer<WCHAR>(bitPattern: identifier)
            XCTAssertEqual(native.handle, LoadCursorW(nil, resource))
        }
    }
}
#endif
