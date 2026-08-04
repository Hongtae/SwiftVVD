import XCTest
@testable import VUI

final class WindowContentScaleTests: XCTestCase {
    // ASSERTIONS caHostingLayerContentScalePropagationObserved
    @MainActor
    func testHostContentScaleUpdatesSceneEnvironmentBeforeGraphEvaluation() throws {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(WindowContentScaleTests.self)
            )
        )
        let windowContext = WindowContext(
            sceneResources: controller.sceneResources
        )
        controller.windowContext = windowContext

        XCTAssertEqual(controller.environment.displayScale, 1)
        XCTAssertNil(controller.contentScaleFactorOverride)
        controller.environment._contentScaleFactorOverride(2)
        XCTAssertEqual(
            windowContext.configuration.contentScaleFactorOverride,
            2
        )

        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 320, height: 240),
            shouldDrawFrame: false
        ) { _, handler in
            _ = handler
        }

        XCTAssertEqual(controller.environment.displayScale, 2)
        XCTAssertEqual(controller.environment._contentScaleFactor, 2)
        let graphScale = try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.envAttr).value.displayScale
        }
        XCTAssertEqual(graphScale, 2)
        let graphContentScale = try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.envAttr)
                .value._contentScaleFactor
        }
        XCTAssertEqual(graphContentScale, 2)
    }

    @MainActor
    func testHostContentScaleTransitionsAreAppliedInBothDirections() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(WindowContentScaleTests.self)
            )
        )
        let windowContext = WindowContext(
            sceneResources: controller.sceneResources
        )
        controller.windowContext = windowContext
        let withGraphicsContext: WindowContext.WithGraphicsContext = { _, handler in
            _ = handler
        }

        for (tick, scale) in [CGFloat(1), 2, 1, 3, 1].enumerated() {
            controller.contentScaleFactor = scale
            controller.updateFrame(
                tick: UInt64(tick),
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 320, height: 240),
                shouldDrawFrame: false,
                withGraphicsContext
            )
            XCTAssertEqual(
                controller.environment.displayScale,
                scale,
                "Transition at tick \(tick)"
            )
            XCTAssertEqual(
                controller.environment._contentScaleFactor,
                scale,
                "Content-scale transition at tick \(tick)"
            )
        }

        controller.contentScaleFactorOverride = nil
        XCTAssertNil(windowContext.configuration.contentScaleFactorOverride)
        XCTAssertEqual(controller.contentScaleFactor, 1)
        controller.updateFrame(
            tick: 5,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 320, height: 240),
            shouldDrawFrame: false,
            withGraphicsContext
        )
        XCTAssertEqual(controller.environment.displayScale, 1)
    }

    @MainActor
    func testContentScaleOverridePropagatesToPresentationDescendants() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowContentScaleTests.self, index: 1)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.windowContext = WindowContext(sceneResources: root.sceneResources)
        root.contentScaleFactor = 3

        let child = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: false
        )
        root.addPresentationChild(child: child)

        let nestedChild = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: false
        )
        child.addPresentationChild(child: nestedChild)

        for controller in [child, nestedChild] {
            XCTAssertEqual(controller.contentScaleFactorOverride, 3)
            XCTAssertEqual(controller.contentScaleFactor, 3)
        }

        root.contentScaleFactor = 1
        for controller in [child, nestedChild] {
            XCTAssertEqual(controller.contentScaleFactorOverride, 1)
            XCTAssertEqual(controller.contentScaleFactor, 1)
        }

        root.contentScaleFactorOverride = nil
        for controller in [child, nestedChild] {
            XCTAssertNil(controller.contentScaleFactorOverride)
            XCTAssertEqual(controller.contentScaleFactor, 1)
        }
    }

    // ASSERTIONS caHostingLayerContentScalePropagationObserved
    @MainActor
    func testOverlayUpdateSynchronizesTypefaceResourceScaleBeforeGraphEvaluation() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowContentScaleTests.self, index: 3)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.windowContext = WindowContext(sceneResources: root.sceneResources)
        root.contentScaleFactor = 3

        let child = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: false
        )
        root.addPresentationChild(child: child)
        var redraw = false
        let withGraphicsContext: WindowContext.WithGraphicsContext = {
            _, handler in
            _ = handler
        }

        XCTAssertEqual(child.sceneResources.contentScaleFactor, 1)
        child.updateView(
            tick: 0,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 320, height: 240),
            redraw: &redraw,
            withGraphicsContext
        )
        XCTAssertEqual(child.sceneResources.contentScaleFactor, 3)

        root.contentScaleFactor = 1
        child.updateView(
            tick: 1,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 320, height: 240),
            redraw: &redraw,
            withGraphicsContext
        )
        XCTAssertEqual(child.sceneResources.contentScaleFactor, 1)
    }

    // ASSERTIONS viewGraphHostEnvironmentWrapperOwnershipObserved
    @MainActor
    func testPlatformModalEnvironmentUsesInheritedEffectiveContentScale() throws {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowContentScaleTests.self, index: 2)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.windowContext = WindowContext(sceneResources: root.sceneResources)
        root.contentScaleFactor = 3

        var sourceEnvironment = EnvironmentValues()
        sourceEnvironment.displayScale = 1
        var sourcePhase = Phase()
        sourcePhase.resetSeed = 5
        let content = AnyView(EmptyView())
        let child = root.viewGraph.data.withCurrent {
            let sourceGraph = root.viewGraph.data.graph
            let contentAttribute: Attribute<AnyView> = sourceGraph.makeInput(
                value: content
            )
            return ModalWindowController(
                crossGraphContent: contentAttribute,
                sourceGraph: sourceGraph,
                environment: sourceEnvironment,
                viewPhase: ViewGraphHost.Phase(base: sourcePhase),
                scene: scene,
                parentController: root,
                usesPlatformWindow: true
            )
        }
        root.addModal(
            child: child,
            session: .sheet(SheetPreference(
                content: content,
                onDismiss: nil,
                namespaceID: Namespace.ID(id: 92_002),
                itemID: nil,
                drawsBackground: true,
                placement: .automatic,
                activeInspector: nil,
                usesPlatformWindow: true
            ))
        )
        child.windowContext = WindowContext(
            sceneResources: child.sceneResources,
            configurationOverride: child.configurationOverride
        )

        child.setPresentationEnvironment(
            sourceEnvironment,
            viewPhase: ViewGraphHost.Phase(base: sourcePhase)
        )
        child.viewGraph.data.withCurrent {
            child.viewGraph.data.graph.inbox.drain()
        }

        XCTAssertEqual(child.contentScaleFactor, 3)
        XCTAssertEqual(child.environment.displayScale, 3)
        XCTAssertEqual(child.environment._contentScaleFactor, 3)
        XCTAssertEqual(
            try child.viewGraph.data.withCurrent {
                try XCTUnwrap(child.viewGraph.envAttr).value.displayScale
            },
            3
        )
        XCTAssertEqual(
            child.viewGraph.parentPhase?.rawValue,
            sourcePhase.rawValue
        )

        root.contentScaleFactor = 1
        child.viewGraph.data.withCurrent {
            child.updateEnvironment()
        }

        XCTAssertEqual(child.contentScaleFactor, 1)
        XCTAssertEqual(child.environment.displayScale, 1)
        XCTAssertEqual(child.environment._contentScaleFactor, 1)
        XCTAssertEqual(
            try child.viewGraph.data.withCurrent {
                try XCTUnwrap(child.viewGraph.envAttr).value.displayScale
            },
            1
        )
    }
}
