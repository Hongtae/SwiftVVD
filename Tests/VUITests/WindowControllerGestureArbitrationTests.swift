import XCTest
@testable import VVD
@testable import VUI

final class WindowControllerGestureArbitrationTests: XCTestCase {
    @MainActor
    func testHighPriorityGestureSuppressesDefaultGesture() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(content: PriorityGestureRoot(probe: probe))
        click(controller, at: CGPoint(x: 100, y: 60), time: 1)

        XCTAssertEqual(probe.highPriorityActions, 1)
        XCTAssertEqual(probe.defaultActions, 0)
    }

    @MainActor
    func testSimultaneousGestureRunsBesideDefaultGesture() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(content: SimultaneousGestureRoot(probe: probe))
        click(controller, at: CGPoint(x: 100, y: 60), time: 1)

        XCTAssertEqual(probe.simultaneousActions, 1)
        XCTAssertEqual(probe.defaultActions, 1)
    }

    @MainActor
    func testSingleTapWaitsForDoubleTapFailure() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(content: TapCountGestureRoot(probe: probe))

        click(controller, at: CGPoint(x: 100, y: 60), time: 1)
        XCTAssertEqual(probe.singleTapActions, 0)
        XCTAssertEqual(probe.doubleTapActions, 0)
        XCTAssertEqual(
            controller.gestureGraph?.nextGestureUpdateTime.seconds ?? .nan,
            1.51,
            accuracy: 0.001
        )

        click(controller, at: CGPoint(x: 100, y: 60), time: 1.1)
        XCTAssertEqual(probe.singleTapActions, 0)
        XCTAssertEqual(probe.doubleTapActions, 1)
    }

    @MainActor
    func testSingleTapFiresAfterDoubleTapDeadline() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(content: TapCountGestureRoot(probe: probe))

        click(controller, at: CGPoint(x: 100, y: 60), time: 1)
        XCTAssertEqual(probe.singleTapActions, 0)
        XCTAssertEqual(probe.doubleTapActions, 0)

        XCTAssertEqual(
            controller.gestureGraph?.updateTimedGestures(at: Time(seconds: 1.6)),
            true
        )
        XCTAssertEqual(probe.singleTapActions, 1)
        XCTAssertEqual(probe.doubleTapActions, 0)
    }

    @MainActor
    func testButtonAndAncestorDragTrackTheSameScrollPointerStream() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(
            content: ScrollButtonArbitrationRoot(probe: probe),
            contentSize: CGSize(width: 260, height: 220)
        )
        let location = CGPoint(x: 130, y: 45)

        click(controller, at: location, time: 1)
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: location),
            at: Time(seconds: 2)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 130, y: 75)),
            at: Time(seconds: 2.1)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 130, y: 105)),
            at: Time(seconds: 2.2)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 130, y: 105)),
            at: Time(seconds: 2.3)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(probe.buttonPressing, [true, false, true, false])
        XCTAssertEqual(probe.buttonActions, 1)
        XCTAssertGreaterThan(probe.ancestorDragChanged, 0)
        XCTAssertEqual(probe.ancestorDragEnded, 1)
    }

    @MainActor
    func testNestedDefaultDescendantDefersAncestorUntilRecognition() {
        let probe = GestureArbitrationProbe()
        let controller = makeController(content: NestedDefaultDragRoot(probe: probe))

        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: CGPoint(x: 100, y: 60)),
            at: Time(seconds: 1)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 105, y: 60)),
            at: Time(seconds: 1.1)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 110, y: 60)),
            at: Time(seconds: 1.15)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(probe.nestedAncestorDragChanged, 0)
        XCTAssertEqual(probe.nestedDescendantDragChanged, 0)

        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 145, y: 60)),
            at: Time(seconds: 1.2)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 145, y: 60)),
            at: Time(seconds: 1.3)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(probe.nestedAncestorDragChanged, 0)
        XCTAssertEqual(probe.nestedAncestorDragEnded, 0)
        XCTAssertGreaterThan(probe.nestedDescendantDragChanged, 0)
        XCTAssertEqual(probe.nestedDescendantDragEnded, 1)
    }

    @MainActor
    private func makeController<Content: View>(
        content: Content,
        contentSize: CGSize = CGSize(width: 200, height: 120)
    ) -> WindowController {
        let controller = WindowController(
            content: content,
            scene: WindowKey(namespace: .app, sceneID: SceneID(Content.self))
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: contentSize,
            redraw: &redraw,
            { _, _ in }
        )
        return controller
    }

    @MainActor
    private func click(
        _ controller: WindowController,
        at location: CGPoint,
        time: TimeInterval
    ) {
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: location),
            at: Time(seconds: time)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: location),
            at: Time(seconds: time + 0.01)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private func pointerEvent(
        _ type: MouseEventType,
        location: CGPoint
    ) -> MouseEvent {
        MouseEvent(
            type: type,
            device: .genericMouse,
            deviceID: 8,
            buttonID: 0,
            location: location,
            timestamp: 0
        )
    }
}

private final class GestureArbitrationProbe {
    var defaultActions = 0
    var highPriorityActions = 0
    var simultaneousActions = 0
    var singleTapActions = 0
    var doubleTapActions = 0
    var buttonPressing: [Bool] = []
    var buttonActions = 0
    var ancestorDragChanged = 0
    var ancestorDragEnded = 0
    var nestedAncestorDragChanged = 0
    var nestedAncestorDragEnded = 0
    var nestedDescendantDragChanged = 0
    var nestedDescendantDragEnded = 0

    func recordButtonPressing(_ pressing: Bool) {
        guard buttonPressing.last != pressing else { return }
        buttonPressing.append(pressing)
    }
}

private struct NestedDefaultDragRoot: View {
    let probe: GestureArbitrationProbe

    var body: some View {
        ZStack {
            Color.blue
                .frame(width: 160, height: 80)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { _ in probe.nestedDescendantDragChanged += 1 }
                        .onEnded { _ in probe.nestedDescendantDragEnded += 1 }
                )
        }
        .frame(width: 200, height: 120)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in probe.nestedAncestorDragChanged += 1 }
                .onEnded { _ in probe.nestedAncestorDragEnded += 1 }
        )
    }
}

private struct ScrollButtonArbitrationRoot: View {
    let probe: GestureArbitrationProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Color.red
                    .frame(width: 180, height: 44)
                    ._onButtonGesture(
                        pressing: { probe.recordButtonPressing($0) },
                        perform: { probe.buttonActions += 1 }
                    )

                ForEach(0..<3) { index in
                    Text("Row \(index)")
                        .frame(width: 180, height: 28)
                }
            }
            .padding(20)
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in probe.ancestorDragChanged += 1 }
                .onEnded { _ in probe.ancestorDragEnded += 1 }
        )
        .frame(width: 260, height: 220)
    }
}

private struct PriorityGestureRoot: View {
    let probe: GestureArbitrationProbe

    var body: some View {
        Color.red
            .frame(width: 200, height: 120)
            .gesture(TapGesture().onEnded { probe.defaultActions += 1 })
            .highPriorityGesture(TapGesture().onEnded { probe.highPriorityActions += 1 })
    }
}

private struct SimultaneousGestureRoot: View {
    let probe: GestureArbitrationProbe

    var body: some View {
        Color.red
            .frame(width: 200, height: 120)
            .gesture(TapGesture().onEnded { probe.defaultActions += 1 })
            .simultaneousGesture(TapGesture().onEnded { probe.simultaneousActions += 1 })
    }
}

private struct TapCountGestureRoot: View {
    let probe: GestureArbitrationProbe

    var body: some View {
        Color.red
            .frame(width: 200, height: 120)
            .onTapGesture(count: 1) { probe.singleTapActions += 1 }
            .onTapGesture(count: 2) { probe.doubleTapActions += 1 }
    }
}
