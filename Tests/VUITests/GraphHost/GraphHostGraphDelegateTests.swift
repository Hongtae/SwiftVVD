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

        XCTAssertEqual(recorder.events, ["begin", "update", "first", "second", "change"])
    }

    func testFlushTransactionsDoesNotNotifyDelegateWhenQueueIsEmpty() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)

        host.flushTransactions()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testDefaultBeginTransactionFlushesOnMainRunLoopObserver() {
        let recorder = DefaultBeginTransactionGraphDelegate()
        let host = DefaultBeginTransactionGraphHost(delegate: recorder)
        recorder.host = host
        host.instantiateIfNeeded()
        recorder.reset()

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 802),
            mutation: GraphDelegateRecordingMutation {
                recorder.record("mutation")
            }
        )

        XCTAssertTrue(recorder.events.isEmpty)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(recorder.events, ["update", "mutation", "change"])
    }

    func testDefaultBeginTransactionCalledOffMainUsesMainRunLoopObserver() {
        let recorder = DefaultBeginTransactionGraphDelegate()
        let host = DefaultBeginTransactionGraphHost(delegate: recorder)
        recorder.host = host
        host.instantiateIfNeeded()
        recorder.reset()
        let scheduled = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            recorder.beginTransaction()
            scheduled.signal()
        }

        XCTAssertEqual(scheduled.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(recorder.events.isEmpty)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(recorder.events, ["update"])
    }

    func testWindowControllerBeginTransactionKeepsFlushOnOwningRenderLane() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        controller.viewGraph.instantiateIfNeeded()
        controller.viewGraph.flushTransactions()
        let mutation = WindowControllerTransactionMutation()

        controller.viewGraph.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 803),
            mutation: GraphDelegateRecordingMutation {
                mutation.didApply = true
            }
        )

        XCTAssertTrue(controller.viewGraph.hasPendingTransactions)
        XCTAssertFalse(mutation.didApply)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertTrue(controller.viewGraph.hasPendingTransactions)
        XCTAssertFalse(mutation.didApply)

        controller.viewGraph.flushTransactions()

        XCTAssertFalse(controller.viewGraph.hasPendingTransactions)
        XCTAssertTrue(mutation.didApply)
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

        XCTAssertEqual(recorder.events, ["update", "mutation", "change"])
    }

    func testSetPhaseWritesHostPhaseAttributeWithoutDelegateChange() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        var phase = _GraphInputs.Phase()
        phase.resetSeed = 4
        phase.isBeingRemoved = true

        host.setPhase(phase)

        host.data.withCurrent {
            XCTAssertEqual(host.data._phase.value.value, phase.value)
        }
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testIncrementPhaseAdvancesResetSeedAndNotifiesDelegate() {
        let recorder = GraphDelegateEventRecorder()
        let host = DelegateGraphHost(recorder: recorder)
        var phase = _GraphInputs.Phase()
        phase.resetSeed = 3
        phase.isBeingRemoved = true
        host.setPhase(phase)

        host.incrementPhase()

        host.data.withCurrent {
            let next = host.data._phase.value
            XCTAssertEqual(next.resetSeed, 4)
            XCTAssertTrue(next.isBeingRemoved)
        }
        XCTAssertEqual(recorder.events, ["change"])
    }

    func testViewGraphRootInputsUseHostPhaseAttribute() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        var phase = _GraphInputs.Phase()
        phase.resetSeed = 9
        phase.isBeingRemoved = true

        XCTAssertEqual(viewGraph.phaseAttr?.identifier, viewGraph.data._phase.identifier)

        viewGraph.setPhase(phase)

        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.phaseAttr?.value.value, phase.value)
        }
    }

    func testViewGraphUpdateGraphPhaseMissingOldWritesNewParentPhase() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        var newParentPhase = _GraphInputs.Phase()
        newParentPhase.resetSeed = 5
        newParentPhase.isBeingRemoved = true

        viewGraph.updateGraphPhase(oldParentPhase: nil, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.value, newParentPhase.value)
        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.data._phase.value.value, newParentPhase.value)
        }
    }

    func testViewGraphUpdateGraphPhaseParentSeedChangeIncrementsHostPhase() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        let recorder = GraphDelegateEventRecorder()
        recorder.host = viewGraph
        viewGraph.graphDelegate = recorder
        var currentPhase = _GraphInputs.Phase()
        currentPhase.resetSeed = 10
        currentPhase.isBeingRemoved = true
        viewGraph.setPhase(currentPhase)
        var oldParentPhase = _GraphInputs.Phase()
        oldParentPhase.resetSeed = 2
        var newParentPhase = _GraphInputs.Phase()
        newParentPhase.resetSeed = 3

        viewGraph.updateGraphPhase(oldParentPhase: oldParentPhase, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.value, newParentPhase.value)
        viewGraph.data.withCurrent {
            let next = viewGraph.data._phase.value
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
        var currentPhase = _GraphInputs.Phase()
        currentPhase.resetSeed = 10
        viewGraph.setPhase(currentPhase)
        var oldParentPhase = _GraphInputs.Phase()
        oldParentPhase.resetSeed = 7
        var newParentPhase = _GraphInputs.Phase()
        newParentPhase.resetSeed = 7
        newParentPhase.isBeingRemoved = true

        viewGraph.updateGraphPhase(oldParentPhase: oldParentPhase, newParentPhase: newParentPhase)

        XCTAssertEqual(viewGraph.parentPhase?.value, newParentPhase.value)
        viewGraph.data.withCurrent {
            let next = viewGraph.data._phase.value
            XCTAssertEqual(next.resetSeed, 10)
            XCTAssertTrue(next.isBeingRemoved)
        }
        XCTAssertTrue(recorder.events.isEmpty)
    }

    // ASSERTIONS viewGraphHostEnvironmentWrapperOwnershipObserved
    func testWindowControllerUpdateEnvironmentConsumesWrapperPhaseWithoutEnteringParentGraph() {
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
        let child = WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(Optional<EmptyView>.self))
        )
        child.parentWindow = parent

        XCTAssertTrue(child.viewGraph.parentHost === parent.viewGraph)

        var childPhase = _GraphInputs.Phase()
        childPhase.resetSeed = 7
        childPhase.isBeingRemoved = true
        child.viewGraph.setPhase(childPhase)

        var oldParentPhase = _GraphInputs.Phase()
        oldParentPhase.resetSeed = 2
        child.viewGraph.parentPhase = oldParentPhase

        var newParentPhase = _GraphInputs.Phase()
        newParentPhase.resetSeed = 3
        parent.viewGraph.setPhase(newParentPhase)
        child.environmentWrapper.phase = ViewGraphHost.Phase(
            base: newParentPhase
        )

        let enteredParentGraph = DispatchSemaphore(value: 0)
        let releaseParentGraph = DispatchSemaphore(value: 0)
        let parentGraphExited = DispatchSemaphore(value: 0)
        let parentGraph = GraphDelegateUncheckedSendableValue(
            parent.viewGraph.data
        )
        DispatchQueue.global().async {
            parentGraph.value.withCurrent {
                enteredParentGraph.signal()
                releaseParentGraph.wait()
            }
            parentGraphExited.signal()
        }

        XCTAssertEqual(
            enteredParentGraph.wait(timeout: .now() + 2),
            .success
        )

        child.viewGraph.data.withCurrent {
            child.updateEnvironment()
        }

        releaseParentGraph.signal()
        XCTAssertEqual(
            parentGraphExited.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(child.viewGraph.parentPhase?.value, newParentPhase.value)
        child.viewGraph.data.withCurrent {
            let next = child.viewGraph.data._phase.value
            XCTAssertEqual(next.resetSeed, 8)
            XCTAssertTrue(next.isBeingRemoved)
        }
    }

    // ASSERTIONS viewGraphHostEnvironmentWrapperOwnershipObserved
    func testPresentationSideEffectCapturesPhaseAttributeWithoutReenteringHostData() throws {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PresentationPhaseAttributeCaptureProbe.self)
            )
        )
        let graph = controller.viewGraph.data.graph
        let updateSeed = controller.viewGraph.data._updateSeed
        let phase = try XCTUnwrap(controller.viewGraph.phaseAttr)
        let context = _AGGraphContext(graph: graph)
        var observedPhases: [UInt32] = []

        _ = context.withCurrent {
            graph.makeSideEffectRule {
                _ = updateSeed.value
                let viewPhase = ViewGraphHost.Phase(base: phase.value)
                controller.updateAlertPresentation(
                    [],
                    viewPhase: viewPhase
                )
                observedPhases.append(viewPhase.base.value)
            }
        }

        XCTAssertEqual(observedPhases, [0])

        controller.viewGraph.data.updateSeed &+= 1

        XCTAssertEqual(observedPhases, [0, 0])
    }
}

private enum PresentationPhaseAttributeCaptureProbe {}

private struct GraphDelegateUncheckedSendableValue<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class DelegateGraphHost: GraphHost {
    private let delegateRecorder: GraphDelegateEventRecorder

    init(recorder: GraphDelegateEventRecorder) {
        self.delegateRecorder = recorder
        super.init(data: Data())
        recorder.host = self
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateRecorder
    }
}

private final class DefaultBeginTransactionGraphHost: GraphHost {
    private let delegateStorage: any GraphDelegate

    init(delegate: any GraphDelegate) {
        self.delegateStorage = delegate
        super.init(data: Data())
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateStorage
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

private final class DefaultBeginTransactionGraphDelegate: GraphDelegate, @unchecked Sendable {
    weak var host: GraphHost?
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let host else {
            fatalError("DefaultBeginTransactionGraphDelegate used before attaching a host.")
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

private final class WindowControllerTransactionMutation {
    var didApply = false
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
