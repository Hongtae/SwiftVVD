import Foundation
import XCTest
@testable import VUI

private final class CountingLayoutEngine: LayoutEngine {
    var proposals: [ProposedViewSize] = []

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposals.append(proposal)
        return CGSize(width: proposal.width ?? 7, height: proposal.height ?? 11)
    }
}

private final class LayoutCacheProbeState {
    var makeCacheCount = 0
    var updateCacheCount = 0
    var storage: LayoutCacheProbeStorage?
}

private final class LayoutCacheProbeStorage {
    var sizeCount = 0
    var placementCount = 0
    var proposals: [ProposedViewSize] = []
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
    }
}

final class LayoutEngineCacheTests: XCTestCase {
    func testViewLayoutEngineCachesThreeProposalsInInsertionOrder() {
        withGraph {
            let state = LayoutCacheProbeState()
            let layout = LayoutCacheProbe(
                state: state,
                reportedSize: CGSize(width: 7, height: 11)
            )
            let engine = ViewLayoutEngine(
                layout: layout,
                children: [],
                layoutDirection: .leftToRight
            )
            let a = ProposedViewSize(width: 10, height: nil)
            let b = ProposedViewSize(width: 20, height: nil)
            let c = ProposedViewSize(width: 30, height: nil)
            let d = ProposedViewSize(width: 40, height: nil)

            _ = engine.sizeThatFits(a)
            _ = engine.sizeThatFits(b)
            _ = engine.sizeThatFits(c)
            _ = engine.sizeThatFits(a)
            let storage = try! XCTUnwrap(state.storage)
            XCTAssertEqual(storage.proposals, [a, b, c])

            _ = engine.sizeThatFits(d)
            _ = engine.sizeThatFits(b)
            _ = engine.sizeThatFits(c)
            _ = engine.sizeThatFits(a)
            XCTAssertEqual(storage.proposals, [a, b, c, d, a])

            engine.update(
                layout: layout,
                layoutAttr: nil,
                children: [],
                layoutDirection: .leftToRight
            )
            _ = engine.sizeThatFits(a)
            XCTAssertEqual(storage.proposals, [a, b, c, d, a, a])
        }
    }

    func testViewLayoutEngineKeepsLayoutCacheAndInvalidatesDerivedCachesOnUpdate() {
        withGraph {
            let state = LayoutCacheProbeState()
            let initial = LayoutCacheProbe(
                state: state,
                reportedSize: CGSize(width: 10, height: 12)
            )
            let engine = ViewLayoutEngine(
                layout: initial,
                children: [],
                layoutDirection: .leftToRight
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

            engine.update(
                layout: LayoutCacheProbe(
                    state: state,
                    reportedSize: CGSize(width: 20, height: 24)
                ),
                layoutAttr: nil,
                children: [],
                layoutDirection: .leftToRight
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
            let proposal = ProposedViewSize(width: 100, height: 20)
            let stack = ViewLayoutEngine(
                layout: HStackLayout(spacing: 0),
                children: [
                    LayoutProxyAttributes(layoutComputer: firstComputer),
                    LayoutProxyAttributes(layoutComputer: secondComputer),
                ],
                layoutDirection: .leftToRight
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

    private func withGraph(_ body: () -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            _ = graph.makeInput(value: ())
            body()
        }
    }
}
