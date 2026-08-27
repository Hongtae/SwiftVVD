#if os(macOS)
import AppKit
import XCTest
@testable import VVD

@MainActor
private final class WindowMenuRefreshDelegate: WindowMenuControllerDelegate {
    var requestedMenuIDs: [WindowMenu.ID?] = []

    func windowMenuController(
        _ controller: any WindowMenuController,
        needsUpdateMenu menuID: WindowMenu.ID?
    ) {
        requestedMenuIDs.append(menuID)
    }
}

final class AppKitWindowMenuTests: XCTestCase {
    @MainActor
    func testActiveRootSwitchesApplicationMenuAndMenuLessChildKeepsIt() throws {
        let firstWindow = try XCTUnwrap(
            makeWindow(name: "FirstRoot", style: [.title], delegate: nil)
        )
        let secondWindow = try XCTUnwrap(
            makeWindow(name: "SecondRoot", style: [.title], delegate: nil)
        )
        let childWindow = try XCTUnwrap(
            makeWindow(name: "PresentationChild", style: [.popupWindow], delegate: nil)
        )
        defer {
            childWindow.close()
            secondWindow.close()
            firstWindow.close()
        }

        let firstController = try XCTUnwrap(
            firstWindow.menuController as? AppKitWindowMenuController
        )
        let secondController = try XCTUnwrap(
            secondWindow.menuController as? AppKitWindowMenuController
        )
        let childController = try XCTUnwrap(
            childWindow.menuController as? AppKitWindowMenuController
        )

        firstController.setMenu(WindowMenu {
            WindowMenu.Menu(id: "first", title: "First")
        })
        secondController.setMenu(WindowMenu {
            WindowMenu.Menu(id: "second", title: "Second")
        })
        XCTAssertEqual(NSApplication.shared.mainMenu?.items.first?.title, "First")

        let secondNativeWindow = try XCTUnwrap(secondController.nativeWindow)
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: secondNativeWindow
        )
        XCTAssertEqual(NSApplication.shared.mainMenu?.items.first?.title, "Second")

        let childNativeWindow = try XCTUnwrap(childController.nativeWindow)
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: childNativeWindow
        )
        XCTAssertEqual(NSApplication.shared.mainMenu?.items.first?.title, "Second")
    }

    @MainActor
    func testNativeMenuConversionPreservesRolesActionsAndRefreshIDs() throws {
        var actionCount = 0
        let window = try XCTUnwrap(
            makeWindow(name: "AppKitWindowMenuTests", style: [.title], delegate: nil)
        )
        defer { window.close() }

        let controller = try XCTUnwrap(
            window.menuController as? AppKitWindowMenuController
        )
        let refreshDelegate = WindowMenuRefreshDelegate()
        controller.delegate = refreshDelegate
        let icon = Image(
            width: 32,
            height: 16,
            pixelFormat: .rgba8,
            data: Data(repeating: 0xff, count: 32 * 16 * 4)
        )

        controller.setMenu(WindowMenu {
            WindowMenu.Menu(id: "application", title: "Application", role: .application) {
                WindowMenu.Menu(id: "services", title: "Services", role: .services)
            }
            WindowMenu.Menu(id: "window", title: "Window", role: .window) {
                WindowMenu.Item(
                    id: "show-window",
                    title: "Show Window",
                    image: icon,
                    imageIsTemplate: true,
                    state: .mixed,
                    isEnabled: false,
                    isHidden: true,
                    isAlternate: true,
                    indentationLevel: 2,
                    allowsShortcutWhenHidden: true,
                    shortcut: WindowMenu.Shortcut("W", modifiers: [.command, .shift]),
                    toolTip: "Show the main window"
                ) {
                    actionCount += 1
                }
            }
            WindowMenu.Menu(
                id: "help",
                title: "Help",
                role: .help,
                usesPlatformItemValidation: true
            )
        })

        let application = NSApplication.shared
        let mainMenu = try XCTUnwrap(application.mainMenu)
        XCTAssertEqual(mainMenu.items.map(\.title), ["Application", "Window", "Help"])

        let windowMenu = try XCTUnwrap(application.windowsMenu)
        let helpMenu = try XCTUnwrap(application.helpMenu)
        let servicesMenu = try XCTUnwrap(application.servicesMenu)
        XCTAssertEqual(windowMenu.title, "Window")
        XCTAssertEqual(helpMenu.title, "Help")
        XCTAssertEqual(servicesMenu.title, "Services")
        XCTAssertFalse(windowMenu.autoenablesItems)
        XCTAssertTrue(helpMenu.autoenablesItems)

        let item = try XCTUnwrap(windowMenu.items.first)
        XCTAssertEqual(item.identifier?.rawValue, "show-window")
        XCTAssertEqual(item.state, .mixed)
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(item.isHidden)
        XCTAssertTrue(item.isAlternate)
        XCTAssertEqual(item.indentationLevel, 2)
        XCTAssertTrue(item.allowsKeyEquivalentWhenHidden)
        XCTAssertEqual(item.keyEquivalent, "w")
        XCTAssertTrue(item.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(item.keyEquivalentModifierMask.contains(.shift))
        XCTAssertEqual(item.toolTip, "Show the main window")
        let nativeImage = try XCTUnwrap(item.image)
        XCTAssertTrue(nativeImage.isTemplate)
        XCTAssertEqual(nativeImage.size, NSSize(width: 16, height: 8))

        item.isEnabled = true
        item.isHidden = false
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(application.sendAction(action, to: item.target, from: item))
        XCTAssertEqual(actionCount, 1)

        controller.menuNeedsUpdate(windowMenu)
        XCTAssertEqual(refreshDelegate.requestedMenuIDs.count, 1)
        XCTAssertEqual(refreshDelegate.requestedMenuIDs[0], "window")
    }
}
#endif
