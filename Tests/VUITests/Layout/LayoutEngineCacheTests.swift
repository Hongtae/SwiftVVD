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
    var proposals: [ProposedViewSize] = []
    var placementProposals: [ProposedViewSize] = []
    var placementBounds: [CGRect] = []
}

private final class PlacementDataBox: @unchecked Sendable {
    var value: PlacementData

    init(_ value: PlacementData) {
        self.value = value
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
    }
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
    let owner = graph.makeInput(value: ())
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
    func testClosureLayoutComputerPlacementCanReadItsOwnSize() {
        withGraph {
            var computer: LayoutComputer!
            var measuredSize: CGSize?
            computer = LayoutComputer(
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
            XCTAssertEqual(storage.placementCount, 1)

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
            XCTAssertEqual(storage.placementCount, 2)
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

    func testStackPlacementCommitsCachedChildDimensionsWithoutRemeasuring() {
        withGraph {
            let firstEngine = CountingLayoutEngine()
            let secondEngine = CountingLayoutEngine()
            let firstBox = LayoutEngineBox(engine: firstEngine)
            let secondBox = LayoutEngineBox(engine: secondEngine)
            let graph = try! XCTUnwrap(_AGGraph.current)
            let firstComputer = graph.makeInput(
                value: LayoutComputer(box: firstBox)
            )
            let secondComputer = graph.makeInput(
                value: LayoutComputer(box: secondBox)
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
                        value: LayoutComputer(box: LayoutEngineBox(engine: firstEngine))
                    )
                ),
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer(box: LayoutEngineBox(engine: secondEngine))
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
