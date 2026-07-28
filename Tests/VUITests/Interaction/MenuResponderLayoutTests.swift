import XCTest
@testable import VVD
@testable import VUI

final class MenuResponderLayoutTests: XCTestCase {
    // ASSERTIONS responderGeometryRuleOwnershipObserved
    @MainActor
    func testConditionalPrimaryActionMenuBuildsWithoutParentLayoutCycle() throws {
        let controller = WindowController(
            content: ConditionalPrimaryActionMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalPrimaryActionMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        XCTAssertNotNil(controller.viewGraph.rootLayoutComputer)
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let menuResponders = responderTree(rootResponder)
            .compactMap { $0 as? MenuDropdownResponder }
        XCTAssertEqual(menuResponders.count, 2)
        for responder in menuResponders {
            XCTAssertGreaterThan(responder.snapshotSize.value.width, 0)
            XCTAssertGreaterThan(responder.snapshotSize.value.height, 0)
        }
        let hoverResponders = responderTree(rootResponder)
            .compactMap { $0 as? HoverResponder }
        XCTAssertFalse(hoverResponders.isEmpty)
        for responder in hoverResponders {
            XCTAssertNotNil(responder.callback)
            XCTAssertGreaterThan(responder.snapshotSize.value.width, 0)
            XCTAssertGreaterThan(responder.snapshotSize.value.height, 0)
        }
    }

    // ASSERTIONS responderGeometryRuleOwnershipObserved
    @MainActor
    func testConditionalContinuousHoverPublishesItsInitialResponderState() throws {
        let controller = WindowController(
            content: ConditionalContinuousHoverRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalContinuousHoverRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let hoverResponder = try XCTUnwrap(
            responderTree(rootResponder).compactMap { $0 as? HoverResponder }.first
        )
        XCTAssertNotNil(hoverResponder.continuousCallback)
        XCTAssertGreaterThan(hoverResponder.snapshotSize.value.width, 0)
        XCTAssertGreaterThan(hoverResponder.snapshotSize.value.height, 0)
    }

    private func responderTree(_ responder: ViewResponder) -> [ViewResponder] {
        [responder] + responder.children.flatMap(responderTree)
    }
}

private struct ConditionalContinuousHoverRoot: View {
    var body: some View {
        HStack {
            hoverRegion(isVisible: true)
            Text("Sibling")
        }
        .padding(20)
    }

    @ViewBuilder
    private func hoverRegion(isVisible: Bool) -> some View {
        if isVisible {
            Text("Hover")
                .padding(8)
                .onContinuousHover { _ in }
        } else {
            EmptyView()
        }
    }
}

private struct ConditionalPrimaryActionMenuRoot: View {
    var body: some View {
        HStack {
            menu("Menu Action") {}
            menu("Open Menu")
        }
        .padding(20)
    }

    @ViewBuilder
    private func menu(
        _ title: String,
        primaryAction: (() -> Void)? = nil
    ) -> some View {
        if let primaryAction {
            Menu(title) {
                Button("Menu Item") {}
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu(title) {
                Button("Menu Item") {}
            }
        }
    }
}
