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
}

private final class TouchEventRecorder: @unchecked Sendable {
    var events: [TouchEvent] = []
}

private struct TouchEventRoutingRoot: View {
    let recorder: TouchEventRecorder

    var body: some View {
        Color.green
            .frame(width: 420, height: 240)
            .gesture(
                EventListener<TouchEvent>()
                    .onChanged { recorder.events.append($0) }
            )
    }
}
