import Foundation
import XCTest
@testable import VUI

private final class CountingLayoutEngine: LayoutEngine {
    var proposals: [_ProposedSize] = []

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        proposals.append(proposal)
        return CGSize(width: proposal.width ?? 7, height: proposal.height ?? 11)
    }
}

private final class LayoutCacheProbeState: @unchecked Sendable {
    var makeCacheCount = 0
    var updateCacheCount = 0
    var storage: LayoutCacheProbeStorage?
}

private final class LayoutCacheProbeStorage {
    var sizeCount = 0
    var placementCount = 0
    var alignmentCount = 0
    var proposals: [ProposedViewSize] = []
    var placementProposals: [ProposedViewSize] = []
    var placementBounds: [CGRect] = []
    var placementTransactionValues: [Int] = []
}

private struct LayoutPlacementTransactionKey: TransactionKey {
    static let defaultValue = 0
}

private enum LayoutCacheAlignmentA: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private enum LayoutCacheAlignmentB: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private enum LayoutCacheAlignmentC: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private enum LayoutCacheNilAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private final class PlacementDataBox: @unchecked Sendable {
    var value: PlacementData

    init(_ value: PlacementData) {
        self.value = value
    }
}

private final class DefaultAlignmentProbeState: @unchecked Sendable {
    var placementCount = 0
}

private final class ExplicitAlignmentProbeEngine: LayoutEngine {
    var size: CGSize
    var horizontal: CGFloat?
    var vertical: CGFloat?

    init(size: CGSize, horizontal: CGFloat?, vertical: CGFloat?) {
        self.size = size
        self.horizontal = horizontal
        self.vertical = vertical
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        size
    }

    func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        switch key.axis {
        case .horizontal: horizontal
        case .vertical: vertical
        }
    }
}

private struct DefaultAlignmentProbeLayout: Layout {
    var state: DefaultAlignmentProbeState
    var size: CGSize
    var origins: [CGPoint]

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        state.placementCount += 1
        for (subview, origin) in zip(subviews, origins) {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + origin.x,
                    y: bounds.minY + origin.y
                ),
                dimensions: subview.dimensions(in: .unspecified)
            )
        }
    }
}

private struct LayoutCacheProbe: Layout {
    var state: LayoutCacheProbeState
    var reportedSize: CGSize

    func makeCache(subviews: Subviews) -> LayoutCacheProbeStorage {
        state.makeCacheCount += 1
        let storage = LayoutCacheProbeStorage()
        state.storage = storage
        return storage
    }

    func updateCache(
        _ cache: inout LayoutCacheProbeStorage,
        subviews: Subviews
    ) {
        state.updateCacheCount += 1
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout LayoutCacheProbeStorage
    ) -> CGSize {
        cache.sizeCount += 1
        cache.proposals.append(proposal)
        return reportedSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout LayoutCacheProbeStorage
    ) {
        cache.placementCount += 1
        cache.placementProposals.append(proposal)
        cache.placementBounds.append(bounds)
        cache.placementTransactionValues.append(
            Transaction.current[LayoutPlacementTransactionKey.self]
        )
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout LayoutCacheProbeStorage
    ) -> CGFloat? {
        cache.alignmentCount += 1
        if ObjectIdentifier(guide.key.id) ==
            ObjectIdentifier(LayoutCacheNilAlignment.self) {
            return nil
        }
        return bounds.width
    }
}

private final class AlternateLayoutCacheProbeState: @unchecked Sendable {
    var makeCacheCount = 0
    var updateCacheCount = 0
    var sizeCount = 0
}

private struct AlternateLayoutCacheProbe: Layout {
    var state: AlternateLayoutCacheProbeState
    var reportedSize: CGSize

    func makeCache(subviews: Subviews) -> Int {
        state.makeCacheCount += 1
        return 0
    }

    func updateCache(_ cache: inout Int, subviews: Subviews) {
        state.updateCacheCount += 1
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Int
    ) -> CGSize {
        cache += 1
        state.sizeCount += 1
        return reportedSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Int
    ) {}
}

private struct StatefulLayoutComputerEngine: LayoutEngine, Equatable {
    var size: CGSize

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        size
    }
}

private struct StatefulLayoutComputerRule: StatefulRule {
    typealias Value = LayoutComputer

    var size: Attribute<CGSize>

    mutating func updateValue() {
        updateIfNotEqual(to: StatefulLayoutComputerEngine(size: size.value))
    }
}

private func makeLayoutContext(
    children: [LayoutProxyAttributes],
    layoutDirection: LayoutDirection
) -> (SizeAndSpacingContext, LayoutProxyCollection) {
    guard let graph = _AGGraph.current else {
        fatalError("A current graph is required by layout tests.")
    }
    let owner = graph.makeInput(value: 0)
    var environment = EnvironmentValues()
    environment.layoutDirection = layoutDirection
    let environmentAttribute = graph.makeInput(value: environment)
    let context = AnyRuleContext(attribute: owner.identifier)
    return (
        SizeAndSpacingContext(
            context: context,
            owner: owner.identifier,
            environment: environmentAttribute
        ),
        LayoutProxyCollection(context: context, attributes: children)
    )
}

final class LayoutEngineCacheTests: XCTestCase {
    func testLayoutPropertiesMatchCurrentStoredDefaults() {
        let properties = LayoutProperties()

        XCTAssertNil(properties.stackOrientation)
        XCTAssertFalse(properties.isDefaultEmptyLayout)
        XCTAssertFalse(properties.isIdentityUnaryLayout)
        XCTAssertEqual(MemoryLayout<LayoutProperties>.size, 3)
    }

    func testClosureLayoutComputerPlacementCanReadItsOwnSize() {
        withGraph {
            var computer: LayoutComputer!
            var measuredSize: CGSize?
            computer = testLayoutComputer(
                sizeThatFits: { _ in CGSize(width: 24, height: 18) },
                place: { _, _, proposal in
                    measuredSize = computer.sizeThatFits(_ProposedSize(proposal))
                }
            )

            computer.place(
                at: CGPoint(x: 10, y: 12),
                proposal: ProposedViewSize(width: 30, height: 20)
            )

            XCTAssertEqual(measuredSize, CGSize(width: 24, height: 18))
        }
    }

    func testStatefulLayoutComputerReusesEngineBoxAcrossValueUpdates() {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            let size = graph.makeInput(value: CGSize(width: 10, height: 20))
            let computer = graph.makeStatefulRule(
                StatefulLayoutComputerRule(size: size)
            )

            let initial = computer.value
            size.setValue(CGSize(width: 10, height: 20))
            let unchanged = computer.value
            XCTAssertTrue(initial.box === unchanged.box)

            size.setValue(CGSize(width: 30, height: 40))
            let changed = computer.value
            XCTAssertTrue(initial.box === changed.box)
            XCTAssertEqual(
                changed.sizeThatFits(.unspecified),
                CGSize(width: 30, height: 40)
            )
        }
    }

    func testPlacementDataIsIsolatedToTheCurrentThread() {
        withGraph {
            let box = PlacementDataBox(
                PlacementData(
                    count: 1,
                    bounds: .zero,
                    layoutDirection: .leftToRight
                )
            )
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                withUnsafeMutablePointer(to: &box.value) { pointer in
                    ThreadLayoutData.withPlacementData(pointer) {
                        entered.signal()
                        _ = release.wait(timeout: .now() + 2)
                    }
                }
                finished.signal()
            }

            XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
            let acceptedForeignPlacement = ThreadLayoutData.setGeometry(
                .zero,
                at: 0,
                layoutDirection: .leftToRight
            )
            release.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
            XCTAssertFalse(acceptedForeignPlacement)
        }
    }

    func testPlacementDataMirrorsAcrossNonzeroBoundsOrigin() {
        withGraph {
            let bounds = CGRect(x: 100, y: 50, width: 200, height: 80)
            var data = PlacementData(
                count: 1,
                bounds: bounds,
                layoutDirection: .leftToRight
            )
            let geometry = ViewGeometry(
                origin: CGPoint(x: 130, y: 60),
                dimensions: ViewDimensions(
                    guideComputer: .defaultValue,
                    size: ViewSize.fixed(CGSize(width: 20, height: 10))
                )
            )

            data.setGeometry(
                geometry,
                at: 0,
                layoutDirection: .rightToLeft
            )

            XCTAssertEqual(data.geometries[0].origin, CGPoint(x: 250, y: 60))
            XCTAssertEqual(data.geometries[0].dimensions, geometry.dimensions)
        }
    }

    func testPlacementDataUsesOriginXNaNAsOnlyEmptySlotSentinel() {
        withGraph {
            var data = PlacementData(
                count: 2,
                bounds: CGRect(x: 100, y: 50, width: 200, height: 80),
                layoutDirection: .leftToRight
            )
            let geometry = ViewGeometry(
                origin: CGPoint(x: 17, y: CGFloat.nan),
                dimensions: ViewDimensions(
                    guideComputer: .defaultValue,
                    size: ViewSize.fixed(CGSize(width: 20, height: 10))
                )
            )

            data.setGeometry(
                geometry,
                at: 0,
                layoutDirection: .leftToRight
            )

            XCTAssertEqual(data.placedCount, 1)
            let resolved = data.resolvedGeometries(
                children: [LayoutProxyAttributes(), LayoutProxyAttributes()],
                proposal: .unspecified
            )
            XCTAssertEqual(resolved[0].origin.x, 17)
            XCTAssertTrue(resolved[0].origin.y.isNaN)
            XCTAssertEqual(resolved[0].dimensions, geometry.dimensions)
            XCTAssertEqual(data.placedCount, 2)
        }
    }

    func testLayoutSubviewPlacementPreservesZeroAnchorAndInfiniteOrigins() {
        withGraph {
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            let proxy = LayoutProxy(
                context: inputs.1.context,
                attributes: LayoutProxyAttributes()
            )
            let finiteOriginSubview = LayoutSubview(proxy: proxy, index: 0)
            let infiniteOriginSubview = LayoutSubview(proxy: proxy, index: 1)
            var data = PlacementData(
                count: 2,
                bounds: .zero,
                layoutDirection: .leftToRight
            )

            withUnsafeMutablePointer(to: &data) { pointer in
                ThreadLayoutData.withPlacementData(pointer) {
                    finiteOriginSubview.place(
                        at: CGPoint(x: 12, y: 14),
                        anchor: .topLeading,
                        dimensions: ViewDimensions(
                            guideComputer: .defaultValue,
                            size: ViewSize.fixed(
                                CGSize(width: CGFloat.infinity, height: 10)
                            )
                        )
                    )
                    infiniteOriginSubview.place(
                        at: CGPoint(x: CGFloat.infinity, y: 18),
                        anchor: .topLeading,
                        dimensions: ViewDimensions(
                            guideComputer: .defaultValue,
                            size: ViewSize.fixed(CGSize(width: 20, height: 10))
                        )
                    )
                }
            }

            XCTAssertEqual(data.geometries[0].origin, CGPoint(x: 12, y: 14))
            XCTAssertTrue(data.geometries[0].dimensions.width.isInfinite)
            XCTAssertTrue(data.geometries[1].origin.x.isInfinite)
            XCTAssertEqual(data.geometries[1].origin.y, 18)
            XCTAssertEqual(data.placedCount, 2)
        }
    }

    func testViewLayoutEngineCachesThreeProposalsInInsertionOrder() {
        withGraph {
            let state = LayoutCacheProbeState()
            let layout = LayoutCacheProbe(
                state: state,
                reportedSize: CGSize(width: 7, height: 11)
            )
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: layout,
                context: inputs.0,
                children: inputs.1
            )
            let a = _ProposedSize(width: 10, height: nil)
            let b = _ProposedSize(width: 20, height: nil)
            let c = _ProposedSize(width: 30, height: nil)
            let d = _ProposedSize(width: 40, height: nil)

            _ = engine.sizeThatFits(a)
            _ = engine.sizeThatFits(b)
            _ = engine.sizeThatFits(c)
            _ = engine.sizeThatFits(a)
            let storage = try! XCTUnwrap(state.storage)
            XCTAssertEqual(storage.proposals, [a, b, c].map(ProposedViewSize.init))

            _ = engine.sizeThatFits(d)
            _ = engine.sizeThatFits(b)
            _ = engine.sizeThatFits(c)
            _ = engine.sizeThatFits(a)
            XCTAssertEqual(storage.proposals, [a, b, c, d, a].map(ProposedViewSize.init))

            let updatedInputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            engine.update(
                layout: layout,
                context: updatedInputs.0,
                children: updatedInputs.1
            )
            _ = engine.sizeThatFits(a)
            XCTAssertEqual(storage.proposals, [a, b, c, d, a, a].map(ProposedViewSize.init))
        }
    }

    func testViewLayoutEngineKeepsLayoutCacheAndInvalidatesDerivedCachesOnUpdate() {
        withGraph {
            let state = LayoutCacheProbeState()
            let initial = LayoutCacheProbe(
                state: state,
                reportedSize: CGSize(width: 10, height: 12)
            )
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: initial,
                context: inputs.0,
                children: inputs.1
            )

            XCTAssertEqual(state.makeCacheCount, 1)
            XCTAssertEqual(engine.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
            XCTAssertEqual(engine.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))

            let storage = try! XCTUnwrap(state.storage)
            XCTAssertEqual(storage.sizeCount, 1)

            let viewSize = ViewSize(CGSize(width: 10, height: 12))
            XCTAssertEqual(engine.childGeometries(at: viewSize, origin: .zero), [])
            XCTAssertEqual(engine.childGeometries(at: viewSize, origin: .zero), [])
            XCTAssertEqual(storage.placementCount, 2)

            let updatedInputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            engine.update(
                layout: LayoutCacheProbe(
                    state: state,
                    reportedSize: CGSize(width: 20, height: 24)
                ),
                context: updatedInputs.0,
                children: updatedInputs.1
            )

            XCTAssertEqual(state.makeCacheCount, 1)
            XCTAssertEqual(state.updateCacheCount, 1)
            XCTAssertEqual(engine.sizeThatFits(.unspecified), CGSize(width: 20, height: 24))
            XCTAssertEqual(storage.sizeCount, 2)

            let updatedSize = ViewSize(CGSize(width: 20, height: 24))
            XCTAssertEqual(engine.childGeometries(at: updatedSize, origin: .zero), [])
            XCTAssertEqual(storage.placementCount, 3)
        }
    }

    func testAnyLayoutRebuildsCacheWhenConcreteLayoutTypeChanges() {
        withGraph {
            let initialState = LayoutCacheProbeState()
            let alternateState = AlternateLayoutCacheProbeState()
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: AnyLayout(
                    LayoutCacheProbe(
                        state: initialState,
                        reportedSize: CGSize(width: 10, height: 12)
                    )
                ),
                context: inputs.0,
                children: inputs.1
            )

            XCTAssertEqual(initialState.makeCacheCount, 1)
            XCTAssertEqual(
                engine.sizeThatFits(.unspecified),
                CGSize(width: 10, height: 12)
            )

            let updatedInputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            engine.update(
                layout: AnyLayout(
                    AlternateLayoutCacheProbe(
                        state: alternateState,
                        reportedSize: CGSize(width: 20, height: 24)
                    )
                ),
                context: updatedInputs.0,
                children: updatedInputs.1
            )

            XCTAssertEqual(alternateState.makeCacheCount, 1)
            XCTAssertEqual(alternateState.updateCacheCount, 0)
            XCTAssertEqual(
                engine.sizeThatFits(.unspecified),
                CGSize(width: 20, height: 24)
            )
            XCTAssertEqual(alternateState.sizeCount, 1)

            let sameTypeInputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            engine.update(
                layout: AnyLayout(
                    AlternateLayoutCacheProbe(
                        state: alternateState,
                        reportedSize: CGSize(width: 30, height: 36)
                    )
                ),
                context: sameTypeInputs.0,
                children: sameTypeInputs.1
            )

            XCTAssertEqual(alternateState.makeCacheCount, 1)
            XCTAssertEqual(alternateState.updateCacheCount, 1)
            XCTAssertEqual(
                engine.sizeThatFits(.unspecified),
                CGSize(width: 30, height: 36)
            )
        }
    }

    func testViewLayoutEnginePlacementPreservesOriginalProposal() {
        withGraph {
            let state = LayoutCacheProbeState()
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: LayoutCacheProbe(
                    state: state,
                    reportedSize: CGSize(width: 80, height: 30)
                ),
                context: inputs.0,
                children: inputs.1
            )
            let proposal = _ProposedSize(width: 240, height: nil)
            let size = engine.sizeThatFits(proposal)

            _ = engine.childGeometries(
                at: ViewSize(size, proposal: proposal),
                origin: .zero
            )

            let storage = try! XCTUnwrap(state.storage)
            XCTAssertEqual(
                storage.placementProposals,
                [ProposedViewSize(proposal)]
            )
            XCTAssertEqual(
                storage.placementBounds,
                [CGRect(origin: .zero, size: size)]
            )
        }
    }

    func testViewLayoutEnginePlacementDoesNotInstallNodeTransaction() {
        withGraph {
            let state = LayoutCacheProbeState()
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: LayoutCacheProbe(
                    state: state,
                    reportedSize: CGSize(width: 80, height: 30)
                ),
                context: inputs.0,
                children: inputs.1
            )

            var nodeTransaction = Transaction()
            nodeTransaction[LayoutPlacementTransactionKey.self] = 73
            Attribute<Int>(inputs.1.context.attribute).setValue(
                1,
                transaction: nodeTransaction
            )

            var ambientTransaction = Transaction()
            ambientTransaction[LayoutPlacementTransactionKey.self] = 11
            Transaction.withScopedThreadTransaction(ambientTransaction) {
                _ = engine.childGeometries(
                    at: ViewSize(
                        CGSize(width: 80, height: 30),
                        proposal: .unspecified
                    ),
                    origin: .zero
                )
            }

            XCTAssertEqual(
                state.storage?.placementTransactionValues,
                [11]
            )
        }
    }

    func testViewLayoutEngineCachesThreeExplicitAlignmentsAndInvalidatesForSize() {
        withGraph {
            let state = LayoutCacheProbeState()
            let inputs = makeLayoutContext(
                children: [],
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: LayoutCacheProbe(
                    state: state,
                    reportedSize: CGSize(width: 10, height: 12)
                ),
                context: inputs.0,
                children: inputs.1
            )
            let storage = try! XCTUnwrap(state.storage)
            let size = ViewSize(CGSize(width: 10, height: 12))
            let keyA = HorizontalAlignment(LayoutCacheAlignmentA.self).key
            let keyB = HorizontalAlignment(LayoutCacheAlignmentB.self).key
            let keyC = HorizontalAlignment(LayoutCacheAlignmentC.self).key
            let nilKey = HorizontalAlignment(LayoutCacheNilAlignment.self).key

            XCTAssertEqual(engine.explicitAlignment(keyA, at: size), 10)
            XCTAssertEqual(engine.explicitAlignment(keyA, at: size), 10)
            XCTAssertEqual(storage.alignmentCount, 1)

            XCTAssertNil(engine.explicitAlignment(nilKey, at: size))
            XCTAssertNil(engine.explicitAlignment(nilKey, at: size))
            XCTAssertEqual(storage.alignmentCount, 2)

            XCTAssertEqual(engine.explicitAlignment(keyB, at: size), 10)
            XCTAssertEqual(engine.explicitAlignment(keyC, at: size), 10)
            XCTAssertEqual(engine.explicitAlignment(keyA, at: size), 10)
            XCTAssertEqual(storage.alignmentCount, 5)

            let resized = ViewSize(CGSize(width: 20, height: 24))
            XCTAssertEqual(engine.childGeometries(at: resized, origin: .zero), [])
            XCTAssertEqual(engine.explicitAlignment(keyA, at: resized), 20)
            XCTAssertEqual(storage.alignmentCount, 6)
        }
    }

    func testViewLayoutEngineDefaultAlignmentUsesPlacedChildGeometry() {
        withGraph {
            let graph = try! XCTUnwrap(_AGGraph.current)
            let state = DefaultAlignmentProbeState()
            let children = [
                ExplicitAlignmentProbeEngine(
                    size: CGSize(width: 10, height: 20),
                    horizontal: 2,
                    vertical: 3
                ),
                ExplicitAlignmentProbeEngine(
                    size: CGSize(width: 20, height: 10),
                    horizontal: 6,
                    vertical: 4
                ),
            ].map {
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer($0)
                    )
                )
            }
            let inputs = makeLayoutContext(
                children: children,
                layoutDirection: .leftToRight
            )
            var engine = ViewLayoutEngine(
                layout: DefaultAlignmentProbeLayout(
                    state: state,
                    size: CGSize(width: 100, height: 80),
                    origins: [
                        CGPoint(x: 10, y: 5),
                        CGPoint(x: 40, y: 25),
                    ]
                ),
                context: inputs.0,
                children: inputs.1
            )
            let size = ViewSize(CGSize(width: 100, height: 80))
            let horizontal = HorizontalAlignment(
                LayoutCacheAlignmentA.self
            ).key
            let vertical = VerticalAlignment(
                LayoutCacheAlignmentB.self
            ).key

            XCTAssertEqual(engine.explicitAlignment(horizontal, at: size), 29)
            XCTAssertEqual(engine.explicitAlignment(vertical, at: size), 18.5)
            XCTAssertEqual(state.placementCount, 1)
        }
    }

    func testViewLayoutEngineDefaultAlignmentUsesLogicalRTLOrigins() {
        withGraph {
            let graph = try! XCTUnwrap(_AGGraph.current)
            let state = DefaultAlignmentProbeState()
            let children = [
                ExplicitAlignmentProbeEngine(
                    size: CGSize(width: 10, height: 20),
                    horizontal: 2,
                    vertical: nil
                ),
                ExplicitAlignmentProbeEngine(
                    size: CGSize(width: 20, height: 10),
                    horizontal: 6,
                    vertical: nil
                ),
            ].map {
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer($0)
                    )
                )
            }
            let inputs = makeLayoutContext(
                children: children,
                layoutDirection: .rightToLeft
            )
            var engine = ViewLayoutEngine(
                layout: DefaultAlignmentProbeLayout(
                    state: state,
                    size: CGSize(width: 100, height: 80),
                    origins: [
                        CGPoint(x: 10, y: 5),
                        CGPoint(x: 40, y: 25),
                    ]
                ),
                context: inputs.0,
                children: inputs.1
            )
            let key = HorizontalAlignment(LayoutCacheAlignmentA.self).key

            XCTAssertEqual(
                engine.explicitAlignment(
                    key,
                    at: ViewSize(CGSize(width: 100, height: 80))
                ),
                29
            )
            XCTAssertEqual(state.placementCount, 1)
        }
    }

    func testStackPlacementCommitsCachedChildDimensionsWithoutRemeasuring() {
        withGraph {
            let firstEngine = CountingLayoutEngine()
            let secondEngine = CountingLayoutEngine()
            let graph = try! XCTUnwrap(_AGGraph.current)
            let firstComputer = graph.makeInput(
                value: LayoutComputer(firstEngine)
            )
            let secondComputer = graph.makeInput(
                value: LayoutComputer(secondEngine)
            )
            let proposal = _ProposedSize(width: 100, height: 20)
            let children = [
                LayoutProxyAttributes(layoutComputer: firstComputer),
                LayoutProxyAttributes(layoutComputer: secondComputer),
            ]
            let inputs = makeLayoutContext(
                children: children,
                layoutDirection: .leftToRight
            )
            var stack = ViewLayoutEngine(
                layout: HStackLayout(spacing: 0),
                context: inputs.0,
                children: inputs.1
            )

            let size = stack.sizeThatFits(proposal)
            XCTAssertFalse(firstEngine.proposals.isEmpty)
            XCTAssertFalse(secondEngine.proposals.isEmpty)

            let firstMeasurementCount = firstEngine.proposals.count
            let secondMeasurementCount = secondEngine.proposals.count

            let geometries = stack.childGeometries(
                at: ViewSize(size, proposal: proposal),
                origin: .zero
            )
            XCTAssertEqual(geometries.count, 2)
            XCTAssertEqual(firstEngine.proposals.count, firstMeasurementCount)
            XCTAssertEqual(secondEngine.proposals.count, secondMeasurementCount)
        }
    }

    func testStackReusesMajorAxisRangesWhileCrossAxisProposalIsStable() {
        withGraph {
            let firstEngine = CountingLayoutEngine()
            let secondEngine = CountingLayoutEngine()
            let graph = try! XCTUnwrap(_AGGraph.current)
            let children = [
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(firstEngine)
                    )
                ),
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(secondEngine)
                    )
                ),
            ]
            let inputs = makeLayoutContext(
                children: children,
                layoutDirection: .leftToRight
            )
            var stack = ViewLayoutEngine(
                layout: HStackLayout(spacing: 0),
                context: inputs.0,
                children: inputs.1
            )

            _ = stack.sizeThatFits(_ProposedSize(width: 100, height: 20))
            XCTAssertEqual(firstEngine.proposals.count, 3)
            XCTAssertEqual(secondEngine.proposals.count, 3)

            _ = stack.sizeThatFits(_ProposedSize(width: 120, height: 20))
            _ = stack.sizeThatFits(_ProposedSize(width: 140, height: 20))
            XCTAssertEqual(firstEngine.proposals.count, 5)
            XCTAssertEqual(secondEngine.proposals.count, 5)

            _ = stack.sizeThatFits(_ProposedSize(width: 140, height: 30))
            XCTAssertEqual(firstEngine.proposals.count, 8)
            XCTAssertEqual(secondEngine.proposals.count, 8)
        }
    }

    private func withGraph(_ body: () -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            body()
        }
    }
}
