#if ENABLE_WIN32
import Foundation
import WinSDK
import XCTest
@testable import VVD

@MainActor
private final class Win32MenuRefreshRecorder: WindowMenuControllerDelegate {
    private(set) var requestedMenuIDs: [WindowMenu.ID?] = []

    func windowMenuController(
        _ controller: any WindowMenuController,
        needsUpdateMenu menuID: WindowMenu.ID?
    ) {
        requestedMenuIDs.append(menuID)
    }
}

final class Win32HostServicesTests: XCTestCase {
    @MainActor
    func testWindowMenuAttachesDispatchesAndPreservesClientSize() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "Win32HostServicesTests.Menu",
                style: .genericWindow,
                delegate: nil
            ) as? Win32Window
        )
        defer { window.close() }

        window.contentSize = CGSize(width: 640, height: 480)
        let expectedResolution = window.resolution
        var invocationCount = 0

        let firstController = try XCTUnwrap(
            window.menuController as? Win32WindowMenuController
        )
        let secondController = try XCTUnwrap(
            window.menuController as? Win32WindowMenuController
        )
        XCTAssertTrue(firstController === secondController)

        let refreshRecorder = Win32MenuRefreshRecorder()
        firstController.delegate = refreshRecorder
        firstController.setMenu(
            WindowMenu {
                WindowMenu.Menu(
                    id: "file",
                    title: "File",
                    role: .file,
                    accessKey: "f"
                ) {
                    WindowMenu.Item(
                        id: "run",
                        title: "Run",
                        accessKey: "r",
                        shortcut: WindowMenu.Shortcut(
                            .f8,
                            modifiers: [.control]
                        )
                    ) {
                        invocationCount += 1
                    }
                    WindowMenu.Element.separator
                    WindowMenu.Menu(id: "recent", title: "Recent") {
                        WindowMenu.Item(id: "document", title: "Document")
                    }
                }
            }
        )

        let hWnd = try XCTUnwrap(window.hWnd)
        let root = try XCTUnwrap(GetMenu(hWnd))
        let fileMenu = try XCTUnwrap(GetSubMenu(root, 0))
        XCTAssertEqual(GetMenuItemCount(root), 1)
        XCTAssertEqual(GetMenuItemCount(fileMenu), 3)
        XCTAssertEqual(window.resolution, expectedResolution)

        let commandID = GetMenuItemID(fileMenu, 0)
        XCTAssertNotEqual(commandID, UINT.max)
        SendMessageW(
            hWnd,
            UINT(WM_COMMAND),
            WPARAM(commandID),
            0
        )
        XCTAssertEqual(invocationCount, 1)

        SendMessageW(
            hWnd,
            UINT(WM_INITMENUPOPUP),
            WPARAM(UInt(bitPattern: fileMenu)),
            0
        )
        XCTAssertEqual(refreshRecorder.requestedMenuIDs, ["file"])

        SendMessageW(
            hWnd,
            UINT(WM_INITMENU),
            WPARAM(UInt(bitPattern: root)),
            0
        )
        XCTAssertEqual(refreshRecorder.requestedMenuIDs.count, 2)
        XCTAssertNil(refreshRecorder.requestedMenuIDs[1])

        SendMessageW(hWnd, UINT(WM_ENTERMENULOOP), 0, 0)
        firstController.setMenu(
            WindowMenu {
                WindowMenu.Menu(id: "edit", title: "Edit") {
                    WindowMenu.Item(id: "replace", title: "Replace")
                }
            }
        )
        XCTAssertEqual(GetMenu(hWnd), root)
        SendMessageW(hWnd, UINT(WM_EXITMENULOOP), 0, 0)
        XCTAssertNotEqual(GetMenu(hWnd), root)
        XCTAssertEqual(window.resolution, expectedResolution)

        firstController.setMenu(nil)
        XCTAssertNil(GetMenu(hWnd))
        XCTAssertEqual(window.resolution, expectedResolution)
    }

    @MainActor
    func testClientCursorOverrideUsesNativeCursorAndRestoresDefault() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "Win32HostServicesTests.Cursor",
                style: .genericWindow,
                delegate: nil
            ) as? Win32Window
        )
        let previousCursor = GetCursor()
        defer {
            SetCursor(previousCursor)
            window.close()
        }

        window.setCursor(.hand, forDeviceID: 0)
        guard case .hand? = window.cursor(forDeviceID: 0) else {
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
    }
}
#endif
