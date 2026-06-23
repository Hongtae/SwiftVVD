import XCTest
@testable import VUI

final class GraphHostGraphDelegateTests: XCTestCase {
    override func tearDown() {
        GraphHost.flushGlobalTransactions()
        super.tearDown()
    }

    func testAsyncTransactionBeginsDelegateOnlyWhenQueueBecomesNonempty() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        let id = Transaction.ID(value: 800)
        let transaction = Transaction()

        host.asyncTransaction(
            transaction,
            id: id,
            mutation: GraphDelegateRecordingMutation {
                recorder.record("first")
            }
        )
        host.asyncTransaction(
            transaction,
            id: id,
            mutation: GraphDelegateRecordingMutation {
                recorder.record("second")
            }
        )

        XCTAssertEqual(recorder.events, ["begin"])

        host.flushTransactions()

        XCTAssertEqual(recorder.events, ["begin", "first", "second", "change"])
    }

    func testFlushTransactionsDoesNotNotifyDelegateWhenQueueIsEmpty() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)

        host.flushTransactions()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testGlobalHostFlushNotifiesProviderHostDelegateAfterMutation() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        let provider = GraphDelegateTransactionHostProvider(host: host)

        GraphHost.globalTransaction(
            Transaction(),
            id: Transaction.ID(value: 801),
            mutation: GraphDelegateRecordingMutation {
                recorder.record("mutation")
            },
            hostProvider: provider
        )

        XCTAssertTrue(recorder.events.isEmpty)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(recorder.events, ["mutation", "change"])
    }
}

private final class DelegateGraphHost: GraphHost {
    private let delegateRecorder: GraphDelegateEventRecorder

    init(recorder: GraphDelegateEventRecorder) {
        self.delegateRecorder = recorder
        super.init()
        recorder.host = self
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateRecorder
    }
}

private final class GraphDelegateEventRecorder: GraphDelegate {
    weak var host: GraphHost?
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func beginTransaction() {
        record("begin")
    }

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let host else {
            fatalError("GraphDelegateEventRecorder used before attaching a host.")
        }
        record("update")
        return body(host)
    }

    func graphDidChange() {
        record("change")
    }
}

private struct GraphDelegateRecordingMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}

private final class GraphDelegateTransactionHostProvider: TransactionHostProvider {
    weak var host: GraphHost?

    init(host: GraphHost?) {
        self.host = host
    }

    var mutationHost: GraphHost? {
        host
    }
}
