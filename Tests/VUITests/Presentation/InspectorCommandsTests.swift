import XCTest
@testable import VUI

final class InspectorCommandsTests: XCTestCase {
    func testFocusedBindingReadsWritesAndProjectsResolvedBinding() {
        // ASSERTIONS commandsFocusedBindingRuntimeObserved
        let storage = InspectorPresentedStorage()
        let binding = Binding(
            get: { storage.value },
            set: { storage.value = $0 }
        )
        var focusedBinding = FocusedBinding<Bool>(
            \.inspectorCommandsTestBinding
        )

        XCTAssertNil(focusedBinding.wrappedValue)
        focusedBinding.wrappedValue = true
        XCTAssertFalse(storage.value)
        focusedBinding.projectedValue.wrappedValue = true
        XCTAssertFalse(storage.value)

        focusedBinding.content = .value(binding)
        XCTAssertEqual(focusedBinding.wrappedValue, false)
        focusedBinding.wrappedValue = true
        XCTAssertTrue(storage.value)
        focusedBinding.projectedValue.wrappedValue = false
        XCTAssertFalse(storage.value)

        focusedBinding.wrappedValue = nil
        XCTAssertFalse(storage.value)
    }

    func testInspectorCommandsFollowActiveRootFocusedBinding() throws {
        // ASSERTIONS commandsInspectorMenuRuntimeObserved
        // ASSERTIONS commandsRootGraphSourceOwnershipObserved
        let appGraph = AppGraph(app: InspectorCommandsTestApp())
        let windowsController = AppWindowsController()
        windowsController.syncWindowControllers(
            sceneListAttr: appGraph.sceneListAttr,
            commandsListAttr: appGraph.commandsListAttr,
            rootEnvironmentAttr: appGraph.rootEnvironmentAttr,
            focusedValuesAttr: appGraph.focusedValuesAttr,
            in: appGraph.graph
        )

        let roots = windowsController.allWindowControllers
        XCTAssertEqual(roots.count, 2)
        for (index, root) in roots.enumerated() {
            update(root, tick: UInt64(index))
            let item = try inspectorItem(in: root)
            XCTAssertEqual(itemTitle(item), "Show Inspector")
            XCTAssertFalse(item.isEnabled)
            XCTAssertEqual(item.keyboardShortcut?.key, "i")
            XCTAssertEqual(
                item.keyboardShortcut,
                builtInKeyboardShortcut(.inspectorToggle)
            )
        }

        let storage = InspectorPresentedStorage()
        let binding = Binding(
            get: { storage.value },
            set: { storage.value = $0 }
        )
        let activeRoot = try XCTUnwrap(roots.first)

        windowsController.rootWindowDidActivate(activeRoot)
        windowsController.updateWindowFocus(
            activeRoot,
            values: focusedValues(binding, versionSeed: 1)
        )
        updateAll(roots, startingAt: 10)

        for root in roots {
            let item = try inspectorItem(in: root)
            XCTAssertEqual(itemTitle(item), "Show Inspector")
            XCTAssertTrue(item.isEnabled)
        }

        let action = try XCTUnwrap(
            try inspectorItem(in: activeRoot).selectionBehavior?.onSelect
        )
        action()
        XCTAssertTrue(storage.value)

        windowsController.updateWindowFocus(
            activeRoot,
            values: focusedValues(binding, versionSeed: 2)
        )
        updateAll(roots, startingAt: 20)

        for root in roots {
            let item = try inspectorItem(in: root)
            XCTAssertEqual(itemTitle(item), "Hide Inspector")
            XCTAssertTrue(item.isEnabled)
        }

        let secondStorage = InspectorPresentedStorage()
        let secondBinding = Binding(
            get: { secondStorage.value },
            set: { secondStorage.value = $0 }
        )
        let inactiveRoot = try XCTUnwrap(
            roots.first(where: { $0 !== activeRoot })
        )

        // Background roots keep their latest values without replacing the
        // app-global command input until that root becomes active.
        windowsController.updateWindowFocus(
            inactiveRoot,
            values: focusedValues(secondBinding, versionSeed: 3)
        )
        updateAll(roots, startingAt: 30)
        for root in roots {
            XCTAssertEqual(
                itemTitle(try inspectorItem(in: root)),
                "Hide Inspector"
            )
        }

        windowsController.rootWindowDidActivate(inactiveRoot)
        windowsController.updateWindowFocus(
            inactiveRoot,
            values: focusedValues(secondBinding, versionSeed: 4)
        )
        updateAll(roots, startingAt: 40)
        for root in roots {
            let item = try inspectorItem(in: root)
            XCTAssertEqual(itemTitle(item), "Show Inspector")
            XCTAssertTrue(item.isEnabled)
        }
        XCTAssertTrue(storage.value)
        XCTAssertFalse(secondStorage.value)
    }

    private func focusedValues(
        _ binding: Binding<Bool>,
        versionSeed: Int
    ) -> FocusedValues {
        var values = FocusedValues()
        values.inspectorCommandsTestBinding = binding
        values.version = DisplayList.Version(value: versionSeed)
        return values
    }

    private func inspectorItem(
        in root: WindowController
    ) throws -> PlatformItemList.Item {
        let presenter = try XCTUnwrap(root.windowCommandMenuPresenter)
        let viewMenu = try XCTUnwrap(
            presenter.items.first(where: { $0.id == .view })
        )
        let host = MainMenuItemHost(
            item: viewMenu,
            environment: presenter.environment,
            focusedValues: root.resolvedFocusedValues
        )
        return try XCTUnwrap(host.menuItems().items.first)
    }

    private func itemTitle(_ item: PlatformItemList.Item) -> String? {
        (item.label ?? item.text)?.string
    }

    private func updateAll(
        _ roots: [WindowController],
        startingAt tick: UInt64
    ) {
        for (offset, root) in roots.enumerated() {
            update(root, tick: tick + UInt64(offset))
        }
    }

    private func update(_ root: WindowController, tick: UInt64) {
        var redraw = false
        root.updateView(
            tick: tick,
            delta: 1.0 / 60.0,
            date: root.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 320, height: 208),
            redraw: &redraw
        ) { _, _ in }
    }
}

private final class InspectorPresentedStorage {
    var value = false
}

private struct InspectorCommandsTestBindingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private extension FocusedValues {
    var inspectorCommandsTestBinding: Binding<Bool>? {
        get { self[InspectorCommandsTestBindingKey.self] }
        set {
            self[InspectorCommandsTestBindingKey.self] = newValue
            inspectorPresented = newValue
        }
    }
}

private struct InspectorCommandsTestApp: App {
    init() {}

    var body: some Scene {
        Window("Inspector commands first root", id: "inspector-first") {
            InspectorCommandsFirstRoot()
        }
        .commandMenuPresentationStyle(.window)
        .commands { InspectorCommands() }

        Window("Inspector commands second root", id: "inspector-second") {
            InspectorCommandsSecondRoot()
        }
        .commandMenuPresentationStyle(.window)
    }
}

private struct InspectorCommandsFirstRoot: View {
    var body: some View { EmptyView() }
}

private struct InspectorCommandsSecondRoot: View {
    var body: some View { EmptyView() }
}
