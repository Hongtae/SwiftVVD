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

    func testSetPhaseWritesHostPhaseAttributeWithoutDelegateChange() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        var phase = Phase()
        phase.resetSeed = 4
        phase.isBeingRemoved = true

        host.setPhase(phase)

        host.data.withCurrent {
            XCTAssertEqual(host.data.phaseAttribute.value.rawValue, phase.rawValue)
        }
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testIncrementPhaseAdvancesResetSeedAndNotifiesDelegate() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        var phase = Phase()
        phase.resetSeed = 3
        phase.isBeingRemoved = true
        host.setPhase(phase)

        host.incrementPhase()

        host.data.withCurrent {
            let next = host.data.phaseAttribute.value
            XCTAssertEqual(next.resetSeed, 4)
            XCTAssertTrue(next.isBeingRemoved)
        }
        XCTAssertEqual(recorder.events, ["change"])
    }

    func testViewGraphRootInputsUseHostPhaseAttribute() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        var phase = Phase()
        phase.resetSeed = 9
        phase.isBeingRemoved = true

        XCTAssertEqual(viewGraph.phaseAttr?.identifier, viewGraph.data.phaseAttribute.identifier)

        viewGraph.setPhase(phase)

        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.phaseAttr?.value.rawValue, phase.rawValue)
        }
    }

    func testViewGraphUpdateGraphPhaseMissingOldWritesNewParentPhase() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        var newParentPhase = Phase()
        newParentPhase.resetSeed = 5
        newParentPhase.isBeingRemoved = true

        viewGraph.updateGraphPhase(oldParentPhase: nil, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.rawValue, newParentPhase.rawValue)
        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.data.phaseAttribute.value.rawValue, newParentPhase.rawValue)
        }
    }

    func testViewGraphUpdateGraphPhaseParentSeedChangeIncrementsHostPhase() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        let recorder = GraphDelegateEventRecorder()
        recorder.host = viewGraph
        viewGraph.graphDelegate = recorder
        var currentPhase = Phase()
        currentPhase.resetSeed = 10
        currentPhase.isBeingRemoved = true
        viewGraph.setPhase(currentPhase)
        var oldParentPhase = Phase()
        oldParentPhase.resetSeed = 2
        var newParentPhase = Phase()
        newParentPhase.resetSeed = 3

        viewGraph.updateGraphPhase(oldParentPhase: oldParentPhase, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.rawValue, newParentPhase.rawValue)
        viewGraph.data.withCurrent {
            let next = viewGraph.data.phaseAttribute.value
            XCTAssertEqual(next.resetSeed, 11)
            XCTAssertTrue(next.isBeingRemoved)
        }
        XCTAssertEqual(recorder.events, ["change"])
    }

    func testViewGraphUpdateGraphPhaseRemovalBitDeltaMirrorsWithoutSeedIncrement() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        let recorder = GraphDelegateEventRecorder()
        recorder.host = viewGraph
        viewGraph.graphDelegate = recorder
        var currentPhase = Phase()
        currentPhase.resetSeed = 10
        viewGraph.setPhase(currentPhase)
        var oldParentPhase = Phase()
        oldParentPhase.resetSeed = 7
        var newParentPhase = Phase()
        newParentPhase.resetSeed = 7
        newParentPhase.isBeingRemoved = true

        viewGraph.updateGraphPhase(oldParentPhase: oldParentPhase, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.rawValue, newParentPhase.rawValue)
        viewGraph.data.withCurrent {
            let next = viewGraph.data.phaseAttribute.value
            XCTAssertEqual(next.resetSeed, 10)
            XCTAssertTrue(next.isBeingRemoved)
        }
        XCTAssertTrue(recorder.events.isEmpty)
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
