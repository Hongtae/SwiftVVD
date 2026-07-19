import XCTest
@testable import VUI

final class ViewListSubgraphLifecycleTests: XCTestCase {
    func testSubgraphHolderCanBeCreatedWithoutGraphHostContext() {
        let graph = _AGGraph()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        _AGGraph.withCurrent(graph) {
            childSubgraph = AGSubgraph()
            retainedSubgraph = _ViewList_Subgraph(subgraph: childSubgraph)
            retainedSubgraph.release()
        }

        XCTAssertEqual(retainedSubgraph.refcount, 0)
        XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
    }

    func testFinalReleaseDispatchesWillRemoveBeforeInvalidatingSubgraph() throws {
        let host = GraphHost()
        let recorder = ViewListSubgraphRecorder()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            AGSubgraph.withCurrent(childSubgraph) {
                let attr = host.data.graph.makeStatefulRule(
                    ViewListSubgraphRecorderRule(recorder: recorder)
                )
                _ = attr.value
            }
            retainedSubgraph = _ViewList_Subgraph(subgraph: childSubgraph)

            XCTAssertTrue(AGSubgraphIsValid(childSubgraph))
            XCTAssertTrue(host.data.rootSubgraph.children.contains { $0 === childSubgraph })

            retainedSubgraph.release()
        }

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertEqual(retainedSubgraph.refcount, 0)
        XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
        XCTAssertNil(childSubgraph.parent)
    }

    func testRetainedReleaseTokenWaitsForFinalSubgraphOwner() throws {
        let host = GraphHost()
        let recorder = ViewListSubgraphRecorder()
        let storage = _ViewList_SublistSubgraphStorage()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            AGSubgraph.withCurrent(childSubgraph) {
                let attr = host.data.graph.makeStatefulRule(
                    ViewListSubgraphRecorderRule(recorder: recorder)
                )
                _ = attr.value
            }
            retainedSubgraph = _ViewList_Subgraph(subgraph: childSubgraph)
            storage.subgraphs.append(retainedSubgraph)

            do {
                let releaseToken = storage.retain()
                XCTAssertNotNil(releaseToken)
                XCTAssertEqual(retainedSubgraph.refcount, 2)
                _ = releaseToken
            }
            XCTAssertEqual(retainedSubgraph.refcount, 1)
            XCTAssertTrue(AGSubgraphIsValid(childSubgraph))
            XCTAssertEqual(recorder.events, ["update"])

            retainedSubgraph.release()
        }

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
    }

    func testRetainedReleaseTokenCanFinalizeOutsideGraphContext() throws {
        let host = GraphHost()
        let recorder = ViewListSubgraphRecorder()
        let storage = _ViewList_SublistSubgraphStorage()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!
        var releaseToken: _ViewList_SubgraphRelease?

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            AGSubgraph.withCurrent(childSubgraph) {
                let attr = host.data.graph.makeStatefulRule(
                    ViewListSubgraphRecorderRule(recorder: recorder)
                )
                _ = attr.value
            }
            retainedSubgraph = _ViewList_Subgraph(subgraph: childSubgraph)
            storage.subgraphs.append(retainedSubgraph)
            releaseToken = storage.retain()
            XCTAssertNotNil(releaseToken)
            XCTAssertEqual(retainedSubgraph.refcount, 2)

            retainedSubgraph.release()
            XCTAssertEqual(retainedSubgraph.refcount, 1)
            XCTAssertTrue(AGSubgraphIsValid(childSubgraph))
        }

        releaseToken = nil

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertEqual(retainedSubgraph.refcount, 0)
        XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
        XCTAssertNil(childSubgraph.parent)
    }

    func testSubgraphStorageRetainSkipsInvalidSubgraphs() throws {
        let host = GraphHost()
        let storage = _ViewList_SublistSubgraphStorage()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            retainedSubgraph = _ViewList_Subgraph(subgraph: childSubgraph)
            storage.subgraphs.append(retainedSubgraph)

            childSubgraph.invalidate()
            childSubgraph.removeFromParent()

            XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
            XCTAssertNil(storage.retain())
            XCTAssertEqual(retainedSubgraph.refcount, 1)
        }
    }
}

private final class ViewListSubgraphRecorder {
    var events: [String] = []
}

private struct ViewListSubgraphRecorderRule: StatefulRule, RemovableAttribute {
    typealias Value = Void

    var recorder: ViewListSubgraphRecorder

    mutating func updateValue() {
        recorder.events.append("update")
        _AGGraph.setStatefulOutput(())
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("willRemove")
        }
    }
}
