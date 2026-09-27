import XCTest
@testable import VUI

final class GraphHostDataSubgraphTests: XCTestCase {
    func testGraphHostDataOwnsGlobalAndRootSubgraphs() {
        let host = GraphHost()

        XCTAssertTrue(host.data.globalSubgraph !== host.data.rootSubgraph)
        XCTAssertTrue(host.data.globalSubgraph.graph === host.data.graph)
        XCTAssertTrue(host.data.rootSubgraph.graph === host.data.graph)
        XCTAssertTrue(host.data.rootSubgraph.parent === host.data.globalSubgraph)
        XCTAssertTrue(host.data.globalSubgraph.children.contains { $0 === host.data.rootSubgraph })
    }

    func testIndependentGraphHostsKeepDistinctSubgraphOwnership() {
        let first = GraphHost()
        let second = GraphHost()

        XCTAssertFalse(first.data.graph === second.data.graph)
        XCTAssertTrue(first.data.globalSubgraph !== second.data.globalSubgraph)
        XCTAssertTrue(first.data.rootSubgraph !== second.data.rootSubgraph)
        XCTAssertTrue(first.data.rootSubgraph.parent === first.data.globalSubgraph)
        XCTAssertTrue(second.data.rootSubgraph.parent === second.data.globalSubgraph)
    }

    func testRootSubgraphRegistersNodesCreatedWhileCurrent() {
        let host = GraphHost()
        var identifier: AGAttribute!

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                identifier = host.data.graph.makeInput(value: 42).identifier
            }
        }

        XCTAssertTrue(host.data.rootSubgraph.nodes.contains(identifier))
        XCTAssertFalse(host.data.globalSubgraph.nodes.contains(identifier))
    }

    // ASSERTIONS graphHostInternGlobalSubgraphObserved
    func testInternCreatesConstantsInGlobalSubgraphAndReusesThemAfterRootRemoval() {
        let host = GraphHost()
        var first: Attribute<Bool>!

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                first = host.intern(true, for: Bool.self, id: .trueValue)
            }
        }

        XCTAssertTrue(host.data.globalSubgraph.nodes.contains(first.identifier))
        XCTAssertFalse(host.data.rootSubgraph.nodes.contains(first.identifier))

        host.instantiate()
        host.uninstantiate(immediately: true)

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let second: Attribute<Bool> = host.intern(
                    true,
                    for: Bool.self,
                    id: .trueValue
                )
                XCTAssertEqual(second.identifier, first.identifier)
                XCTAssertTrue(second.value)
            }
        }
    }

    func testSubgraphUpdateSelectsDirtyNodesByAttributeFlags() {
        let host = GraphHost()
        var source: Attribute<Int>!
        var unflagged: Attribute<Int>!
        var transactional: Attribute<Int>!
        var unflaggedEvaluations = 0
        var transactionalEvaluations = 0

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                source = host.data.graph.makeInput(value: 1)
                unflagged = host.data.graph.makeRule {
                    unflaggedEvaluations += 1
                    return source.value
                }
                transactional = host.data.graph.makeRule {
                    transactionalEvaluations += 1
                    return source.value
                }
                transactional.setFlags(.transactional, mask: .transactional)
            }

            XCTAssertEqual(unflagged.value, 1)
            XCTAssertEqual(transactional.value, 1)
            source.setValue(2)

            host.data.rootSubgraph.update(flags: AGAttributeFlags.transactional.rawValue)
            XCTAssertEqual(unflaggedEvaluations, 1)
            XCTAssertEqual(transactionalEvaluations, 2)
            XCTAssertEqual(transactional.value, 2)

            host.data.rootSubgraph.update(flags: 0)
            XCTAssertEqual(unflaggedEvaluations, 1)

            XCTAssertEqual(unflagged.value, 2)
            XCTAssertEqual(unflaggedEvaluations, 2)
        }
    }

    func testInvalidationReleasesNodesCreatedOutsideOwnershipSubgraphs() {
        weak var graphReference: _AGGraph?
        var host: GraphHost? = GraphHost()
        graphReference = host?.data.graph

        host?.data.withCurrent {
            let graph = host!.data.graph
            let retainedGraphRule: Attribute<Int> = graph.makeRule(
                rule: { () -> Int in graph.slots.count }
            )
            XCTAssertGreaterThan(retainedGraphRule.value, 0)
        }

        host?.invalidate()
        host = nil

        XCTAssertNil(graphReference)
    }

    func testTerminalInvalidationAllowsDestroyHookToInvalidateOwnedSubgraph() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = TerminalSubgraphDestroyRecorder()

        ref.withCurrent {
            let child = AGSubgraph()
            AGSubgraph.withCurrent(child) {
                _ = graph.makeInput(value: 42)
            }
            _ = graph.makeStatefulRule(
                TerminalSubgraphInvalidatingRule(
                    subgraph: child,
                    recorder: recorder
                )
            )

            graph.invalidateAllNodes()
        }

        XCTAssertEqual(recorder.destroyCount, 1)
        XCTAssertFalse(recorder.subgraphWasValidAfterInvalidation)
        XCTAssertTrue(graph.slots.isEmpty)
    }
}

private final class TerminalSubgraphDestroyRecorder {
    var destroyCount = 0
    var subgraphWasValidAfterInvalidation = true
}

private struct TerminalSubgraphInvalidatingRule:
    StatefulRule, ObservedAttribute
{
    typealias Value = Int

    var subgraph: AGSubgraphRef
    var recorder: TerminalSubgraphDestroyRecorder

    mutating func updateValue() {
        value = 1
    }

    mutating func destroy() {
        recorder.destroyCount += 1
        subgraph.invalidate()
        recorder.subgraphWasValidAfterInvalidation = subgraph.isValid
    }
}
