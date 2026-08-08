import Foundation
import XCTest
@testable import VUI

private struct DefaultSpacingProbeLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
    }
}

private final class DefaultSpacingProbeEngine: LayoutEngine {
    let spacingValue: Spacing
    var spacingCallCount = 0

    init(spacing: Spacing) {
        self.spacingValue = spacing
    }

    func spacing() -> Spacing {
        spacingCallCount += 1
        return spacingValue
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        .zero
    }
}

final class LayoutDefaultBehaviorTests: XCTestCase {
    func testDefaultSpacingReturnsZeroForEmptySubviews() {
        withGraph { graph in
            let layout = DefaultSpacingProbeLayout()
            let subviews = makeSubviews(
                graph: graph,
                engines: [],
                layoutDirection: .rightToLeft
            )
            var cache: Void = ()

            let result = layout.spacing(
                subviews: subviews,
                cache: &cache
            )

            XCTAssertEqual(result.spacing, .zero)
            XCTAssertNil(result.layoutDirection)
        }
    }

    func testDefaultSpacingIncorporatesEveryChildAndPreservesDirection() {
        withGraph { graph in
            let first = DefaultSpacingProbeEngine(
                spacing: spacing(left: 3, right: 9)
            )
            let second = DefaultSpacingProbeEngine(
                spacing: spacing(left: 7, right: 2)
            )
            let layout = DefaultSpacingProbeLayout()
            let subviews = makeSubviews(
                graph: graph,
                engines: [first, second],
                layoutDirection: .rightToLeft
            )
            var cache: Void = ()

            let result = layout.spacing(
                subviews: subviews,
                cache: &cache
            )

            XCTAssertEqual(spacingValue(result, edge: .left), 7)
            XCTAssertEqual(spacingValue(result, edge: .right), 9)
            XCTAssertEqual(result.layoutDirection, .rightToLeft)
            XCTAssertEqual(first.spacingCallCount, 1)
            XCTAssertEqual(second.spacingCallCount, 1)
        }
    }

    private func makeSubviews(
        graph: _AGGraph,
        engines: [DefaultSpacingProbeEngine],
        layoutDirection: LayoutDirection
    ) -> LayoutSubviews {
        let context = AnyRuleContext(
            attribute: graph.makeInput(value: ()).identifier
        )
        return LayoutSubviews(
            context: context,
            attributes: engines.map { engine in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(engine)
                    )
                )
            },
            layoutDirection: layoutDirection
        )
    }

    private func spacing(left: CGFloat, right: CGFloat) -> Spacing {
        Spacing(minima: [
            Spacing.Key(category: .default, edge: .left): .distance(left),
            Spacing.Key(category: .default, edge: .right): .distance(right),
        ])
    }

    private func spacingValue(
        _ spacing: ViewSpacing,
        edge: AbsoluteEdge
    ) -> CGFloat? {
        spacing.spacing.minima[
            Spacing.Key(category: .default, edge: edge)
        ]?.value
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            body(graph)
        }
    }
}
