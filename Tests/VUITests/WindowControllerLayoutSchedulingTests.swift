import XCTest
@testable import VUI

final class WindowControllerLayoutSchedulingTests: XCTestCase {
    @MainActor
    func testIdleUpdateDoesNotRepeatRootLayoutPlacement() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static layout scheduling test should not request graphics resources.")
        }

        controller.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        XCTAssertGreaterThan(initialPlacements, 0)

        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(counter.placements, initialPlacements)

        controller.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(2.0 / 60.0),
            contentSize: CGSize(width: 140, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertGreaterThan(counter.placements, initialPlacements)
    }

    @MainActor
    func testScheduledAnimationUpdateDoesNotRepeatRootLayoutPlacement() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingAnimationRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingAnimationRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        let initialBounds = try displayBounds(in: controller)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        redraw = false
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let targetPlacements = counter.placements
        XCTAssertGreaterThan(targetPlacements, initialPlacements)

        redraw = false
        controller.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(0.25),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        let sampledBounds = try displayBounds(in: controller)
        XCTAssertEqual(counter.placements, targetPlacements)
        XCTAssertTrue(redraw)
        XCTAssertNotEqual(sampledBounds, initialBounds)
    }

    @MainActor
    private func displayBounds(in controller: WindowController) throws -> CGRect {
        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.rootDisplayList?.value.interpolationBounds)
        }
    }
}

private final class LayoutSchedulingCounter {
    var placements = 0
}

private struct LayoutSchedulingRoot: View {
    let counter: LayoutSchedulingCounter

    var body: some View {
        LayoutSchedulingProbeLayout(counter: counter) {
            Color.clear
                .frame(width: 10, height: 10)
        }
    }
}

private struct LayoutSchedulingProbeLayout: Layout {
    let counter: LayoutSchedulingCounter

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: 10, height: 10)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        counter.placements += 1
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: 10, height: 10)
            )
        }
    }
}

private final class LayoutSchedulingAnimationProbe {
    var toggle: (() -> Void)?
}

private struct LayoutSchedulingAnimationRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe

    var body: some View {
        LayoutSchedulingPassThroughLayout(counter: counter) {
            LayoutSchedulingAnimatedFrame(probe: probe)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingAnimatedFrame: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return RoundedRectangle(cornerRadius: expanded ? 28 : 10)
            .fill(expanded ? Color.purple : Color.blue)
            .frame(
                width: expanded ? 180 : 72,
                height: expanded ? 96 : 72
            )
            .offset(
                x: expanded ? 42 : -42,
                y: expanded ? 8 : -8
            )
    }
}

private struct LayoutSchedulingPassThroughLayout: Layout {
    let counter: LayoutSchedulingCounter

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 420, height: 240))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        counter.placements += 1
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}
