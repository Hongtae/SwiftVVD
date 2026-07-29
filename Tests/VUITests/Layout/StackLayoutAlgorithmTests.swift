import Foundation
import XCTest
@testable import VUI

private final class StackRangeLayoutEngine: LayoutEngine {
    let minimum: CGFloat
    let ideal: CGFloat
    let maximum: CGFloat
    let cross: CGFloat
    let priorityValue: Double
    var proposals: [_ProposedSize] = []

    init(
        minimum: CGFloat,
        ideal: CGFloat,
        maximum: CGFloat,
        cross: CGFloat = 20,
        priority: Double = 0
    ) {
        self.minimum = minimum
        self.ideal = ideal
        self.maximum = maximum
        self.cross = cross
        self.priorityValue = priority
    }

    func layoutPriority() -> Double {
        priorityValue
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        proposals.append(proposal)
        let width: CGFloat
        if let proposed = proposal.width {
            if proposed == .infinity {
                width = maximum
            } else {
                width = min(maximum, max(minimum, proposed))
            }
        } else {
            width = ideal
        }
        return CGSize(
            width: width,
            height: proposal.height ?? cross
        )
    }
}

private final class VerticalStackRangeLayoutEngine: LayoutEngine {
    let minimum: CGFloat
    let ideal: CGFloat
    let maximum: CGFloat
    let cross: CGFloat
    var proposals: [_ProposedSize] = []

    init(
        minimum: CGFloat,
        ideal: CGFloat,
        maximum: CGFloat,
        cross: CGFloat
    ) {
        self.minimum = minimum
        self.ideal = ideal
        self.maximum = maximum
        self.cross = cross
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        proposals.append(proposal)
        let height: CGFloat
        if let proposed = proposal.height {
            if proposed == .infinity {
                height = maximum
            } else {
                height = min(maximum, max(minimum, proposed))
            }
        } else {
            height = ideal
        }
        return CGSize(
            width: proposal.width ?? cross,
            height: height
        )
    }
}

private enum NonlinearStackAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height * 0.5
    }

    static func _combineExplicit(
        childValue: CGFloat,
        _ n: Int,
        into parentValue: inout CGFloat?
    ) {
        parentValue = (parentValue ?? 0) * 2 + childValue
    }
}

private enum OutOfBoundsVerticalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height * 0.5
    }
}

private enum OutOfBoundsHorizontalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.width * 0.5
    }
}

final class StackLayoutAlgorithmTests: XCTestCase {
    func testConcreteMajorProposalUsesObservedPriorityAndFlexibilityOrder() {
        withGraph { graph in
            let a = StackRangeLayoutEngine(
                minimum: 10,
                ideal: 40,
                maximum: 120
            )
            let b = StackRangeLayoutEngine(
                minimum: 20,
                ideal: 60,
                maximum: 160,
                priority: 1
            )
            let c = StackRangeLayoutEngine(
                minimum: 15,
                ideal: 35,
                maximum: 90
            )
            let subviews = makeSubviews(
                graph: graph,
                engines: [a, b, c],
                layoutDirection: .leftToRight
            )
            let layout = HStackLayout(alignment: .center, spacing: 5)
            var cache = layout.makeCache(subviews: subviews)
            let proposal = ProposedViewSize(width: 125, height: 50)

            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                ),
                CGSize(width: 125, height: 50)
            )
            XCTAssertEqual(fittingOrder(in: cache), [1, 2, 0])
            assertProposals(
                a.proposals,
                [
                    _ProposedSize(width: 0, height: 50),
                    _ProposedSize(width: .infinity, height: 50),
                    _ProposedSize(width: 10, height: 50),
                ]
            )
            assertProposals(
                b.proposals,
                [_ProposedSize(width: 90, height: 50)]
            )
            assertProposals(
                c.proposals,
                [
                    _ProposedSize(width: 0, height: 50),
                    _ProposedSize(width: .infinity, height: 50),
                    _ProposedSize(width: 12.5, height: 50),
                ]
            )

            let measurementCounts = [a.proposals.count, b.proposals.count, c.proposals.count]
            let geometries = place(
                layout,
                cache: &cache,
                subviews: subviews,
                bounds: CGRect(x: 0, y: 0, width: 125, height: 50),
                proposal: proposal,
                layoutDirection: .leftToRight
            )
            XCTAssertEqual([a.proposals.count, b.proposals.count, c.proposals.count], measurementCounts)
            XCTAssertEqual(geometries.map(\.origin.x), [0, 15, 110])
            XCTAssertEqual(geometries.map(\.dimensions.width), [10, 90, 15])
        }
    }

    func testEqualFiniteAndInfiniteFittingRangesPreserveDeclarationOrder() {
        withGraph { graph in
            let finite = [
                StackRangeLayoutEngine(minimum: 10, ideal: 40, maximum: 110),
                StackRangeLayoutEngine(minimum: 10, ideal: 40, maximum: 110),
                StackRangeLayoutEngine(minimum: 15, ideal: 30, maximum: 45),
            ]
            let finiteSubviews = makeSubviews(
                graph: graph,
                engines: finite,
                layoutDirection: .leftToRight
            )
            let layout = HStackLayout(alignment: .center, spacing: 5)
            var finiteCache = layout.makeCache(subviews: finiteSubviews)
            _ = layout.sizeThatFits(
                proposal: ProposedViewSize(width: 150, height: 50),
                subviews: finiteSubviews,
                cache: &finiteCache
            )
            XCTAssertEqual(fittingOrder(in: finiteCache), [2, 0, 1])

            let infinite = [
                StackRangeLayoutEngine(minimum: 10, ideal: 40, maximum: .infinity),
                StackRangeLayoutEngine(minimum: 10, ideal: 40, maximum: .infinity),
                StackRangeLayoutEngine(minimum: 15, ideal: 30, maximum: 90),
            ]
            let infiniteSubviews = makeSubviews(
                graph: graph,
                engines: infinite,
                layoutDirection: .leftToRight
            )
            var infiniteCache = layout.makeCache(subviews: infiniteSubviews)
            _ = layout.sizeThatFits(
                proposal: ProposedViewSize(width: 150, height: 50),
                subviews: infiniteSubviews,
                cache: &infiniteCache
            )
            XCTAssertEqual(fittingOrder(in: infiniteCache), [2, 0, 1])
        }
    }

    func testConcreteMajorBudgetClampsAtZeroAndDoesNotBecomeNaNAtInfinity() {
        withGraph { graph in
            let zeroEngines = [
                StackRangeLayoutEngine(
                    minimum: 10,
                    ideal: 40,
                    maximum: .infinity
                ),
                StackRangeLayoutEngine(
                    minimum: 20,
                    ideal: 60,
                    maximum: .infinity
                ),
                StackRangeLayoutEngine(
                    minimum: 15,
                    ideal: 35,
                    maximum: 90
                ),
            ]
            let zeroSubviews = makeSubviews(
                graph: graph,
                engines: zeroEngines,
                layoutDirection: .leftToRight
            )
            let layout = HStackLayout(alignment: .center, spacing: 5)
            var zeroCache = layout.makeCache(subviews: zeroSubviews)

            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: ProposedViewSize(width: 0, height: 50),
                    subviews: zeroSubviews,
                    cache: &zeroCache
                ),
                CGSize(width: 55, height: 50)
            )
            for engine in zeroEngines {
                XCTAssertEqual(engine.proposals.last?.width, 0)
                XCTAssertFalse(
                    engine.proposals.contains {
                        guard let width = $0.width else { return false }
                        return width < 0 || width.isNaN
                    }
                )
            }

            let infiniteEngines = [
                StackRangeLayoutEngine(
                    minimum: 10,
                    ideal: 40,
                    maximum: .infinity
                ),
                StackRangeLayoutEngine(
                    minimum: 20,
                    ideal: 60,
                    maximum: .infinity
                ),
                StackRangeLayoutEngine(
                    minimum: 15,
                    ideal: 35,
                    maximum: 90
                ),
            ]
            let infiniteSubviews = makeSubviews(
                graph: graph,
                engines: infiniteEngines,
                layoutDirection: .leftToRight
            )
            var infiniteCache = layout.makeCache(subviews: infiniteSubviews)

            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: ProposedViewSize(width: .infinity, height: 50),
                    subviews: infiniteSubviews,
                    cache: &infiniteCache
                ),
                CGSize(width: CGFloat.infinity, height: 50)
            )
            for engine in infiniteEngines {
                XCTAssertEqual(engine.proposals.last?.width, .infinity)
                XCTAssertFalse(
                    engine.proposals.contains {
                        $0.width?.isNaN == true
                    }
                )
            }
        }
    }

    func testUnspecifiedMajorAxisStaysUnspecifiedDuringPlacement() {
        withGraph { graph in
            let hA = StackRangeLayoutEngine(
                minimum: 10,
                ideal: 30,
                maximum: 90,
                cross: 10
            )
            let hB = StackRangeLayoutEngine(
                minimum: 10,
                ideal: 40,
                maximum: 100,
                cross: 20
            )
            let hSubviews = makeSubviews(
                graph: graph,
                engines: [hA, hB],
                layoutDirection: .leftToRight
            )
            let hLayout = HStackLayout(alignment: .center, spacing: 5)
            var hCache = hLayout.makeCache(subviews: hSubviews)
            XCTAssertEqual(
                hLayout.sizeThatFits(
                    proposal: .unspecified,
                    subviews: hSubviews,
                    cache: &hCache
                ),
                CGSize(width: 75, height: 20)
            )
            assertProposals(hA.proposals, [.unspecified])
            assertProposals(hB.proposals, [.unspecified])

            _ = place(
                hLayout,
                cache: &hCache,
                subviews: hSubviews,
                bounds: CGRect(x: 0, y: 0, width: 75, height: 20),
                proposal: .unspecified,
                layoutDirection: .leftToRight
            )
            assertProposals(
                hA.proposals,
                [.unspecified, _ProposedSize(width: nil, height: 20)]
            )
            assertProposals(
                hB.proposals,
                [.unspecified, _ProposedSize(width: nil, height: 20)]
            )

            let vA = VerticalStackRangeLayoutEngine(
                minimum: 10,
                ideal: 30,
                maximum: 90,
                cross: 10
            )
            let vB = VerticalStackRangeLayoutEngine(
                minimum: 10,
                ideal: 40,
                maximum: 100,
                cross: 20
            )
            let vSubviews = makeSubviews(
                graph: graph,
                engines: [vA, vB],
                layoutDirection: .leftToRight
            )
            let vLayout = VStackLayout(alignment: .center, spacing: 5)
            var vCache = vLayout.makeCache(subviews: vSubviews)
            XCTAssertEqual(
                vLayout.sizeThatFits(
                    proposal: .unspecified,
                    subviews: vSubviews,
                    cache: &vCache
                ),
                CGSize(width: 20, height: 75)
            )
            _ = place(
                vLayout,
                cache: &vCache,
                subviews: vSubviews,
                bounds: CGRect(x: 0, y: 0, width: 20, height: 75),
                proposal: .unspecified,
                layoutDirection: .leftToRight
            )
            assertProposals(
                vA.proposals,
                [.unspecified, _ProposedSize(width: 20, height: nil)]
            )
            assertProposals(
                vB.proposals,
                [.unspecified, _ProposedSize(width: 20, height: nil)]
            )
        }
    }

    func testStackPlacementMirrorsOnlyAtTheRTLCommitBoundary() {
        withGraph { graph in
            let hLTR = fixedSubviews(
                graph: graph,
                sizes: [
                    CGSize(width: 20, height: 10),
                    CGSize(width: 30, height: 20),
                ],
                layoutDirection: .leftToRight
            )
            let hRTL = fixedSubviews(
                graph: graph,
                sizes: [
                    CGSize(width: 20, height: 10),
                    CGSize(width: 30, height: 20),
                ],
                layoutDirection: .rightToLeft
            )
            let hLayout = HStackLayout(alignment: .top, spacing: 10)
            var hLTRCache = hLayout.makeCache(subviews: hLTR)
            var hRTLCache = hLayout.makeCache(subviews: hRTL)
            let hBounds = CGRect(x: 0, y: 0, width: 60, height: 20)
            let hProposal = ProposedViewSize(width: 60, height: 20)

            let hLTRGeometry = place(
                hLayout,
                cache: &hLTRCache,
                subviews: hLTR,
                bounds: hBounds,
                proposal: hProposal,
                layoutDirection: .leftToRight
            )
            let hRTLGeometry = place(
                hLayout,
                cache: &hRTLCache,
                subviews: hRTL,
                bounds: hBounds,
                proposal: hProposal,
                layoutDirection: .rightToLeft
            )
            XCTAssertEqual(hLTRGeometry.map(\.origin), [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 30, y: 0),
            ])
            XCTAssertEqual(hRTLGeometry.map(\.origin), [
                CGPoint(x: 40, y: 0),
                CGPoint(x: 0, y: 0),
            ])

            let vLTR = fixedSubviews(
                graph: graph,
                sizes: [
                    CGSize(width: 20, height: 10),
                    CGSize(width: 30, height: 20),
                ],
                layoutDirection: .leftToRight
            )
            let vRTL = fixedSubviews(
                graph: graph,
                sizes: [
                    CGSize(width: 20, height: 10),
                    CGSize(width: 30, height: 20),
                ],
                layoutDirection: .rightToLeft
            )
            let vLayout = VStackLayout(alignment: .leading, spacing: 10)
            var vLTRCache = vLayout.makeCache(subviews: vLTR)
            var vRTLCache = vLayout.makeCache(subviews: vRTL)
            let vBounds = CGRect(x: 0, y: 0, width: 30, height: 40)
            let vProposal = ProposedViewSize(width: 30, height: 40)

            let vLTRGeometry = place(
                vLayout,
                cache: &vLTRCache,
                subviews: vLTR,
                bounds: vBounds,
                proposal: vProposal,
                layoutDirection: .leftToRight
            )
            let vRTLGeometry = place(
                vLayout,
                cache: &vRTLCache,
                subviews: vRTL,
                bounds: vBounds,
                proposal: vProposal,
                layoutDirection: .rightToLeft
            )
            XCTAssertEqual(vLTRGeometry.map(\.origin), [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 0, y: 20),
            ])
            XCTAssertEqual(vRTLGeometry.map(\.origin), [
                CGPoint(x: 10, y: 0),
                CGPoint(x: 0, y: 20),
            ])
        }
    }

    func testStackCrossAxisRangeIncludesZeroOutsideChildGuideBounds() {
        withGraph { graph in
            let verticalGuide = VerticalAlignment(
                OutOfBoundsVerticalAlignmentID.self
            )
            let horizontalGuide = HorizontalAlignment(
                OutOfBoundsHorizontalAlignmentID.self
            )

            for (guideValue, expectedSize, expectedOrigin) in [
                (
                    CGFloat(-6),
                    CGSize(width: 40, height: 16),
                    CGPoint(x: 0, y: 6)
                ),
                (
                    CGFloat(16),
                    CGSize(width: 40, height: 16),
                    CGPoint(x: 0, y: 0)
                ),
            ] {
                let subviews = alignedSubviews(
                    graph: graph,
                    count: 2,
                    size: CGSize(width: 20, height: 10),
                    guide: verticalGuide.key,
                    value: guideValue
                )
                let layout = HStackLayout(
                    alignment: verticalGuide,
                    spacing: 0
                )
                var cache = layout.makeCache(subviews: subviews)
                XCTAssertEqual(
                    layout.sizeThatFits(
                        proposal: .unspecified,
                        subviews: subviews,
                        cache: &cache
                    ),
                    expectedSize
                )
                let geometries = place(
                    layout,
                    cache: &cache,
                    subviews: subviews,
                    bounds: CGRect(origin: .zero, size: expectedSize),
                    proposal: .unspecified,
                    layoutDirection: .leftToRight
                )
                XCTAssertEqual(geometries.first?.origin, expectedOrigin)
            }

            for (guideValue, expectedSize, expectedOrigin) in [
                (
                    CGFloat(-6),
                    CGSize(width: 26, height: 20),
                    CGPoint(x: 6, y: 0)
                ),
                (
                    CGFloat(26),
                    CGSize(width: 26, height: 20),
                    CGPoint(x: 0, y: 0)
                ),
            ] {
                let subviews = alignedSubviews(
                    graph: graph,
                    count: 2,
                    size: CGSize(width: 20, height: 10),
                    guide: horizontalGuide.key,
                    value: guideValue
                )
                let layout = VStackLayout(
                    alignment: horizontalGuide,
                    spacing: 0
                )
                var cache = layout.makeCache(subviews: subviews)
                XCTAssertEqual(
                    layout.sizeThatFits(
                        proposal: .unspecified,
                        subviews: subviews,
                        cache: &cache
                    ),
                    expectedSize
                )
                let geometries = place(
                    layout,
                    cache: &cache,
                    subviews: subviews,
                    bounds: CGRect(origin: .zero, size: expectedSize),
                    proposal: .unspecified,
                    layoutDirection: .leftToRight
                )
                XCTAssertEqual(geometries.first?.origin, expectedOrigin)
            }
        }
    }

    func testStackAddsBoundsOriginAfterCombiningCustomExplicitAlignment() {
        withGraph { graph in
            let guide = VerticalAlignment(NonlinearStackAlignmentID.self)
            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let attributes = [CGFloat(3), CGFloat(5)].map { explicitValue in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(
                            sizeThatFits: { _ in
                                CGSize(width: 20, height: 10)
                            },
                            explicitAlignment: { key, _ in
                                key == guide.key ? explicitValue : nil
                            }
                        )
                    )
                )
            }
            let subviews = LayoutSubviews(
                context: context,
                attributes: attributes,
                layoutDirection: .leftToRight
            )
            let layout = HStackLayout(alignment: .top, spacing: 0)
            var cache = layout.makeCache(subviews: subviews)

            XCTAssertEqual(
                layout.explicitAlignment(
                    of: guide,
                    in: CGRect(x: 20, y: 100, width: 40, height: 10),
                    proposal: ProposedViewSize(width: 40, height: 10),
                    subviews: subviews,
                    cache: &cache
                ),
                111
            )
        }
    }

    func testStackSpacingSelectsSemanticOuterEdgesUsingLayoutDirection() {
        withGraph { graph in
            let layout = HStackLayout(alignment: .center, spacing: nil)
            let ltrSubviews = asymmetricSpacingSubviews(
                graph: graph,
                layoutDirection: .leftToRight
            )
            var ltrCache = layout.makeCache(subviews: ltrSubviews)
            let ltr = layout.spacing(
                subviews: ltrSubviews,
                cache: &ltrCache
            )
            XCTAssertEqual(spacingValue(ltr, edge: .left), 1)
            XCTAssertEqual(spacingValue(ltr, edge: .right), 4)

            let rtlSubviews = asymmetricSpacingSubviews(
                graph: graph,
                layoutDirection: .rightToLeft
            )
            var rtlCache = layout.makeCache(subviews: rtlSubviews)
            let rtl = layout.spacing(
                subviews: rtlSubviews,
                cache: &rtlCache
            )
            XCTAssertEqual(spacingValue(rtl, edge: .left), 3)
            XCTAssertEqual(spacingValue(rtl, edge: .right), 2)
        }
    }

    private func makeSubviews<E: LayoutEngine>(
        graph: _AGGraph,
        engines: [E],
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
                        value: LayoutComputer(
                            box: LayoutEngineBox(engine: engine)
                        )
                    )
                )
            },
            layoutDirection: layoutDirection
        )
    }

    private func fixedSubviews(
        graph: _AGGraph,
        sizes: [CGSize],
        layoutDirection: LayoutDirection
    ) -> LayoutSubviews {
        let context = AnyRuleContext(
            attribute: graph.makeInput(value: ()).identifier
        )
        return LayoutSubviews(
            context: context,
            attributes: sizes.map { size in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.fixed(size)
                    )
                )
            },
            layoutDirection: layoutDirection
        )
    }

    private func alignedSubviews(
        graph: _AGGraph,
        count: Int,
        size: CGSize,
        guide: AlignmentKey,
        value: CGFloat
    ) -> LayoutSubviews {
        let context = AnyRuleContext(
            attribute: graph.makeInput(value: ()).identifier
        )
        return LayoutSubviews(
            context: context,
            attributes: (0..<count).map { _ in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(
                            sizeThatFits: { _ in size },
                            explicitAlignment: { requested, _ in
                                requested == guide ? value : nil
                            }
                        )
                    )
                )
            },
            layoutDirection: .leftToRight
        )
    }

    private func asymmetricSpacingSubviews(
        graph: _AGGraph,
        layoutDirection: LayoutDirection
    ) -> LayoutSubviews {
        let context = AnyRuleContext(
            attribute: graph.makeInput(value: ()).identifier
        )
        let edgePairs: [(left: CGFloat, right: CGFloat)] = [
            (1, 2),
            (3, 4),
        ]
        return LayoutSubviews(
            context: context,
            attributes: edgePairs.map { pair in
                let spacing = Spacing(minima: [
                    Spacing.Key(category: .default, edge: .left):
                        .distance(pair.left),
                    Spacing.Key(category: .default, edge: .right):
                        .distance(pair.right),
                ])
                return LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(
                            sizeThatFits: { _ in
                                CGSize(width: 20, height: 10)
                            },
                            spacing: spacing
                        )
                    )
                )
            },
            layoutDirection: layoutDirection
        )
    }

    private func spacingValue(
        _ spacing: ViewSpacing,
        edge: AbsoluteEdge
    ) -> CGFloat? {
        spacing.spacing.minima[
            Spacing.Key(category: .default, edge: edge)
        ]?.value
    }

    private func place<L: Layout>(
        _ layout: L,
        cache: inout L.Cache,
        subviews: LayoutSubviews,
        bounds: CGRect,
        proposal: ProposedViewSize,
        layoutDirection: LayoutDirection
    ) -> [ViewGeometry] where L.Subviews == LayoutSubviews {
        var data = PlacementData(
            count: subviews.count,
            bounds: bounds,
            layoutDirection: layoutDirection
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
        return data.geometries
    }

    private func fittingOrder(in cache: _StackLayoutCache) -> [Int] {
        guard let stack = reflectedField(cache, named: "stack"),
              let children = reflectedField(stack, named: "children") else {
            XCTFail("The reflected stack-cache structure changed.")
            return []
        }
        return Mirror(reflecting: children).children.compactMap { child in
            reflectedField(child.value, named: "fittingOrder") as? Int
        }
    }

    private func reflectedField(_ value: Any, named name: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    private func assertProposals(
        _ actual: [_ProposedSize],
        _ expected: [_ProposedSize],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func withGraph(_ body: (_ graph: _AGGraph) -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            body(graph)
        }
    }
}
