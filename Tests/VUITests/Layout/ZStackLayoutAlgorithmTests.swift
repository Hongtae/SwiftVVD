import Foundation
import XCTest
@testable import VUI

private enum ZStackHorizontalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.width * 0.5
    }
}

private enum ZStackVerticalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height * 0.5
    }
}

private final class ZStackProbeLayoutEngine: LayoutEngine {
    let size: CGSize
    let priorityValue: Double
    let horizontalKey: AlignmentKey
    let horizontalGuide: CGFloat
    let verticalKey: AlignmentKey
    let verticalGuide: CGFloat
    let spacingValue: Spacing

    var proposals: [_ProposedSize] = []
    var spacingCallCount = 0

    init(
        size: CGSize,
        priority: Double,
        horizontalKey: AlignmentKey,
        horizontalGuide: CGFloat,
        verticalKey: AlignmentKey,
        verticalGuide: CGFloat,
        spacing: Spacing = Spacing()
    ) {
        self.size = size
        self.priorityValue = priority
        self.horizontalKey = horizontalKey
        self.horizontalGuide = horizontalGuide
        self.verticalKey = verticalKey
        self.verticalGuide = verticalGuide
        self.spacingValue = spacing
    }

    func layoutPriority() -> Double {
        priorityValue
    }

    func spacing() -> Spacing {
        spacingCallCount += 1
        return spacingValue
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        proposals.append(proposal)
        return size
    }

    func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        if key == horizontalKey {
            return horizontalGuide
        }
        if key == verticalKey {
            return verticalGuide
        }
        return nil
    }
}

private func isZStackUnaryViewRoot<T>(_ value: T) -> Bool {
    value is any _VariadicView_UnaryViewRoot
}

final class ZStackLayoutAlgorithmTests: XCTestCase {
    func testPublicZStackLayoutIsADistinctDerivedShell() {
        let publicLayout = ZStackLayout(alignment: .bottomTrailing)
        let internalLayout = _ZStackLayout(alignment: .bottomTrailing)

        XCTAssertNotEqual(
            ObjectIdentifier(ZStackLayout.self),
            ObjectIdentifier(_ZStackLayout.self)
        )
        XCTAssertEqual(MemoryLayout<ZStackLayout>.size, MemoryLayout<_ZStackLayout>.size)
        XCTAssertEqual(MemoryLayout<ZStackLayout>.stride, MemoryLayout<_ZStackLayout>.stride)
        XCTAssertEqual(publicLayout.base.alignment, internalLayout.alignment)
        XCTAssertFalse(isZStackUnaryViewRoot(publicLayout))
        XCTAssertTrue(isZStackUnaryViewRoot(internalLayout))
    }

    func testLayoutPropertiesUseObservedIdentityUnaryFlag() {
        let properties = ZStackLayout.layoutProperties

        XCTAssertNil(properties.stackOrientation)
        XCTAssertFalse(properties.isDefaultEmptyLayout)
        XCTAssertTrue(properties.isIdentityUnaryLayout)
    }

    func testSpacingUsesOnlyHighestPriorityAndPreservesDirection() {
        withGraph { graph in
            let alignment = probeAlignment()
            let low = makeEngine(
                size: CGSize(width: 100, height: 80),
                priority: 0,
                alignment: alignment,
                horizontalGuide: 90,
                verticalGuide: 70,
                spacing: spacing(left: 99, right: 99)
            )
            let highA = makeEngine(
                size: CGSize(width: 20, height: 10),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 3,
                verticalGuide: 4,
                spacing: spacing(left: 3, right: 5)
            )
            let highB = makeEngine(
                size: CGSize(width: 30, height: 40),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 12,
                verticalGuide: 8,
                spacing: spacing(left: 7, right: 2)
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [low, highA, highB],
                layoutDirection: .rightToLeft
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()

            let result = layout.spacing(
                subviews: subviews,
                cache: &cache
            )

            XCTAssertEqual(spacingValue(result, edge: .left), 7)
            XCTAssertEqual(spacingValue(result, edge: .right), 5)
            XCTAssertEqual(result.layoutDirection, .rightToLeft)
            XCTAssertEqual(low.spacingCallCount, 0)
            XCTAssertEqual(highA.spacingCallCount, 1)
            XCTAssertEqual(highB.spacingCallCount, 1)
        }
    }

    func testSizeUsesHighestPriorityGuideExtentsAndOriginalProposal() {
        withGraph { graph in
            let alignment = probeAlignment()
            let low = makeEngine(
                size: CGSize(width: 100, height: 80),
                priority: 0,
                alignment: alignment,
                horizontalGuide: 90,
                verticalGuide: 70
            )
            let highA = makeEngine(
                size: CGSize(width: 20, height: 10),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 3,
                verticalGuide: 4
            )
            let highB = makeEngine(
                size: CGSize(width: 30, height: 40),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 12,
                verticalGuide: 8
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [low, highA, highB],
                layoutDirection: .leftToRight
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()
            let proposal = ProposedViewSize(width: nil, height: 60)

            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                ),
                CGSize(width: 30, height: 40)
            )
            XCTAssertTrue(low.proposals.isEmpty)
            XCTAssertEqual(highA.proposals, [_ProposedSize(proposal)])
            XCTAssertEqual(highB.proposals, [_ProposedSize(proposal)])
        }
    }

    func testNegativePrioritiesUseTheirTrueMaximum() {
        withGraph { graph in
            let alignment = probeAlignment()
            let higher = makeEngine(
                size: CGSize(width: 11, height: 13),
                priority: -1,
                alignment: alignment,
                horizontalGuide: 2,
                verticalGuide: 3
            )
            let lower = makeEngine(
                size: CGSize(width: 17, height: 19),
                priority: -2,
                alignment: alignment,
                horizontalGuide: 5,
                verticalGuide: 7
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [higher, lower],
                layoutDirection: .leftToRight
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()

            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: .unspecified,
                    subviews: subviews,
                    cache: &cache
                ),
                CGSize(width: 11, height: 13)
            )
            XCTAssertEqual(higher.proposals, [.unspecified])
            XCTAssertTrue(lower.proposals.isEmpty)
        }
    }

    func testNaNPriorityWithoutAnExactMatchReturnsZeroSpacing() {
        withGraph { graph in
            let alignment = probeAlignment()
            let engine = makeEngine(
                size: CGSize(width: 11, height: 13),
                priority: .nan,
                alignment: alignment,
                horizontalGuide: 2,
                verticalGuide: 3,
                spacing: spacing(left: 7, right: 9)
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [engine],
                layoutDirection: .rightToLeft
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()

            let result = layout.spacing(
                subviews: subviews,
                cache: &cache
            )

            XCTAssertEqual(result.spacing, .zero)
            XCTAssertNil(result.layoutDirection)
            XCTAssertEqual(engine.spacingCallCount, 0)
        }
    }

    func testPositiveInfiniteSizeBypassesInfiniteGuideSubtraction() {
        withGraph { graph in
            let alignment = probeAlignment()
            let engine = makeEngine(
                size: CGSize(width: CGFloat.infinity, height: 10),
                priority: 0,
                alignment: alignment,
                horizontalGuide: CGFloat.infinity,
                verticalGuide: 5
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [engine],
                layoutDirection: .leftToRight
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()

            let size = layout.sizeThatFits(
                proposal: .unspecified,
                subviews: subviews,
                cache: &cache
            )
            XCTAssertEqual(size.width, CGFloat.infinity)
            XCTAssertEqual(size.height, 10)
            XCTAssertFalse(size.width.isNaN)
        }
    }

    func testPlacementUsesBoundsProposalAndDirectGuideOffsets() {
        withGraph { graph in
            let alignment = probeAlignment()
            let low = makeEngine(
                size: CGSize(width: 100, height: 80),
                priority: 0,
                alignment: alignment,
                horizontalGuide: 90,
                verticalGuide: 70
            )
            let highA = makeEngine(
                size: CGSize(width: 20, height: 10),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 3,
                verticalGuide: 4
            )
            let highB = makeEngine(
                size: CGSize(width: 30, height: 40),
                priority: 2,
                alignment: alignment,
                horizontalGuide: 12,
                verticalGuide: 8
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [low, highA, highB],
                layoutDirection: .leftToRight
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()
            let bounds = CGRect(x: 100, y: 200, width: 60, height: 50)

            let geometries = place(
                layout,
                cache: &cache,
                subviews: subviews,
                bounds: bounds,
                proposal: ProposedViewSize(width: 999, height: 777)
            )

            XCTAssertEqual(
                geometries.map(\.origin),
                [
                    CGPoint(x: 22, y: 138),
                    CGPoint(x: 109, y: 204),
                    CGPoint(x: 100, y: 200),
                ]
            )
            let boundsProposal = _ProposedSize(bounds.size)
            XCTAssertEqual(low.proposals, [boundsProposal])
            XCTAssertEqual(
                highA.proposals,
                [boundsProposal, boundsProposal]
            )
            XCTAssertEqual(
                highB.proposals,
                [boundsProposal, boundsProposal]
            )
        }
    }

    func testPlacementAvoidsInfiniteGuideSelfSubtraction() {
        withGraph { graph in
            let alignment = probeAlignment()
            let engine = makeEngine(
                size: CGSize(width: CGFloat.infinity, height: 10),
                priority: 0,
                alignment: alignment,
                horizontalGuide: CGFloat.infinity,
                verticalGuide: 5
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [engine],
                layoutDirection: .leftToRight
            )
            let layout = ZStackLayout(alignment: alignment)
            var cache: Void = ()
            let bounds = CGRect(x: 12, y: 34, width: 60, height: 50)

            let geometries = place(
                layout,
                cache: &cache,
                subviews: subviews,
                bounds: bounds,
                proposal: .unspecified
            )

            XCTAssertEqual(geometries[0].origin, bounds.origin)
            XCTAssertFalse(geometries[0].origin.x.isNaN)
        }
    }

    private func probeAlignment() -> Alignment {
        Alignment(
            horizontal: HorizontalAlignment(
                ZStackHorizontalAlignmentID.self
            ),
            vertical: VerticalAlignment(ZStackVerticalAlignmentID.self)
        )
    }

    private func makeEngine(
        size: CGSize,
        priority: Double,
        alignment: Alignment,
        horizontalGuide: CGFloat,
        verticalGuide: CGFloat,
        spacing: Spacing = Spacing()
    ) -> ZStackProbeLayoutEngine {
        ZStackProbeLayoutEngine(
            size: size,
            priority: priority,
            horizontalKey: alignment.horizontal.key,
            horizontalGuide: horizontalGuide,
            verticalKey: alignment.vertical.key,
            verticalGuide: verticalGuide,
            spacing: spacing
        )
    }

    private func makeSubviews(
        graph: _AGGraph,
        engines: [ZStackProbeLayoutEngine],
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

    private func place(
        _ layout: ZStackLayout,
        cache: inout Void,
        subviews: LayoutSubviews,
        bounds: CGRect,
        proposal: ProposedViewSize
    ) -> [ViewGeometry] {
        var data = PlacementData(
            count: subviews.count,
            bounds: bounds,
            layoutDirection: .leftToRight
        )
        withUnsafeMutablePointer(to: &data) { pointer in
            ThreadLayoutData.withPlacementData(pointer) {
                layout.placeSubviews(
                    in: bounds,
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                )
            }
        }
        XCTAssertEqual(data.placedCount, subviews.count)
        return data.geometries
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            body(graph)
        }
    }
}
