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
    func testAppKitWindowProvidesStableMenuController() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitWindowMenuTests",
                style: [.title],
                delegate: nil
            )
        )
        defer { window.close() }

        let first = try XCTUnwrap(window.menuController)
        let second = try XCTUnwrap(window.menuController)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject))

        let snapshot = WindowMenu(menus: [
            WindowMenu.Menu(
                id: "file",
                title: "File",
                role: .file,
                elements: [
                    .item(WindowMenu.Item(id: "close", title: "Close")),
                ]
            ),
        ])
        first.setMenu(snapshot)
        XCTAssertEqual(first.menu?.menus.first?.id, "file")

        first.setMenu(nil)
        XCTAssertNil(first.menu)
    }

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

    @MainActor
    func testSnapshotRefreshPreservesNativeIdentityAndUpdatesContents() throws {
        var originalActionCount = 0
        var refreshedActionCount = 0
        let window = try XCTUnwrap(
            makeWindow(name: "MenuIdentity", style: [.title], delegate: nil)
        )
        defer { window.close() }

        let controller = try XCTUnwrap(
            window.menuController as? AppKitWindowMenuController
        )
        controller.setMenu(WindowMenu {
            WindowMenu.Menu(id: "window", title: "Window", role: .window) {
                WindowMenu.Item(
                    id: "open",
                    title: "Open",
                    isEnabled: false
                ) {
                    originalActionCount += 1
                }
                WindowMenu.Menu(id: "recent", title: "Recent") {
                    WindowMenu.Item(id: "document", title: "Document")
                }
            }
        })

        let application = NSApplication.shared
        let root = try XCTUnwrap(application.mainMenu)
        let rootItem = try XCTUnwrap(root.items.first)
        let windowMenu = try XCTUnwrap(application.windowsMenu)
        let openItem = try XCTUnwrap(
            windowMenu.items.first {
                $0.identifier?.rawValue == "open"
            }
        )
        let recentItem = try XCTUnwrap(
            windowMenu.items.first {
                $0.identifier?.rawValue == "recent"
            }
        )
        let recentMenu = try XCTUnwrap(recentItem.submenu)
        let documentItem = try XCTUnwrap(recentMenu.items.first)

        // This is the refresh sequence used after NSMenuDelegate reports that
        // a visible menu needs updated semantic state.
        controller.menuNeedsUpdate(windowMenu)
        controller.setMenu(WindowMenu {
            WindowMenu.Menu(
                id: "window",
                title: "Workspace",
                role: .window,
                usesPlatformItemValidation: true
            ) {
                WindowMenu.Menu(id: "recent", title: "Recent Documents") {
                    WindowMenu.Item(id: "document", title: "Project.vvd")
                }
                WindowMenu.Item(
                    id: "open",
                    title: "Open Project…",
                    state: .on,
                    shortcut: WindowMenu.Shortcut(
                        "p",
                        modifiers: [.command, .shift]
                    )
                ) {
                    refreshedActionCount += 1
                }
                WindowMenu.Element.separator
                WindowMenu.Item(id: "close", title: "Close")
            }
        })

        let refreshedRoot = try XCTUnwrap(application.mainMenu)
        let refreshedWindowMenu = try XCTUnwrap(application.windowsMenu)
        XCTAssertTrue(refreshedRoot === root)
        XCTAssertTrue(refreshedRoot.items.first === rootItem)
        XCTAssertTrue(refreshedWindowMenu === windowMenu)
        XCTAssertEqual(rootItem.title, "Workspace")
        XCTAssertEqual(refreshedWindowMenu.title, "Workspace")
        XCTAssertTrue(refreshedWindowMenu.autoenablesItems)

        let refreshedRecentItem = try XCTUnwrap(
            refreshedWindowMenu.items.first {
                $0.identifier?.rawValue == "recent"
            }
        )
        let refreshedOpenItem = try XCTUnwrap(
            refreshedWindowMenu.items.first {
                $0.identifier?.rawValue == "open"
            }
        )
        XCTAssertTrue(refreshedRecentItem === recentItem)
        XCTAssertTrue(refreshedRecentItem.submenu === recentMenu)
        XCTAssertTrue(recentMenu.items.first === documentItem)
        XCTAssertEqual(recentItem.title, "Recent Documents")
        XCTAssertEqual(documentItem.title, "Project.vvd")
        XCTAssertTrue(refreshedOpenItem === openItem)
        XCTAssertEqual(openItem.title, "Open Project…")
        XCTAssertEqual(openItem.state, .on)
        XCTAssertTrue(openItem.isEnabled)
        XCTAssertEqual(openItem.keyEquivalent, "p")
        XCTAssertTrue(openItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(openItem.keyEquivalentModifierMask.contains(.shift))
        XCTAssertEqual(
            refreshedWindowMenu.items.map(\.identifier?.rawValue),
            ["recent", "open", nil, "close"]
        )

        let action = try XCTUnwrap(openItem.action)
        XCTAssertTrue(
            application.sendAction(action, to: openItem.target, from: openItem)
        )
        XCTAssertEqual(originalActionCount, 0)
        XCTAssertEqual(refreshedActionCount, 1)
    }
}
#endif
