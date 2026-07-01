import XCTest
@testable import VUI

final class GraphHostEmptyTransactionTests: XCTestCase {
    func testEmptyTransactionQueuesNoOpDeferredTransaction() {
        let host = GraphHost()

        host.emptyTransaction(Transaction())

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertTrue(host.mayDeferUpdate)
        XCTAssertEqual(host.data.transactionSeed, 0)

        host.flushTransactions()

        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertFalse(host.isUpdating)
        XCTAssertTrue(host.mayDeferUpdate)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testEmptyTransactionsWithCurrentIDAndEqualTransactionMerge() {
        let host = GraphHost()
        let transaction = Transaction()

        let firstTrace = host.emptyTransaction(transaction)
        let secondTrace = host.emptyTransaction(transaction)

        XCTAssertEqual(firstTrace, secondTrace)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testEmptyTransactionDoesNotFinalizeCompletionListeners() {
        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        let host = GraphHost()
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("completion")
        }

        host.emptyTransaction(transaction)
        host.flushTransactions()

        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)

        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }
        XCTAssertEqual(events, ["completion"])

        withExtendedLifetime(transaction) {}
    }
}
