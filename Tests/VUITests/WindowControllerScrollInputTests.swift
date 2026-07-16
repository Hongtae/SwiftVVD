import XCTest
@testable import VVD
@testable import VUI

final class WindowControllerScrollInputTests: XCTestCase {
    @MainActor
    func testPrimaryPointerDragProducesTimedPanUpdates() {
        let probe = PointerPanProbe()
        let controller = WindowController(
            content: PointerPanRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerPanRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: CGPoint(x: 40, y: 40)),
            at: Time(seconds: 1.0)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 50, y: 40)),
            at: Time(seconds: 1.1)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 70, y: 40)),
            at: Time(seconds: 1.2)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 80, y: 40)),
            at: Time(seconds: 1.25)
        ))

        XCTAssertEqual(probe.changed.last?.translation, CGSize(width: 30, height: 0))
        XCTAssertEqual(
            probe.changed.last?.velocity.valuePerSecond.width ?? .nan,
            200,
            accuracy: 0.001
        )
        XCTAssertEqual(probe.ended?.translation, CGSize(width: 40, height: 0))
        XCTAssertEqual(
            probe.ended?.velocity.valuePerSecond.width ?? .nan,
            200,
            accuracy: 0.001
        )
    }

    @MainActor
    func testSecondaryPointerButtonDoesNotProducePanUpdates() {
        let probe = PointerPanProbe()
        let controller = WindowController(
            content: PointerPanRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerPanRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )

        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, buttonID: 1, location: CGPoint(x: 40, y: 40)),
            at: Time(seconds: 1.0)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, buttonID: 1, location: CGPoint(x: 70, y: 40)),
            at: Time(seconds: 1.1)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, buttonID: 1, location: CGPoint(x: 70, y: 40)),
            at: Time(seconds: 1.2)
        )

        XCTAssertTrue(probe.changed.isEmpty)
        XCTAssertNil(probe.ended)
    }

    @MainActor
    func testPublicScrollViewAcceptsSynthesizedPointerPan() {
        let controller = WindowController(
            content: PointerScrollViewRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerScrollViewRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        guard let responder = controller.gestureGraph?.rootResponder?.responders.first
                as? GestureResponder<SystemScrollViewGesture> else {
            XCTFail("Expected the public ScrollView system gesture responder")
            return
        }
        let host = controller.viewGraph.data.withCurrent {
            responder.modifierAttr.value.scrollView
        }

        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: CGPoint(x: 100, y: 60)),
            at: Time(seconds: 0)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 100, y: 30)),
            at: Time(seconds: 0.05)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 100, y: 30)),
            at: Time(seconds: 0.1)
        ))
        XCTAssertTrue(host.isDecelerating)

        var sampledOffsets: [CGFloat] = []
        for tick in 1...3 {
            redraw = false
            controller.updateView(
                tick: UInt64(tick),
                delta: 0.1 + Double(tick) * 0.1 -
                    controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(0.1 + Double(tick) * 0.1),
                contentSize: CGSize(width: 200, height: 120),
                redraw: &redraw,
                withGC
            )
            XCTAssertTrue(redraw)
            sampledOffsets.append(host.pendingContext?.contentOffset.y ?? .nan)
        }
        XCTAssertGreaterThan(sampledOffsets[0], 30)
        XCTAssertGreaterThan(sampledOffsets[1], sampledOffsets[0])
    }

    @MainActor
    func testPublicScrollViewAcceptsWheelAndPublishesOffset() {
        let controller = WindowController(
            content: PointerScrollViewRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerScrollViewRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        guard let responder = controller.gestureGraph?.rootResponder?.responders.first
                as? GestureResponder<SystemScrollViewGesture> else {
            XCTFail("Expected the public ScrollView system gesture responder")
            return
        }
        let host = controller.viewGraph.data.withCurrent {
            responder.modifierAttr.value.scrollView
        }

        XCTAssertTrue(controller.handleMouseWheel(
            at: CGPoint(x: 100, y: 60),
            delta: CGPoint(x: 0, y: 40),
            time: Time(seconds: 0.05)
        ))
        controller.updateView(
            tick: 1,
            delta: 0.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(0.1),
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )

        XCTAssertEqual(host.pendingContext?.contentOffset.y, 40)
        XCTAssertFalse(host.isDecelerating)
    }

    @MainActor
    func testPublicHorizontalScrollViewAcceptsHorizontalWheel() {
        let controller = WindowController(
            content: PointerHorizontalScrollViewRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerHorizontalScrollViewRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        guard let responder = controller.gestureGraph?.rootResponder?.responders.first
                as? GestureResponder<SystemScrollViewGesture> else {
            XCTFail("Expected the public ScrollView system gesture responder")
            return
        }
        let host = controller.viewGraph.data.withCurrent {
            responder.modifierAttr.value.scrollView
        }

        XCTAssertTrue(controller.handleMouseWheel(
            at: CGPoint(x: 100, y: 60),
            delta: CGPoint(x: 35, y: 0),
            time: Time(seconds: 0.05)
        ))

        XCTAssertEqual(host.pendingContext?.contentOffset.x, 35)
        XCTAssertEqual(host.pendingContext?.contentOffset.y, 0)
        XCTAssertFalse(host.isDecelerating)
    }

    @MainActor
    func testContinuousWheelUsesDirectPhaseAndIgnoresNativeMomentumSamples() {
        let controller = WindowController(
            content: PointerScrollViewRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerScrollViewRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        guard let responder = controller.gestureGraph?.rootResponder?.responders.first
                as? GestureResponder<SystemScrollViewGesture> else {
            XCTFail("Expected the public ScrollView system gesture responder")
            return
        }
        let host = controller.viewGraph.data.withCurrent {
            responder.modifierAttr.value.scrollView
        }

        controller.onMouseEvent(
            event: wheelEvent(delta: CGPoint(x: 0, y: 10), phase: .began, timestamp: 1),
            at: Time(seconds: 1)
        )
        controller.onMouseEvent(
            event: wheelEvent(delta: CGPoint(x: 0, y: 20), phase: .changed, timestamp: 1.05),
            at: Time(seconds: 1.05)
        )
        controller.onMouseEvent(
            event: wheelEvent(delta: .zero, phase: .ended, timestamp: 1.1),
            at: Time(seconds: 1.1)
        )

        XCTAssertEqual(host.pendingContext?.contentOffset.y, 30)
        XCTAssertTrue(host.isDecelerating)
        let offsetBeforeNativeMomentum = host.pendingContext?.contentOffset

        controller.onMouseEvent(
            event: wheelEvent(
                delta: CGPoint(x: 0, y: 80),
                nativeMomentumPhase: .changed,
                timestamp: 1.15
            ),
            at: Time(seconds: 1.15)
        )

        XCTAssertEqual(host.pendingContext?.contentOffset, offsetBeforeNativeMomentum)
    }

    @MainActor
    func testPlatformPanForwardsChangedAndEndedWithAccumulatedTranslation() {
        let probe = PointerPanProbe()
        let controller = WindowController(
            content: PointerPanRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerPanRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )

        XCTAssertTrue(controller.handleGestureEvent(
            event: panEvent(.began, delta: .zero),
            at: Time(seconds: 1.0)
        ))
        XCTAssertTrue(controller.handleGestureEvent(
            event: panEvent(.changed, delta: CGPoint(x: 0, y: -12)),
            at: Time(seconds: 1.1)
        ))
        XCTAssertTrue(controller.handleGestureEvent(
            event: panEvent(.changed, delta: CGPoint(x: 0, y: -8)),
            at: Time(seconds: 1.2)
        ))
        XCTAssertTrue(controller.handleGestureEvent(
            event: panEvent(.ended, delta: .zero),
            at: Time(seconds: 1.3)
        ))

        XCTAssertEqual(probe.changed.last?.translation, CGSize(width: 0, height: -20))
        XCTAssertEqual(probe.ended?.translation, CGSize(width: 0, height: -20))
    }

    @MainActor
    func testScrollPanSuppressesButtonActivation() {
        let probe = PointerScrollButtonProbe()
        let controller = WindowController(
            content: PointerScrollButtonRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerScrollButtonRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )

        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: CGPoint(x: 100, y: 60)),
            at: Time(seconds: 1.0)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.move, location: CGPoint(x: 100, y: 30)),
            at: Time(seconds: 1.1)
        )
        _ = controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 100, y: 30)),
            at: Time(seconds: 1.2)
        )

        XCTAssertEqual(probe.actions, 0)
    }

    @MainActor
    func testScrollContentButtonStillActivatesWithoutPan() {
        let probe = PointerScrollButtonProbe()
        let controller = WindowController(
            content: PointerScrollButtonRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PointerScrollButtonRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw,
            withGC
        )
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonDown, location: CGPoint(x: 100, y: 60)),
            at: Time(seconds: 1.0)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: pointerEvent(.buttonUp, location: CGPoint(x: 100, y: 60)),
            at: Time(seconds: 1.1)
        ))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(probe.actions, 1)
    }

    private func pointerEvent(
        _ type: MouseEventType,
        buttonID: Int = 0,
        location: CGPoint
    ) -> MouseEvent {
        MouseEvent(
            type: type,
            device: .genericMouse,
            deviceID: 7,
            buttonID: buttonID,
            location: location,
            timestamp: 0
        )
    }

    private func panEvent(
        _ phase: GestureEventPhase,
        delta: CGPoint
    ) -> GestureEvent {
        GestureEvent(
            type: .pan,
            phase: phase,
            location: CGPoint(x: 100, y: 60),
            delta: delta
        )
    }

    private func wheelEvent(
        delta: CGPoint,
        phase: ScrollEventPhase? = nil,
        nativeMomentumPhase: ScrollEventPhase? = nil,
        timestamp: TimeInterval
    ) -> MouseEvent {
        MouseEvent(
            type: .wheel,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 2,
            location: CGPoint(x: 100, y: 60),
            delta: delta,
            timestamp: timestamp,
            scrollData: ScrollEventData(
                phase: phase,
                nativeMomentumPhase: nativeMomentumPhase,
                source: .continuous,
                isPrecise: true
            )
        )
    }
}

private final class PointerPanProbe {
    var changed: [PanGesture.Value] = []
    var ended: PanGesture.Value?
}

private struct PointerPanRoot: View {
    let probe: PointerPanProbe

    var body: some View {
        Color.red
            .frame(width: 200, height: 120)
            .gesture(
                PanGesture(minimumDistance: 0, allowedDirections: .all)
                    .onChanged { probe.changed.append($0) }
                    .onEnded { probe.ended = $0 }
            )
    }
}

private struct PointerScrollViewRoot: View {
    var body: some View {
        ScrollView(.vertical) {
            Color.red.frame(width: 200, height: 400)
        }
    }
}

private struct PointerHorizontalScrollViewRoot: View {
    var body: some View {
        ScrollView(.horizontal) {
            Color.red.frame(width: 400, height: 120)
        }
    }
}

private final class PointerScrollButtonProbe {
    var actions = 0
}

private struct PointerScrollButtonRoot: View {
    let probe: PointerScrollButtonProbe

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.red.frame(width: 200, height: 140)
                Button("Tap") { probe.actions += 1 }
                    .frame(width: 200, height: 120)
                Color.red.frame(width: 200, height: 140)
            }
        }
    }
}
