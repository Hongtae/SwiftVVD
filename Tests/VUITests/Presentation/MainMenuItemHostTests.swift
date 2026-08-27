import XCTest
@testable import VUI

final class MainMenuItemHostTests: XCTestCase {
    func testHostRequestsSemanticMenuAndFocusOutputs() {
        // ASSERTIONS commandsMainMenuHostGraphContractObserved
        let host = MainMenuItemHost(
            item: makeItem(content: AnyView(EmptyView())),
            environment: EnvironmentValues()
        )

        XCTAssertEqual(
            host.viewGraph.requestedOutputs,
            [.platformItemList, .focus]
        )
    }

    func testHostCollectsActionsShortcutsAndNestedItems() throws {
        // ASSERTIONS commandsMainMenuHostRecursiveTransformObserved
        var invoked = false
        let content = TupleView((
            Button("Run") { invoked = true }
                .keyboardShortcut("K", modifiers: [.command, .shift]),
            Menu("More") {
                Button("Nested") {}
            }
        ))
        let host = MainMenuItemHost(
            item: makeItem(content: AnyView(content)),
            environment: EnvironmentValues()
        )

        let list = host.menuItems()
        XCTAssertEqual(list.items.count, 2)

        let action = list.items[0]
        XCTAssertEqual((action.label ?? action.text)?.string, "Run")
        XCTAssertTrue(action.scaleDownMenuImage)
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.keyboardShortcut?.key, "K")
        XCTAssertEqual(
            action.keyboardShortcut?.modifiers,
            [.command, .shift]
        )
        try XCTUnwrap(action.selectionBehavior?.onSelect)()
        XCTAssertTrue(invoked)

        let submenu = list.items[1]
        XCTAssertEqual((submenu.label ?? submenu.text)?.string, "More")
        XCTAssertTrue(submenu.scaleDownMenuImage)
        let nested = try XCTUnwrap(submenu.children)
        XCTAssertEqual(nested.items.count, 1)
        XCTAssertEqual(
            (nested.items[0].label ?? nested.items[0].text)?.string,
            "Nested"
        )
        XCTAssertTrue(nested.items[0].scaleDownMenuImage)
    }

    func testHostDefersRootReplacementUntilOutputUpdate() {
        let delegate = MenuHostDelegateRecorder()
        let identifier = MainMenuItem.Identifier.custom(UUID())
        let host = MainMenuItemHost(
            item: makeItem(
                id: identifier,
                content: AnyView(Button("Initial") {})
            ),
            environment: EnvironmentValues()
        )
        host.delegate = delegate

        XCTAssertEqual(firstTitle(in: host.menuItems()), "Initial")

        host.update(
            item: makeItem(
                id: identifier,
                content: AnyView(Button("Updated") {})
            ),
            environment: EnvironmentValues()
        )
        XCTAssertGreaterThan(delegate.changeCount, 0)
        let retainedList = host.viewGraph.data.withCurrent {
            host.viewGraph.platformItemList() ?? PlatformItemList()
        }
        XCTAssertEqual(firstTitle(in: retainedList), "Initial")
        XCTAssertEqual(firstTitle(in: host.menuItems()), "Updated")
    }

    func testHostRematerializesContentWhenFocusedValuesChange() {
        // ASSERTIONS commandsMenuHostFocusInvalidationObserved
        let host = MainMenuItemHost(
            item: makeItem(content: AnyView(FocusedMenuButton())),
            environment: EnvironmentValues(),
            focusedValues: makeFocusedValues("Root")
        )

        XCTAssertEqual(firstTitle(in: host.menuItems()), "Root")

        host.updateFocusedValues(makeFocusedValues("Presentation"))

        XCTAssertEqual(firstTitle(in: host.menuItems()), "Presentation")
    }

    private func makeItem(
        id: MainMenuItem.Identifier = .custom(UUID()),
        content: AnyView
    ) -> MainMenuItem {
        MainMenuItem(
            name: "Fixture",
            id: id,
            groups: [CommandAccumulator.Result(viewContent: content)]
        )
    }

    private func firstTitle(in list: PlatformItemList) -> String? {
        guard let item = list.items.first else {
            return nil
        }
        return (item.label ?? item.text)?.string
    }

    private func makeFocusedValues(_ title: String) -> FocusedValues {
        FocusedValues(
            resolving: FocusedValueList(
                items: [
                    FocusedValueList.Item(
                        version: DisplayList.Version(forUpdate: ()),
                        isFocused: true,
                        update: { values in
                            values.menuHostFocusedTitle = title
                        }
                    )
                ]
            )
        )
    }
}

private struct MenuHostFocusedTitleKey: FocusedValueKey {
    typealias Value = String
}

private extension FocusedValues {
    var menuHostFocusedTitle: String? {
        get { self[MenuHostFocusedTitleKey.self] }
        set { self[MenuHostFocusedTitleKey.self] = newValue }
    }
}

private struct FocusedMenuButton: View {
    @FocusedValue(\.menuHostFocusedTitle) private var title

    var body: some View {
        Button(title ?? "nil") {}
    }
}

private final class MenuHostDelegateRecorder: MainMenuItemHostDelegate {
    var changeCount = 0

    func menuHostDidChangeMenuItems(_ host: MainMenuItemHost) {
        changeCount += 1
    }
}
