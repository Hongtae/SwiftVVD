import XCTest
@testable import VUI

final class NavigationSplitViewTests: XCTestCase {
    func testPublicVisibilityAndColumnValuesUseObservedRepresentations() throws {
        // ASSERTIONS navigationSplitViewPublicValueRuntimeObserved
        XCTAssertEqual(MemoryLayout<NavigationSplitViewVisibility>.size, 2)
        XCTAssertEqual(bytes(of: NavigationSplitViewVisibility.detailOnly), [0, 0])
        XCTAssertEqual(bytes(of: NavigationSplitViewVisibility.doubleColumn), [1, 0])
        XCTAssertEqual(bytes(of: NavigationSplitViewVisibility.all), [2, 0])
        XCTAssertEqual(bytes(of: NavigationSplitViewVisibility.automatic), [1, 1])

        for value in [
            NavigationSplitViewVisibility.detailOnly,
            .doubleColumn,
            .all,
            .automatic,
        ] {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(
                try JSONDecoder().decode(
                    NavigationSplitViewVisibility.self,
                    from: data
                ),
                value
            )
        }

        XCTAssertEqual(MemoryLayout<NavigationSplitViewColumn>.size, 1)
        XCTAssertEqual(bytes(of: NavigationSplitViewColumn.sidebar), [0])
        XCTAssertEqual(bytes(of: NavigationSplitViewColumn.content), [1])
        XCTAssertEqual(bytes(of: NavigationSplitViewColumn.detail), [2])
    }

    func testTwoAndThreeColumnVisibilityUseDistinctSidebarRules() {
        // ASSERTIONS navigationSplitViewThreeColumnRuntimeObserved
        var two = AnyNavigationSplitVisibility.twoColumn(.doubleColumn)
        XCTAssertTrue(two.isSidebarVisible)
        two.toggleSidebar()
        XCTAssertEqual(two, .twoColumn(.detailOnly))
        two.toggleSidebar()
        XCTAssertEqual(two, .twoColumn(.all))

        var three = AnyNavigationSplitVisibility.threeColumn(.doubleColumn)
        XCTAssertFalse(three.isSidebarVisible)
        three.toggleSidebar()
        XCTAssertEqual(three, .threeColumn(.all))
        three.toggleSidebar()
        XCTAssertEqual(three, .threeColumn(.doubleColumn))
    }

    func testNavigationSplitViewPublishesBoundSidebarContext() throws {
        // ASSERTIONS navigationSplitViewStyleOwnershipRuntimeObserved
        // ASSERTIONS navigationSplitViewSidebarResponderRuntimeObserved
        var capturedVisibility: Binding<NavigationSplitViewVisibility>?
        let controller = WindowController(
            content: NavigationSplitViewVisibilityHost {
                capturedVisibility = $0
            },
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NavigationSplitViewVisibilityHost.self)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        update(controller, ticks: 0..<8)

        var context = try XCTUnwrap(
            controller.resolvedFocusedValues.rootSidebarCommandContext
        )
        XCTAssertTrue(context.isSidebarVisible)
        XCTAssertEqual(try XCTUnwrap(capturedVisibility).wrappedValue, .all)

        context.toggleSidebar()
        update(controller, ticks: 8..<16)
        XCTAssertEqual(
            try XCTUnwrap(capturedVisibility).wrappedValue,
            .doubleColumn
        )
        context = try XCTUnwrap(
            controller.resolvedFocusedValues.rootSidebarCommandContext
        )
        XCTAssertFalse(context.isSidebarVisible)

        context.toggleSidebar()
        update(controller, ticks: 16..<24)
        XCTAssertEqual(try XCTUnwrap(capturedVisibility).wrappedValue, .all)
    }

    func testUnboundNavigationSplitViewOwnsSidebarVisibilityState() throws {
        let controller = WindowController(
            content: NavigationSplitView {
                Text("Sidebar")
            } detail: {
                Text("Detail")
            },
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NavigationSplitViewTests.self)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        update(controller, ticks: 0..<8)

        var context = try XCTUnwrap(
            controller.resolvedFocusedValues.rootSidebarCommandContext
        )
        XCTAssertTrue(context.isSidebarVisible)

        context.toggleSidebar()
        update(controller, ticks: 8..<16)
        context = try XCTUnwrap(
            controller.resolvedFocusedValues.rootSidebarCommandContext
        )
        XCTAssertFalse(context.isSidebarVisible)

        context.toggleSidebar()
        update(controller, ticks: 16..<24)
        XCTAssertTrue(
            try XCTUnwrap(
                controller.resolvedFocusedValues.rootSidebarCommandContext
            ).isSidebarVisible
        )
    }

    private func bytes<T>(of value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    private func update(
        _ controller: WindowController,
        ticks: Range<Int>
    ) {
        for tick in ticks {
            var redraw = false
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 720, height: 360),
                redraw: &redraw
            ) { _, _ in }
        }
    }
}

private struct NavigationSplitViewVisibilityHost: View {
    let capture: (Binding<NavigationSplitViewVisibility>) -> Void
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        let _ = capture($visibility)
        NavigationSplitView(columnVisibility: $visibility) {
            Text("Sidebar")
        } content: {
            Text("Content")
        } detail: {
            Text("Detail")
        }
    }
}
