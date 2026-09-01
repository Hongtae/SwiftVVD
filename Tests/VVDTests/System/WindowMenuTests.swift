import XCTest
@testable import VVD

final class WindowMenuTests: XCTestCase {
    @MainActor
    func testSnapshotBuilderPreservesMenuAndElementOrder() {
        let includesRecent = true
        let snapshot = WindowMenu {
            WindowMenu.Menu(id: "application", title: "Application", role: .application) {
                WindowMenu.Item(id: "about", title: "About")
            }
            WindowMenu.Menu(id: "file", title: "File", role: .file) {
                WindowMenu.Item(
                    id: "open",
                    title: "Open…",
                    shortcut: WindowMenu.Shortcut("o")
                )
                WindowMenu.Element.separator
                if includesRecent {
                    WindowMenu.Menu(id: "recent", title: "Open Recent") {
                        WindowMenu.Item(id: "document", title: "Document")
                    }
                }
            }
        }

        XCTAssertEqual(snapshot.menus.map(\.id), ["application", "file"])
        XCTAssertEqual(snapshot.menus.map(\.role), [.application, .file])

        let fileElements = snapshot.menus[1].elements
        XCTAssertEqual(fileElements.count, 3)
        guard case let .item(open) = fileElements[0],
              case .separator = fileElements[1],
              case let .submenu(recent) = fileElements[2] else {
            return XCTFail("Unexpected menu element order")
        }
        XCTAssertEqual(open.id, "open")
        XCTAssertEqual(open.shortcut, WindowMenu.Shortcut("o"))
        XCTAssertEqual(recent.id, "recent")
        XCTAssertEqual(recent.elements.count, 1)
    }

    @MainActor
    func testItemActionAndPresentationStateRemainInSnapshot() {
        var invocationCount = 0
        let item = WindowMenu.Item(
            id: "toggle-sidebar",
            title: "Show Sidebar",
            imageIsTemplate: true,
            scalesImageToFit: false,
            state: .mixed,
            isEnabled: false,
            isHidden: true,
            isAlternate: true,
            indentationLevel: 2,
            allowsShortcutWhenHidden: true,
            shortcut: WindowMenu.Shortcut(.f8, modifiers: [.control]),
            toolTip: "Toggle the sidebar"
        ) {
            invocationCount += 1
        }

        XCTAssertEqual(item.id, "toggle-sidebar")
        XCTAssertTrue(item.imageIsTemplate)
        XCTAssertFalse(item.scalesImageToFit)
        XCTAssertEqual(item.state, .mixed)
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(item.isHidden)
        XCTAssertTrue(item.isAlternate)
        XCTAssertEqual(item.indentationLevel, 2)
        XCTAssertTrue(item.allowsShortcutWhenHidden)
        XCTAssertEqual(
            item.shortcut,
            WindowMenu.Shortcut(.f8, modifiers: [.control])
        )
        XCTAssertEqual(item.toolTip, "Toggle the sidebar")

        item.action?()
        XCTAssertEqual(invocationCount, 1)
    }

}
