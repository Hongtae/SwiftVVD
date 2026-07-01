import XCTest
@testable import VUI

final class ViewListSubgraphLifecycleTests: XCTestCase {
    func testFinalReleaseDispatchesWillRemoveBeforeInvalidatingSubgraph() throws {
        let host = GraphHost()
        let recorder = ViewListSubgraphRecorder()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            AGSubgraph.$current.withValue(childSubgraph) {
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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
                childSubgraph = AGSubgraph()
            }
            AGSubgraph.$current.withValue(childSubgraph) {
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

    func testSubgraphStorageRetainSkipsInvalidSubgraphs() throws {
        let host = GraphHost()
        let storage = _ViewList_SublistSubgraphStorage()
        var childSubgraph: AGSubgraph!
        var retainedSubgraph: _ViewList_Subgraph!

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
        AttributeGraph.setStatefulOutput(())
    }

    static func willRemove(attribute: AGAttribute) {
        AttributeGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("willRemove")
        }
    }
}
