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
    private func makeController<Content: View>(content: Content) -> WindowController {
        let controller = WindowController(
            content: content,
            scene: WindowKey(namespace: .app, sceneID: SceneID(Content.self))
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
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
