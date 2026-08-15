import XCTest
@testable import VUI
@testable import VVD

final class ButtonEventRoutingTests: XCTestCase {
    // ASSERTIONS gestureResponderBindEventHitTestObserved
    @MainActor
    func testWindowMouseClickInvokesButtonAction() {
        let counter = ButtonActionCounter()
        let controller = WindowController(
            content: ButtonEventRoutingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ButtonEventRoutingRoot.self)
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

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 1)
    }

    // ASSERTIONS appKitPressedPointerHoverIsolationObserved
    @MainActor
    func testWindowMouseDragDoesNotCancelButtonActionWithHoverEvent() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)
        let location = CGPoint(x: 210, y: 120)

        controller.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: location.x + 1, y: location.y),
            timestamp: 0.01
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: location.x + 1, y: location.y),
            timestamp: 0.02
        ))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 1)
    }

    // ASSERTIONS buttonPressedDragBoundaryBindingObserved
    @MainActor
    func testWindowMouseReleaseOutsideButtonDoesNotInvokeAction() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)
        let inside = CGPoint(x: 210, y: 120)
        let outside = CGPoint(x: 20, y: 20)
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: inside,
            timestamp: 0
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.01
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.02
        ))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 0)
    }

    // ASSERTIONS buttonPressedDragBoundaryBindingObserved
    func testEventBindingManagerRetainsPointerResponderOutsideInitialHitRegion() {
        let manager = EventBindingManager()
        let target = ResponderNode()
        let root = ButtonBindingRoot(target: target)
        let host = ButtonBindingHost(manager: manager, responderNode: root)
        manager.host = host
        manager.rootResponder = root
        let eventID = EventID(type: VUI.MouseEvent.self, serial: 41)

        XCTAssertTrue(manager.sendDownstream(
            [eventID: VUI.MouseEvent(
                timestamp: .zero,
                binding: nil,
                button: .primary,
                phase: .began,
                location: CGPoint(x: 10, y: 10),
                globalLocation: CGPoint(x: 10, y: 10),
                modifiers: []
            )],
            at: .zero
        ).isActive)
        XCTAssertTrue(manager.bindings[eventID]?.responder === target)
        XCTAssertTrue(host.receivedEvents.last?[eventID]?.binding?.responder === target)
        XCTAssertEqual(root.bindCount, 1)

        root.target = nil
        XCTAssertTrue(manager.sendDownstream(
            [eventID: VUI.MouseEvent(
                timestamp: Time(seconds: 0.01),
                binding: nil,
                button: .primary,
                phase: .active,
                location: CGPoint(x: 200, y: 200),
                globalLocation: CGPoint(x: 200, y: 200),
                modifiers: []
            )],
            at: Time(seconds: 0.01)
        ).isActive)
        XCTAssertTrue(host.receivedEvents.last?[eventID]?.binding?.responder === target)
        XCTAssertEqual(root.bindCount, 1)

        XCTAssertTrue(manager.sendDownstream(
            [eventID: VUI.MouseEvent(
                timestamp: Time(seconds: 0.02),
                binding: nil,
                button: .primary,
                phase: .ended,
                location: CGPoint(x: 200, y: 200),
                globalLocation: CGPoint(x: 200, y: 200),
                modifiers: []
            )],
            at: Time(seconds: 0.02)
        ).isEnded)
        XCTAssertTrue(host.receivedEvents.last?[eventID]?.binding?.responder === target)
        XCTAssertNil(manager.bindings[eventID])
        XCTAssertEqual(root.bindCount, 1)
    }

    // ASSERTIONS buttonPressedDragBoundaryBindingObserved
    func testPrimitiveButtonCallbacksClearPressOutsideAndRestoreOnReentry() {
        var pressingValues: [Bool] = []
        var actionCount = 0
        let callbacks = PrimitiveButtonGestureCallbacks(
            hoverCallback: { _ in actionCount += 1 },
            buttonPressingAction: { phase in
                pressingValues.append(phase == .pressing)
            }
        )
        var state = PrimitiveButtonGestureCallbacks.initialState

        callbacks.dispatch(
            phase: .active(.init(
                location: CGPoint(x: 10, y: 10),
                timestamp: 0,
                locationInBounds: .inBounds
            )),
            state: &state
        )?()
        XCTAssertEqual(state, .pressing)
        XCTAssertEqual(pressingValues, [true])

        callbacks.dispatch(
            phase: .active(.init(
                location: CGPoint(x: 200, y: 200),
                timestamp: 0.01,
                locationInBounds: .outOfBounds
            )),
            state: &state
        )?()
        XCTAssertEqual(state, .outside)
        XCTAssertEqual(pressingValues, [true, false])
        XCTAssertEqual(actionCount, 0)

        callbacks.dispatch(
            phase: .active(.init(
                location: CGPoint(x: 10, y: 10),
                timestamp: 0.02,
                locationInBounds: .inBounds
            )),
            state: &state
        )?()
        XCTAssertEqual(state, .pressing)
        XCTAssertEqual(pressingValues, [true, false, true])

        callbacks.dispatch(
            phase: .ended(.init(
                location: CGPoint(x: 10, y: 10),
                timestamp: 0.03,
                locationInBounds: .inBounds
            )),
            state: &state
        )?()
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(pressingValues, [true, false, true, false])
        XCTAssertEqual(actionCount, 1)
    }

    // ASSERTIONS buttonPressedDragBoundaryBindingObserved
    @MainActor
    func testWindowMouseDragOutsidePublishesUnpressedBeforeRelease() {
        let recorder = ButtonPressRecorder()
        let controller = WindowController(
            content: ButtonGestureRecordingRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ButtonGestureRecordingRoot.self)
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

        let inside = CGPoint(x: 210, y: 120)
        let outside = CGPoint(x: 20, y: 20)
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: inside,
            timestamp: 0
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(recorder.pressingValues, [true])

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .move,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.01
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(recorder.pressingValues, [true, false])
        XCTAssertEqual(recorder.actionCount, 0)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.02
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(recorder.actionCount, 0)
    }

    // ASSERTIONS appKitPressedPointerHoverIsolationObserved
    @MainActor
    func testQueuedMouseDragPreservesPressStreamAndInvokesButtonAction() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)
        let location = CGPoint(x: 210, y: 120)

        let samples: [(MouseEventType, CGPoint, Double)] = [
            (.buttonDown, location, 0),
            (.move, CGPoint(x: location.x + 1, y: location.y), 0.01),
            (.move, CGPoint(x: location.x + 2, y: location.y), 0.02),
            (.buttonUp, CGPoint(x: location.x + 2, y: location.y), 0.03),
        ]
        for (type, point, seconds) in samples {
            controller.enqueueMouseInputEvent(
                VVD.MouseEvent(
                    type: type,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    location: point,
                    timestamp: seconds
                ),
                at: Time(seconds: seconds)
            )
        }

        var redraw = false
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 1)
    }

    // ASSERTIONS forwardedEventDispatcherRegistrationDispatchObserved
    @MainActor
    func testUnboundHoverEventDoesNotCancelActiveButtonPress() throws {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)
        let location = CGPoint(x: 210, y: 120)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        )))

        let manager = try XCTUnwrap(
            controller.gestureGraph?.eventBindingManager
        )
        let hoverID = EventID(type: HoverEvent.self, serial: 91)
        XCTAssertTrue(manager.send(
            [hoverID: HoverEvent(
                timestamp: .zero,
                phase: .began,
                binding: nil,
                globalLocation: location
            )],
            at: .zero
        ).isEmpty)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0.01
        )))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func testWindowSecondaryMouseClickDoesNotInvokeButtonAction() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)

        _ = pointerClick(
            controller,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 1,
            at: CGPoint(x: 210, y: 120)
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 0)
    }

    @MainActor
    func testWindowStylusTipInvokesButtonAction() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)

        let consumed = pointerClick(
            controller,
            device: .stylus,
            deviceID: 17,
            buttonID: 0,
            at: CGPoint(x: 210, y: 120)
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(consumed.down)
        XCTAssertTrue(consumed.up)
        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func testWindowStylusBarrelClickDoesNotInvokeButtonAction() {
        let counter = ButtonActionCounter()
        let controller = makeButtonController(counter: counter)

        _ = pointerClick(
            controller,
            device: .stylus,
            deviceID: 18,
            buttonID: 1,
            at: CGPoint(x: 210, y: 120)
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 0)
    }

    @MainActor
    func testWindowMouseClickStartsANewGestureSession() {
        let counter = ButtonActionCounter()
        let controller = WindowController(
            content: ButtonEventRoutingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ButtonEventRoutingRoot.self)
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

        click(controller, at: CGPoint(x: 210, y: 120))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        click(controller, at: CGPoint(x: 210, y: 120))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(counter.value, 2)
    }

    // ASSERTIONS gestureResponderResetSubgraphReferencesObserved
    @MainActor
    func testGestureMakeGestureRunsForEachClickSession() {
        let actionCounter = ButtonActionCounter()
        let makeCounter = ButtonActionCounter()
        let controller = WindowController(
            content: MakeCountingButtonRoot(
                actionCounter: actionCounter,
                makeCounter: makeCounter
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MakeCountingButtonRoot.self)
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

        XCTAssertEqual(makeCounter.value, 0)
        click(controller, at: CGPoint(x: 210, y: 120))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(actionCounter.value, 1)
        XCTAssertEqual(makeCounter.value, 1)

        click(controller, at: CGPoint(x: 210, y: 120))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(actionCounter.value, 2)
        XCTAssertEqual(makeCounter.value, 2)
    }

    @MainActor
    func testWindowMouseClickSelectsButtonFromNestedResponderTree() {
        let first = ButtonActionCounter()
        let second = ButtonActionCounter()
        let controller = WindowController(
            content: NestedButtonEventRoutingRoot(first: first, second: second),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedButtonEventRoutingRoot.self)
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

        let firstBinding = controller.gestureGraph?.eventBinding(
            at: CGPoint(x: 130, y: 120),
            accepting: MouseEvent.self
        )
        let secondBinding = controller.gestureGraph?.eventBinding(
            at: CGPoint(x: 290, y: 120),
            accepting: MouseEvent.self
        )
        XCTAssertNotNil(firstBinding)
        XCTAssertNotNil(secondBinding)
        XCTAssertFalse(firstBinding?.responder === secondBinding?.responder)

        click(controller, at: CGPoint(x: 130, y: 120))
        click(controller, at: CGPoint(x: 290, y: 120))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 1)
    }

    @MainActor
    func testWindowMouseClickSurvivesPresentationModifierChain() {
        let counter = ButtonActionCounter()
        let controller = WindowController(
            content: PresentedButtonEventRoutingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PresentedButtonEventRoutingRoot.self)
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

        XCTAssertNotNil(controller.gestureGraph?.eventBinding(
            at: CGPoint(x: 210, y: 120),
            accepting: MouseEvent.self
        ))

        click(controller, at: CGPoint(x: 210, y: 120))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func testMixedToggleAndButtonRetainGestureResponders() {
        let controller = WindowController(
            content: MixedControlEventRoutingRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MixedControlEventRoutingRoot.self)
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
        for tick in 1...3 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date,
                contentSize: CGSize(width: 680, height: 650),
                redraw: &redraw
            ) { _, _ in }
        }

        let root = controller.gestureGraph?.responderNode as? MultiViewResponder
        XCTAssertEqual(
            root?.children.compactMap { $0 as? any AnyGestureResponder }.count,
            2
        )
    }

    @MainActor
    func testManyNestedControlsRetainGestureResponders() {
        let controller = WindowController(
            content: ManyControlEventRoutingRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ManyControlEventRoutingRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 680, height: 650),
            redraw: &redraw
        ) { _, _ in }

        let root = controller.gestureGraph?.responderNode as? MultiViewResponder
        XCTAssertEqual(
            root?.children.compactMap { $0 as? any AnyGestureResponder }.count,
            14
        )
    }

    @MainActor
    func testGraphValueWindowContentRetainsGestureResponders() {
        let source = GraphHost.Data()
        var controller: WindowController!
        source.withCurrent {
            let content = source.graph.makeInput(value: ManyControlEventRoutingRoot())
            controller = WindowController(
                content: _GraphValue(_attribute: content),
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(ManyControlEventRoutingRoot.self)
                )
            )
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 680, height: 650),
            redraw: &redraw
        ) { _, _ in }

        let root = controller.gestureGraph?.responderNode as? MultiViewResponder
        XCTAssertEqual(
            root?.children.compactMap { $0 as? any AnyGestureResponder }.count,
            14
        )
    }

    @MainActor
    private func click(_ controller: WindowController, at location: CGPoint) {
        let consumed = pointerClick(
            controller,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            at: location
        )
        XCTAssertTrue(consumed.down)
        XCTAssertTrue(consumed.up)
    }

    @MainActor
    private func makeButtonController(
        counter: ButtonActionCounter
    ) -> WindowController {
        let controller = WindowController(
            content: ButtonEventRoutingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ButtonEventRoutingRoot.self)
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
        return controller
    }

    @MainActor
    private func pointerClick(
        _ controller: WindowController,
        device: MouseEventDevice,
        deviceID: Int,
        buttonID: Int,
        at location: CGPoint
    ) -> (down: Bool, up: Bool) {
        let down = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: device,
            deviceID: deviceID,
            buttonID: buttonID,
            location: location,
            timestamp: 0
        ))
        let up = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: device,
            deviceID: deviceID,
            buttonID: buttonID,
            location: location,
            timestamp: 0
        ))
        return (down, up)
    }
}

private final class ButtonActionCounter: @unchecked Sendable {
    var value = 0
}

private final class ButtonPressRecorder: @unchecked Sendable {
    var pressingValues: [Bool] = []
    var actionCount = 0
}

private final class ButtonBindingRoot: ResponderNode {
    var target: ResponderNode?
    var bindCount = 0

    init(target: ResponderNode?) {
        self.target = target
    }

    override func bindEvent(_ event: any EventType) -> ResponderNode? {
        bindCount += 1
        return target
    }
}

private final class ButtonBindingHost: EventGraphHost {
    let eventBindingManager: EventBindingManager
    var responderNode: ResponderNode?
    var focusedResponder: ResponderNode?
    var nextGestureUpdateTime: Time { .infinity }
    var receivedEvents: [[EventID: any EventType]] = []

    init(manager: EventBindingManager, responderNode: ResponderNode?) {
        self.eventBindingManager = manager
        self.responderNode = responderNode
    }

    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        receivedEvents.append(events)
        return events.values.contains { $0.phase.isTerminal }
            ? .ended(())
            : .active(())
    }

    func resetEvents() {}
    func gestureCategory() -> GestureCategory? { nil }
}

private struct ButtonEventRoutingRoot: View {
    let counter: ButtonActionCounter

    var body: some View {
        Button("Action") {
            counter.value += 1
        }
        .frame(width: 420, height: 240)
    }
}

private struct ButtonGestureRecordingRoot: View {
    let recorder: ButtonPressRecorder

    var body: some View {
        Text("Action")
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4).fill(Color.white)
            }
            .foregroundStyle(Color.black)
            ._onButtonGesture(
                pressing: { recorder.pressingValues.append($0) },
                perform: { recorder.actionCount += 1 }
            )
            .frame(width: 420, height: 240)
    }
}

private struct MakeCountingGesture<Base: Gesture>: Gesture {
    let base: Base
    let counter: ButtonActionCounter

    typealias Value = Base.Value
    typealias Body = Never

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        gesture[\.counter]._attribute.value.value += 1
        return Base._makeGesture(gesture: gesture[\.base], inputs: inputs)
    }
}

private struct MakeCountingButtonRoot: View {
    let actionCounter: ButtonActionCounter
    let makeCounter: ButtonActionCounter

    var body: some View {
        Button("Action") {
            actionCounter.value += 1
        }
        .simultaneousGesture(
            MakeCountingGesture(base: TapGesture(), counter: makeCounter)
        )
        .frame(width: 420, height: 240)
    }
}

private struct NestedButtonEventRoutingRoot: View {
    let first: ButtonActionCounter
    let second: ButtonActionCounter

    var body: some View {
        HStack(spacing: 10) {
            Button("First") {
                first.value += 1
            }
            .frame(width: 145, height: 40)

            Button("Second") {
                second.value += 1
            }
            .frame(width: 145, height: 40)
        }
        .frame(width: 420, height: 240)
    }
}

private struct PresentedButtonEventRoutingRoot: View {
    let counter: ButtonActionCounter
    @State private var selectedItem: PresentedButtonEventRoutingItem?
    @State private var sheetPresented = false
    @State private var alertPresented = false

    var body: some View {
        VStack {
            actionButton()
        }
        .frame(width: 420, height: 240)
        .sheet(item: $selectedItem) { item in
            Text(item.title)
        }
        .environment(\.modalSessionUsingPlatformWindow, true)
        .sheet(isPresented: $sheetPresented) {
            Text("Sheet")
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
        .alert("Alert", isPresented: $alertPresented) {
            Button("Dismiss") {}
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
    }

    private func actionButton() -> some View {
        Button("Action") {
            counter.value += 1
        }
        .frame(width: 145, height: 40)
    }
}

private struct MixedControlEventRoutingRoot: View {
    @State private var isOn = false

    var body: some View {
        VStack {
            Toggle("Enabled", isOn: $isOn)
            Button("Action") {}
        }
        .frame(width: 420, height: 240)
    }
}

private struct ManyControlEventRoutingRoot: View {
    @State private var isOn = false
    @State private var selectedItem: PresentedButtonEventRoutingItem?
    @State private var sheetPresented = false
    @State private var alertPresented = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Controls")
            VStack(spacing: 10) {
                Toggle("Enabled", isOn: $isOn)
                HStack(spacing: 10) {
                    actionButton("1")
                    actionButton("2")
                    actionButton("3")
                    actionButton("4")
                }
                HStack(spacing: 10) {
                    actionButton("5")
                    actionButton("6")
                    actionButton("7")
                    actionButton("8")
                }
                HStack(spacing: 10) {
                    actionButton("9")
                    actionButton("10")
                    actionButton("11")
                    actionButton("12")
                }
                actionButton("13")
            }
        }
        .padding(24)
        .frame(width: 680, height: 650)
        .sheet(item: $selectedItem) { item in
            Text(item.title)
        }
        .environment(\.modalSessionUsingPlatformWindow, true)
        .sheet(isPresented: $sheetPresented) {
            Text("Sheet")
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
        .alert("Alert", isPresented: $alertPresented) {
            Button("Dismiss") {}
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
    }

    private func actionButton(_ title: String) -> some View {
        Button(title) {}
            .frame(width: 145)
    }
}

private struct PresentedButtonEventRoutingItem: Identifiable {
    let id: Int
    let title: String
}
