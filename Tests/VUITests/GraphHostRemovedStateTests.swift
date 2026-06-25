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
        XCTAssertEqual(host.removedStateDidChangeCount, 1)

        host.removedState = .unattached

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
        XCTAssertEqual(host.removedStateDidChangeCount, 2)
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
        AttributeGraph.setStatefulOutput(())
    }

    static func willRemove(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("willRemove")
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("didReinsert")
        }
    }
}

private final class RecordingRemovedStateGraphHost: GraphHost {
    var removedStateDidChangeCount = 0

    override func removedStateDidChange() {
        removedStateDidChangeCount += 1
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
