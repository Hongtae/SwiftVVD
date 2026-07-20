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
}
