import XCTest
@testable import VUI

final class GraphHostDataSeedTests: XCTestCase {
    func testGraphHostDataOwnsUpdateAndTransactionSeedAttributes() {
        let host = GraphHost()

        host.data.withCurrent {
            XCTAssertTrue(GraphHost.currentHost === host)
            XCTAssertTrue(_AGGraph.current === host.data.graph)
            XCTAssertEqual(host.data.updateSeed, 0)
            XCTAssertEqual(host.data.transactionSeed, 0)
            XCTAssertEqual(host.data.updateSeedAttribute.value, 0)
            XCTAssertEqual(host.data.transactionSeedAttribute.value, 0)

            host.data.updateSeed = 7
            host.data.transactionSeed = 11

            XCTAssertEqual(host.data.updateSeedAttribute.value, 7)
            XCTAssertEqual(host.data.transactionSeedAttribute.value, 11)
        }
    }

    func testGraphHostDataSeedsAreIndependentForSharedGraphHosts() {
        let graph = _AGGraph()
        let first = GraphHost(graph: graph)
        let second = GraphHost(graph: graph)

        first.data.withCurrent {
            XCTAssertTrue(GraphHost.currentHost === first)
            first.data.updateSeed = 1
            first.data.transactionSeed = 2
        }

        second.data.withCurrent {
            XCTAssertTrue(GraphHost.currentHost === second)
            XCTAssertEqual(second.data.updateSeed, 0)
            XCTAssertEqual(second.data.transactionSeed, 0)
            second.data.updateSeed = 3
            second.data.transactionSeed = 4
        }

        first.data.withCurrent {
            XCTAssertEqual(first.data.updateSeed, 1)
            XCTAssertEqual(first.data.transactionSeed, 2)
        }

        second.data.withCurrent {
            XCTAssertEqual(second.data.updateSeed, 3)
            XCTAssertEqual(second.data.transactionSeed, 4)
        }
    }
}
