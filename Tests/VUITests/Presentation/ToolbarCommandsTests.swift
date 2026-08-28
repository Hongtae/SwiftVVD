import XCTest
@testable import VUI
import class VVD.AudioDeviceContext
import class VVD.GraphicsDeviceContext

final class ToolbarCommandsTests: XCTestCase {
    func testToolbarCommandsFollowActiveRootToolbarState() throws {
        // ASSERTIONS commandsToolbarBodyDisassemblyObserved
        // ASSERTIONS commandsToolbarResponderActionObserved
        // ASSERTIONS commandsToolbarMenuRuntimeObserved
        // ASSERTIONS commandsToolbarRootHostLifetimeObserved
        let appGraph = AppGraph(app: ToolbarCommandsTestApp())
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = ToolbarCommandsTestAppContext(
            windowsController: windowsController
        )
        defer { appContext = previousAppContext }
        windowsController.syncWindowControllers(
            sceneListAttr: appGraph.sceneListAttr,
            commandsListAttr: appGraph.commandsListAttr,
            rootEnvironmentAttr: appGraph.rootEnvironmentAttr,
            focusedValuesAttr: appGraph.focusedValuesAttr,
            in: appGraph.graph
        )

        let root = try XCTUnwrap(
            windowsController.allWindowControllers.first
        )
        update(root, ticks: 0..<4)
        windowsController.rootWindowDidActivate(root)
        update(root, ticks: 4..<8)

        var items = try toolbarCommandItems(in: root)
        var toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Hide Toolbar"
        }))
        var customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(customize.isEnabled)
        XCTAssertEqual(toggle.keyboardShortcut?.key, "t")
        XCTAssertEqual(
            toggle.keyboardShortcut?.modifiers,
            [.command, .option]
        )

        try XCTUnwrap(toggle.selectionBehavior?.onSelect)()
        update(root, ticks: 8..<14)

        items = try toolbarCommandItems(in: root)
        toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Show Toolbar"
        }))
        customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(customize.isEnabled)

        try XCTUnwrap(toggle.selectionBehavior?.onSelect)()
        update(root, ticks: 14..<20)
        items = try toolbarCommandItems(in: root)
        customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        try XCTUnwrap(customize.selectionBehavior?.onSelect)()
        update(root, ticks: 20..<26)

        let context = try XCTUnwrap(
            root.resolvedFocusedValues.rootToolbarCommandContext
        )
        XCTAssertEqual(context.visibility, .visible)
        XCTAssertFalse(context.canToggleVisibility)
        XCTAssertTrue(context.canCustomize)
        XCTAssertTrue(context.customizationIsPresented)

        items = try toolbarCommandItems(in: root)
        toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Hide Toolbar"
        }))
        customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertTrue(customize.isEnabled)
    }

    func testToolbarCommandActionsDispatchToTheActiveRoot() throws {
        let appGraph = AppGraph(app: ToolbarCommandsMultiRootTestApp())
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = ToolbarCommandsTestAppContext(
            windowsController: windowsController
        )
        defer { appContext = previousAppContext }
        windowsController.syncWindowControllers(
            sceneListAttr: appGraph.sceneListAttr,
            commandsListAttr: appGraph.commandsListAttr,
            rootEnvironmentAttr: appGraph.rootEnvironmentAttr,
            focusedValuesAttr: appGraph.focusedValuesAttr,
            in: appGraph.graph
        )

        let roots = windowsController.allWindowControllers
        XCTAssertEqual(roots.count, 2)
        updateAll(roots, startingAt: 0)

        let customizableRoot = try XCTUnwrap(roots.first(where: {
            $0.resolvedFocusedValues.rootToolbarCommandContext?
                .canCustomize == true
        }))
        let plainRoot = try XCTUnwrap(roots.first(where: {
            $0 !== customizableRoot
                && $0.resolvedFocusedValues.rootToolbarCommandContext != nil
        }))

        windowsController.rootWindowDidActivate(plainRoot)
        updateAll(roots, startingAt: 10)

        var items = try toolbarCommandItems(in: customizableRoot)
        var toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Hide Toolbar"
        }))
        var customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertFalse(customize.isEnabled)

        // Even when selected from another root's presenter, the shared command
        // action must target the root that currently owns command focus.
        try XCTUnwrap(toggle.selectionBehavior?.onSelect)()
        updateAll(roots, startingAt: 20)
        XCTAssertEqual(
            customizableRoot.resolvedFocusedValues
                .rootToolbarCommandContext?.visibility,
            .visible
        )
        XCTAssertEqual(
            plainRoot.resolvedFocusedValues
                .rootToolbarCommandContext?.visibility,
            .hidden
        )

        items = try toolbarCommandItems(in: customizableRoot)
        toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Show Toolbar"
        }))
        customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertFalse(customize.isEnabled)

        windowsController.rootWindowDidActivate(customizableRoot)
        updateAll(roots, startingAt: 30)
        items = try toolbarCommandItems(in: plainRoot)
        toggle = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Hide Toolbar"
        }))
        customize = try XCTUnwrap(items.first(where: {
            itemTitle($0) == "Customize Toolbar…"
        }))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(customize.isEnabled)
    }

    private func toolbarCommandItems(
        in root: WindowController
    ) throws -> [PlatformItemList.Item] {
        let presenter = try XCTUnwrap(root.windowCommandMenuPresenter)
        let viewMenu = try XCTUnwrap(
            presenter.items.first(where: { $0.id == .view })
        )
        let host = MainMenuItemHost(
            item: viewMenu,
            environment: presenter.environment,
            focusedValues: root.resolvedFocusedValues
        )
        return flattened(host.menuItems().items)
    }

    private func flattened(
        _ items: [PlatformItemList.Item]
    ) -> [PlatformItemList.Item] {
        items.flatMap { item in
            [item]
                + flattened(item.children?.items ?? [])
                + flattened(item.labelGroupChildren?.items ?? [])
        }
    }

    private func itemTitle(_ item: PlatformItemList.Item) -> String? {
        (item.label ?? item.text)?.string
    }

    private func update(
        _ root: WindowController,
        ticks: Range<Int>
    ) {
        for tick in ticks {
            var redraw = false
            root.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: root.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 420, height: 260),
                redraw: &redraw
            ) { _, _ in }
        }
    }

    private func updateAll(
        _ roots: [WindowController],
        startingAt tick: Int
    ) {
        for (offset, root) in roots.enumerated() {
            update(
                root,
                ticks: (tick + offset * 6)..<(tick + offset * 6 + 6)
            )
        }
    }
}

private struct ToolbarCommandsTestApp: App {
    init() {}

    var body: some Scene {
        Window("Toolbar commands root", id: "toolbar-commands") {
            Text("Root")
                .toolbar(id: "root-toolbar") {
                    ToolbarItem(id: "first") {
                        Button("First") {}
                    }
                    ToolbarItem(id: "second", showsByDefault: false) {
                        Button("Second") {}
                    }
                }
        }
        .commandMenuPresentationStyle(.window)
        .commands { ToolbarCommands() }
    }
}

private struct ToolbarCommandsMultiRootTestApp: App {
    init() {}

    var body: some Scene {
        Window("Customizable toolbar root", id: "toolbar-first") {
            Text("First root")
                .toolbar(id: "first-toolbar") {
                    ToolbarItem(id: "first") {
                        Button("First") {}
                    }
                }
        }
        .commandMenuPresentationStyle(.window)
        .commands { ToolbarCommands() }

        Window("Plain toolbar root", id: "toolbar-second") {
            Text("Second root")
                .toolbar {
                    ToolbarItem {
                        Button("Second") {}
                    }
                }
        }
        .commandMenuPresentationStyle(.window)
    }
}

private final class ToolbarCommandsTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    let appWindowsController: AppWindowsController?
    private var resources: [URL: any DataProtocol] = [:]

    init(windowsController: AppWindowsController) {
        appWindowsController = windowsController
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }

    func checkWindowActivities() {
    }
}
