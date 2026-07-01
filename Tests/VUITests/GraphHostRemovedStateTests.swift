import XCTest
@testable import VUI

final class GraphHostRemovedStateTests: XCTestCase {
    func testRemovedStateTransitionsDispatchSubgraphRemovableCallbacksOnce() {
        let host = GraphHost()
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: host, recorder: recorder)

        host.removedState = .unattached
        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)

        host.removedState = .unattached
        XCTAssertEqual(recorder.events, ["update", "willRemove"])

        host.removedState = []
        XCTAssertEqual(recorder.events, ["update", "willRemove", "didReinsert"])
        XCTAssertFalse(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
    }

    func testHiddenForReuseSetsHiddenFlagAndDispatchesRemoval() {
        let host = RecordingRemovedStateGraphHost()
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: host, recorder: recorder)

        host.removedState = .hiddenForReuse

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertTrue(host.isHiddenForReuse)
        XCTAssertEqual(host.isHiddenForReuseDidChangeCount, 1)

        host.removedState = .unattached

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
        XCTAssertEqual(host.isHiddenForReuseDidChangeCount, 2)
    }

    func testChildHostInheritsParentHiddenForReuseRemoval() {
        let parent = GraphHost()
        let child = ChildRemovedStateGraphHost(parent: parent)
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: child, recorder: recorder)

        parent.removedState = .hiddenForReuse
        child.updateRemovedState()

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(child.isRemoved)
        XCTAssertTrue(child.isHiddenForReuse)

        parent.removedState = []
        child.updateRemovedState()

        XCTAssertEqual(recorder.events, ["update", "willRemove", "didReinsert"])
        XCTAssertFalse(child.isRemoved)
        XCTAssertFalse(child.isHiddenForReuse)
    }

    func testViewGraphHostUpdateRemovedStatePacksUnattachedAndHiddenForReuse() {
        let host = ViewGraphHost()

        host.updateRemovedState(isUnattached: true, isHiddenForReuse: false)
        XCTAssertEqual(host.removedState, .unattached)
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)

        host.updateRemovedState(isUnattached: true, isHiddenForReuse: true)
        XCTAssertEqual(host.removedState, [.unattached, .hiddenForReuse])
        XCTAssertTrue(host.isRemoved)
        XCTAssertTrue(host.isHiddenForReuse)

        host.updateRemovedState(isUnattached: false, isHiddenForReuse: false)
        XCTAssertEqual(host.removedState, [])
        XCTAssertFalse(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
    }

    func testViewGraphHiddenForReuseDispatchesFeatureBufferHook() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        let feature = RecordingViewGraphFeature()
        viewGraph.addFeature(feature)

        XCTAssertEqual(viewGraph.viewGraphFeatureCount, 1)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)

        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 1)
        XCTAssertTrue(feature.hiddenReuseChangeGraphs[0] === viewGraph)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)
        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 1)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: false)
        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 2)
        XCTAssertTrue(feature.hiddenReuseChangeGraphs[1] === viewGraph)
    }

    func testViewGraphFeatureDefaultsAreNoopAndAllowAsyncUpdate() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        let feature = DefaultOnlyViewGraphFeature()

        XCTAssertEqual(feature.allowsAsyncUpdate(graph: viewGraph), true)
        XCTAssertFalse(feature.needsUpdate(graph: viewGraph))

        feature.uninstantiate(graph: viewGraph)
        feature.outputsDidChange(graph: viewGraph)
        feature.update(graph: viewGraph)

        viewGraph.addFeature(feature)
        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)
        XCTAssertEqual(viewGraph.viewGraphFeatureCount, 1)
    }

    private func installRemovableRule(in host: GraphHost, recorder: RemovedStateRecorder) {
        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
                let attr = host.data.graph.makeStatefulRule(RemovableRecorderRule(recorder: recorder))
                _ = attr.value
            }
        }
    }
}

private final class RemovedStateRecorder {
    var events: [String] = []
}

private struct RemovableRecorderRule: StatefulRule, RemovableAttribute {
    typealias Value = Void

    var recorder: RemovedStateRecorder

    mutating func updateValue() {
        recorder.events.append("update")
        _AGGraph.setStatefulOutput(())
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("willRemove")
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("didReinsert")
        }
    }
}

private final class RecordingRemovedStateGraphHost: GraphHost {
    var isHiddenForReuseDidChangeCount = 0

    override func isHiddenForReuseDidChange() {
        isHiddenForReuseDidChangeCount += 1
    }
}

private final class ChildRemovedStateGraphHost: GraphHost {
    private weak var parent: GraphHost?

    init(parent: GraphHost) {
        self.parent = parent
        super.init(graph: parent.data.graph)
    }

    override var parentHost: GraphHost? {
        parent
    }
}

private final class RecordingViewGraphFeature: ViewGraphFeature {
    var hiddenReuseChangeGraphs: [ViewGraph] = []

    func isHiddenForReuseDidChange(graph: ViewGraph) {
        hiddenReuseChangeGraphs.append(graph)
    }
}

private struct DefaultOnlyViewGraphFeature: ViewGraphFeature {}
