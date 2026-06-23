import XCTest
@testable import VUI

final class GraphHostMayDeferUpdateTests: XCTestCase {
    func testMayDeferUpdateStartsTrue() {
        let host = GraphHost()

        XCTAssertTrue(host.mayDeferUpdate)
    }

    func testSetNeedsUpdateNarrowsUntilTransactionFlush() {
        let host = GraphHost()

        host.setNeedsUpdate(mayDeferUpdate: false, values: .size)
        XCTAssertFalse(host.mayDeferUpdate)

        host.setNeedsUpdate(mayDeferUpdate: true, values: .environment)
        XCTAssertFalse(host.mayDeferUpdate)

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 60),
            mutation: MayDeferRecordingGraphMutation {}
        )
        host.flushTransactions()

        XCTAssertTrue(host.mayDeferUpdate)
    }

    func testDeferredAsyncTransactionNarrowsUntilFlush() {
        let host = GraphHost()

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 61),
            mutation: MayDeferRecordingGraphMutation {},
            style: .deferred,
            mayDeferUpdate: false
        )

        XCTAssertFalse(host.mayDeferUpdate)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertTrue(host.mayDeferUpdate)
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testImmediateAsyncTransactionKeepsNarrowedLatchUntilQueuedMutationFlushes() {
        let host = GraphHost()
        var didApply = false

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 62),
            mutation: MayDeferRecordingGraphMutation {
                didApply = true
            },
            style: .immediate,
            mayDeferUpdate: false
        )

        XCTAssertFalse(didApply)
        XCTAssertFalse(host.mayDeferUpdate)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertTrue(didApply)
        XCTAssertTrue(host.mayDeferUpdate)
        XCTAssertFalse(host.hasPendingTransactions)
    }
}

private struct MayDeferRecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}
