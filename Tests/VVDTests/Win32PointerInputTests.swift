#if ENABLE_WIN32
import XCTest
import WinSDK
@testable import VVD

final class Win32PointerInputTests: XCTestCase {
    func testOnlyStylusRetainsPointerStateAfterContactEnds() {
        XCTAssertTrue(
            win32RetainsPointerStateAfterEvent(
                type: .buttonUp,
                device: .stylus
            )
        )
        XCTAssertFalse(
            win32RetainsPointerStateAfterEvent(
                type: .buttonUp,
                device: .touch
            )
        )
        XCTAssertFalse(
            win32RetainsPointerStateAfterEvent(
                type: .cancelled,
                device: .stylus
            )
        )
    }

    func testPenSecondaryButtonUsesPointerFlagOrBarrelFlag() {
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: DWORD(POINTER_FLAG_SECONDBUTTON),
                penFlags: 0,
                buttonChange: POINTER_CHANGE_NONE,
                activeButtonID: nil
            ),
            1
        )
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: 0,
                penFlags: DWORD(PEN_FLAG_BARREL),
                buttonChange: POINTER_CHANGE_NONE,
                activeButtonID: nil
            ),
            1
        )
    }

    func testPenSecondaryButtonUsesButtonTransitions() {
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: 0,
                penFlags: 0,
                buttonChange: POINTER_CHANGE_SECONDBUTTON_DOWN,
                activeButtonID: nil
            ),
            1
        )
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: 0,
                penFlags: 0,
                buttonChange: POINTER_CHANGE_SECONDBUTTON_UP,
                activeButtonID: nil
            ),
            1
        )
    }

    func testPenContactPreservesItsInitialButtonUntilTerminalDelivery() {
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: DWORD(POINTER_FLAG_FIRSTBUTTON),
                penFlags: 0,
                buttonChange: POINTER_CHANGE_FIRSTBUTTON_UP,
                activeButtonID: 1
            ),
            1
        )
        XCTAssertEqual(
            win32PenButtonID(
                pointerFlags: DWORD(POINTER_FLAG_SECONDBUTTON),
                penFlags: DWORD(PEN_FLAG_BARREL),
                buttonChange: POINTER_CHANGE_SECONDBUTTON_DOWN,
                activeButtonID: 0
            ),
            0
        )
    }
}
#endif
