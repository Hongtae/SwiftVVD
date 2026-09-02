import XCTest
@testable import VUI
@testable import VVD

final class TouchEventRoutingTests: XCTestCase {
    @MainActor
    func testPlatformTouchDataReachesTouchEventListener() throws {
        let recorder = TouchEventRecorder()
        let controller = WindowController(
            content: TouchEventRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TouchEventRoutingRoot.self)
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

        XCTAssertTrue(controller.handleMouseEvent(event: VVD.MouseEvent(
            type: .buttonDown,
            device: .touch,
            deviceID: 7,
            buttonID: 0,
            modifiers: [.option, .command],
            location: CGPoint(x: 210, y: 120),
            tilt: CGPoint(x: 0.75, y: 0.5),
            pressure: 2.5,
            timestamp: 3,
            touchData: TouchEventData(
                majorRadius: 12.5,
                majorRadiusTolerance: 1.25,
                maximumPossiblePressure: 4
            )
        )))

        XCTAssertEqual(recorder.events.count, 1)
        let event = try XCTUnwrap(recorder.events.first)
        XCTAssertEqual(event.radius, 12.5)
        XCTAssertEqual(event.force, 2.5)
        XCTAssertEqual(event.maximumPossibleForce, 4)
        XCTAssertEqual(event.altitude.radians, 0.5)
        XCTAssertEqual(event.azimuth.radians, 0.75)
        XCTAssertEqual(event.touchType, .direct)
        XCTAssertEqual(event.modifiers, [.option, .command])
    }

    @MainActor
    func testPlatformMouseMetadataReachesMouseEventListener() throws {
        let recorder = MouseEventRecorder()
        let controller = WindowController(
            content: MouseEventRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MouseEventRoutingRoot.self)
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

        XCTAssertTrue(controller.handleMouseEvent(event: VVD.MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 3,
            modifiers: [.shift, .control],
            location: CGPoint(x: 210, y: 120),
            timestamp: 3
        )))

        XCTAssertEqual(recorder.events.count, 1)
        let event = try XCTUnwrap(recorder.events.first)
        XCTAssertEqual(event.phase, .began)
        XCTAssertEqual(event.clickCount, 3)
        XCTAssertEqual(event.modifiers, [.shift, .control])
    }

    @MainActor
    func testMissingTouchDataUsesConservativeZeroRadius() throws {
        let recorder = TouchEventRecorder()
        let controller = WindowController(
            content: TouchEventRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TouchEventRoutingRoot.self)
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

        XCTAssertTrue(controller.handleMouseEvent(event: VVD.MouseEvent(
            type: .buttonDown,
            device: .touch,
            deviceID: 8,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 4
        )))

        XCTAssertEqual(recorder.events.count, 1)
        let event = try XCTUnwrap(recorder.events.first)
        XCTAssertEqual(event.radius, 0)
        XCTAssertEqual(event.maximumPossibleForce, 1)
    }

    @MainActor
    // ASSERTIONS appKitRecognizerAdmittedFailureCancellationObserved
    func testCancelledTouchTerminatesTheActiveEventAsFailed() throws {
        let recorder = TouchEventRecorder()
        let controller = WindowController(
            content: TouchEventRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TouchEventRoutingRoot.self)
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

        XCTAssertTrue(controller.handleMouseEvent(event: VVD.MouseEvent(
            type: .buttonDown,
            device: .touch,
            deviceID: 9,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 5
        )))
        _ = controller.handleMouseEvent(event: VVD.MouseEvent(
            type: .cancelled,
            device: .touch,
            deviceID: 9,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 6
        ))

        XCTAssertEqual(recorder.phases, [.began, .failed])
    }

    @MainActor
    func testStylusPointingAndCancellationDriveHoverLifecycle() {
        let recorder = HoverStateRecorder()
        let controller = WindowController(
            content: HoverRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(HoverRoutingRoot.self)
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

        controller.onMouseEvent(event: VVD.MouseEvent(
            type: .pointing,
            device: .stylus,
            deviceID: 19,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 7
        ))
        controller.onMouseEvent(event: VVD.MouseEvent(
            type: .cancelled,
            device: .stylus,
            deviceID: 19,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 8
        ))

        XCTAssertEqual(recorder.states, [true, false])
    }

    @MainActor
    func testDirectTouchDoesNotDriveHoverLifecycle() {
        let recorder = HoverStateRecorder()
        let controller = WindowController(
            content: HoverRoutingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(HoverRoutingRoot.self)
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

        controller.onMouseEvent(event: VVD.MouseEvent(
            type: .buttonDown,
            device: .touch,
            deviceID: 20,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 9
        ))
        controller.onMouseEvent(event: VVD.MouseEvent(
            type: .move,
            device: .touch,
            deviceID: 20,
            buttonID: 0,
            location: CGPoint(x: 211, y: 120),
            timestamp: 10
        ))
        controller.onMouseEvent(event: VVD.MouseEvent(
            type: .buttonUp,
            device: .touch,
            deviceID: 20,
            buttonID: 0,
            location: CGPoint(x: 211, y: 120),
            timestamp: 11
        ))

        XCTAssertTrue(recorder.states.isEmpty)
    }

    @MainActor
    func testAutomaticContextMenuPolicyTreatsStylusBarrelAsSecondary() throws {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TouchEventRoutingTests.self)
            )
        )

        try controller.viewGraph.data.withCurrent {
            let graph = controller.viewGraph.data.graph
            let environment = graph.makeInput(value: EnvironmentValues())
            let phase = try XCTUnwrap(controller.viewGraph.phaseAttr)
            let itemList = graph.makeInput(value: PlatformItemList())
            let responder = AGSubgraph.withCurrent(
                controller.viewGraph.data.rootSubgraph
            ) {
                ContextMenuResponder(
                    inputs: makeContextMenuViewInputs(
                        graph: graph,
                        environment: environment,
                        phase: phase
                    ),
                    itemList: itemList.asWeak(),
                    environment: environment,
                    phase: phase
                )
            }

            XCTAssertEqual(
                responder.resolvedTriggerPolicy(for: .stylus, buttonID: 0),
                .longPress
            )
            XCTAssertEqual(
                responder.resolvedTriggerPolicy(for: .stylus, buttonID: 1),
                .secondaryDown
            )
        }
    }
}

private final class TouchEventRecorder: @unchecked Sendable {
    var events: [TouchEvent] = []
    var phases: [EventPhase] = []
}

private final class MouseEventRecorder: @unchecked Sendable {
    var events: [VUI.MouseEvent] = []
}

private final class HoverStateRecorder: @unchecked Sendable {
    var states: [Bool] = []
}

private struct TouchEventRoutingRoot: View {
    let recorder: TouchEventRecorder

    var body: some View {
        Color.green
            .frame(width: 420, height: 240)
            .gesture(
                ModifierGesture(
                    content: EventListener<TouchEvent>(),
                    modifier: CallbacksGesture(callbacks: FullGestureCallbacks<TouchEvent>(
                        possible: nil,
                        changed: { event in
                            recorder.events.append(event)
                            recorder.phases.append(event.phase)
                        },
                        ended: { event in
                            recorder.events.append(event)
                            recorder.phases.append(event.phase)
                        },
                        failed: {
                            recorder.phases.append(.failed)
                        }
                    ))
                )
            )
    }
}

private struct MouseEventRoutingRoot: View {
    let recorder: MouseEventRecorder

    var body: some View {
        Color.green
            .frame(width: 420, height: 240)
            .gesture(
                ModifierGesture(
                    content: EventListener<VUI.MouseEvent>(),
                    modifier: CallbacksGesture(
                        callbacks: FullGestureCallbacks<VUI.MouseEvent>(
                            possible: nil,
                            changed: { recorder.events.append($0) },
                            ended: { recorder.events.append($0) },
                            failed: nil
                        )
                    )
                )
            )
    }
}

private struct HoverRoutingRoot: View {
    let recorder: HoverStateRecorder

    var body: some View {
        Color.green
            .frame(width: 420, height: 240)
            .onHover { recorder.states.append($0) }
    }
}

private func makeContextMenuViewInputs(
    graph: _AGGraph,
    environment: Attribute<EnvironmentValues>,
    phase: Attribute<_GraphInputs.Phase>
) -> _ViewInputs {
    _ViewInputs(
        base: _GraphInputs(
            time: graph.makeInput(value: Time.zero),
            phase: phase,
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        ),
        customInputs: PropertyList(),
        preferences: PreferencesInputs(
            keys: PreferenceKeys(),
            hostKeys: graph.makeInput(value: PreferenceKeys())
        ),
        transform: graph.makeInput(value: ViewTransform.identity),
        position: graph.makeInput(value: CGPoint.zero),
        containerPosition: graph.makeInput(value: CGPoint.zero),
        size: graph.makeInput(
            value: ViewSize(CGSize(width: 100, height: 40))
        ),
        safeAreaInsets: OptionalAttribute(),
        containerSize: OptionalAttribute(),
        stackOrientation: nil
    )
}
