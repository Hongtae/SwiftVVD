import XCTest
@testable import VUI
@testable import VVD

final class ButtonEventRoutingTests: XCTestCase {
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
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        )))
    }
}

private final class ButtonActionCounter: @unchecked Sendable {
    var value = 0
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
