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
}
