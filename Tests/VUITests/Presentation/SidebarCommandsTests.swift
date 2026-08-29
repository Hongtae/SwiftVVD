import XCTest
@testable import VUI
import class VVD.AudioDeviceContext
import class VVD.GraphicsDeviceContext

final class SidebarCommandsTests: XCTestCase {
    func testSidebarCommandsFollowActiveRootNavigationOwner() throws {
        // ASSERTIONS commandsSidebarBodyDisassemblyObserved
        // ASSERTIONS commandsSidebarResponderActionObserved
        // ASSERTIONS commandsSidebarMenuRuntimeObserved
        // ASSERTIONS commandsSidebarActiveRootRuntimeObserved
        // ASSERTIONS navigationSplitViewSidebarResponderRuntimeObserved
        let appGraph = AppGraph(app: SidebarCommandsTestApp())
        var rootEnvironment = EnvironmentValues.tracking()
        rootEnvironment.defaultFontRenderingMode = .vector()
        _ = _AGGraph.withCurrent(appGraph.graph) {
            appGraph.rootEnvironmentAttr.setValue(rootEnvironment)
        }
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = SidebarCommandsTestAppContext(
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

        let splitRoot = try XCTUnwrap(roots.first(where: {
            $0.resolvedFocusedValues.rootSidebarCommandContext != nil
        }))
        let plainRoot = try XCTUnwrap(roots.first(where: {
            $0 !== splitRoot
        }))

        windowsController.rootWindowDidActivate(splitRoot)
        updateAll(roots, startingAt: 20)

        var item = try sidebarItem(in: plainRoot)
        XCTAssertEqual(itemTitle(item), "Hide Sidebar")
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.keyboardShortcut?.key, "s")
        XCTAssertEqual(
            item.keyboardShortcut?.modifiers,
            [.command, .control]
        )

        try XCTUnwrap(item.selectionBehavior?.onSelect)()
        updateAll(roots, startingAt: 40)

        XCTAssertFalse(
            try XCTUnwrap(
                splitRoot.resolvedFocusedValues.rootSidebarCommandContext
            ).isSidebarVisible
        )
        item = try sidebarItem(in: splitRoot)
        XCTAssertEqual(itemTitle(item), "Show Sidebar")
        XCTAssertTrue(item.isEnabled)

        windowsController.rootWindowDidActivate(plainRoot)
        updateAll(roots, startingAt: 60)
        item = try sidebarItem(in: splitRoot)
        XCTAssertEqual(itemTitle(item), "Show Sidebar")
        XCTAssertFalse(item.isEnabled)
        XCTAssertNil(item.selectionBehavior?.onSelect)

        windowsController.rootWindowDidActivate(splitRoot)
        updateAll(roots, startingAt: 80)
        item = try sidebarItem(in: plainRoot)
        XCTAssertEqual(itemTitle(item), "Show Sidebar")
        XCTAssertTrue(item.isEnabled)

        try XCTUnwrap(item.selectionBehavior?.onSelect)()
        updateAll(roots, startingAt: 100)
        XCTAssertTrue(
            try XCTUnwrap(
                splitRoot.resolvedFocusedValues.rootSidebarCommandContext
            ).isSidebarVisible
        )
        XCTAssertEqual(
            itemTitle(try sidebarItem(in: splitRoot)),
            "Hide Sidebar"
        )
    }

    private func sidebarItem(
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
        return try XCTUnwrap(flattened(host.menuItems().items).first(where: {
            $0.keyboardShortcut?.key == "s"
                && $0.keyboardShortcut?.modifiers == [.command, .control]
        }))
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

    private func updateAll(
        _ roots: [WindowController],
        startingAt tick: Int
    ) {
        for (offset, root) in roots.enumerated() {
            let firstTick = tick + offset * 8
            update(root, ticks: firstTick..<(firstTick + 8))
        }
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
                contentSize: CGSize(width: 720, height: 360),
                redraw: &redraw
            ) { _, _ in }
        }
    }
}

private struct SidebarCommandsTestApp: App {
    init() {}

    var body: some Scene {
        Window("Sidebar root", id: "sidebar-root") {
            SidebarCommandsSplitRoot()
        }
        .commandMenuPresentationStyle(.window)
        .commands { SidebarCommands() }

        Window("Plain root", id: "sidebar-plain-root") {
            Text("Plain")
        }
        .commandMenuPresentationStyle(.window)
    }
}

private struct SidebarCommandsSplitRoot: View {
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            Text("Sidebar")
        } detail: {
            Text("Detail")
        }
    }
}

private final class SidebarCommandsTestAppContext: AppContext {
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

    func checkWindowActivities() {}
}
