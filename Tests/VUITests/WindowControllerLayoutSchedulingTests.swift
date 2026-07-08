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
