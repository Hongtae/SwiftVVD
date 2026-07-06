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

    func testSharedGraphHostsKeepDistinctSubgraphOwnership() {
        let graph = _AGGraph()
        let first = GraphHost(graph: graph)
        let second = GraphHost(graph: graph)

        XCTAssertTrue(first.data.graph === second.data.graph)
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
}
