import XCTest
@testable import VUI

final class GraphHostGraphInvalidationTests: XCTestCase {
    func testNilSourceNotifiesGraphDelegateDirectly() {
        let recorder = GraphInvalidationDelegateRecorder()
        let host = GraphInvalidationRecordingHost(delegate: recorder)

        host.graphInvalidation(from: nil)

        XCTAssertEqual(recorder.changeCount, 1)
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testEmptySourceTransactionOnlyNarrowsMayDeferUpdate() {
        // ASSERTIONS graphHostGraphInvalidationTransactionForwardingObserved
        let source = GraphHost()
        let target = GraphHost()
        source.setNeedsUpdate(mayDeferUpdate: false, values: .size)

        source.data.withCurrent {
            target.graphInvalidation(from: source.data._environment.identifier)
        }

        XCTAssertFalse(target.mayDeferUpdate)
        XCTAssertFalse(target.hasPendingTransactions)
        XCTAssertEqual(target.data.transactionSeed, 0)
    }

    func testNonemptySourceTransactionQueuesItOnTargetHost() {
        // ASSERTIONS graphHostGraphInvalidationTransactionForwardingObserved
        let source = GraphHost()
        let target = GraphInvalidationRecordingHost()
        source.data.transaction = Transaction(
            animation: .linear(duration: 0.25)
        )

        source.data.withCurrent {
            target.graphInvalidation(from: source.data._transaction.identifier)
        }

        XCTAssertTrue(target.hasPendingTransactions)
        XCTAssertEqual(target.data.transactionSeed, 0)

        target.flushTransactions()

        XCTAssertFalse(target.hasPendingTransactions)
        XCTAssertEqual(target.data.transactionSeed, 1)
        XCTAssertEqual(target.observedNonemptyTransactions, [true])
    }
}

private final class GraphInvalidationRecordingHost: GraphHost {
    private let delegateStorage: (any GraphDelegate)?
    private(set) var observedNonemptyTransactions: [Bool] = []

    init(delegate: (any GraphDelegate)? = nil) {
        delegateStorage = delegate
        super.init(data: Data())
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateStorage
    }

    override func startTransactionUpdate(id: UInt32? = nil) {
        // startTransactionUpdate runs inside this host's graph context, after
        // the forwarded transaction has been installed on _transaction.
        observedNonemptyTransactions.append(!data._transaction.value.isEmpty)
        super.startTransactionUpdate(id: id)
    }
}

private final class GraphInvalidationDelegateRecorder: GraphDelegate {
    private(set) var changeCount = 0

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        fatalError("This recorder only covers the direct nil-source callback.")
    }

    func graphDidChange() {
        changeCount += 1
    }
}
