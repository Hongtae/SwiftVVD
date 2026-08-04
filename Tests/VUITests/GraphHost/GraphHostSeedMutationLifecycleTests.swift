import XCTest
@testable import VUI

final class GraphHostSeedMutationLifecycleTests: XCTestCase {
    func testRunTransactionIncrementsTransactionSeedAndRestoresUpdatingFlag() {
        let host = GraphHost()
        var value = 0

        host.runTransaction(nil, do: {
            XCTAssertTrue(host.isUpdating)
            XCTAssertEqual(host.data.transactionSeed, 1)
            XCTAssertEqual(host.data.updateSeed, 0)
            value = 42
        }, id: nil)

        XCTAssertEqual(value, 42)
        XCTAssertFalse(host.isUpdating)
        host.data.withCurrent {
            XCTAssertEqual(host.data.transactionSeed, 1)
            XCTAssertEqual(host.data.updateSeed, 0)
        }
    }

    func testRunTransactionDoesNotInstallPassedTransactionAsCurrent() {
        let host = GraphHost()
        var transaction = Transaction()
        transaction.isContinuous = true
        var observedCurrentIsContinuous: Bool?

        host.runTransaction(transaction, do: {
            observedCurrentIsContinuous = Transaction.current.isContinuous
            XCTAssertTrue(host.isUpdating)
        }, id: 11)

        XCTAssertEqual(observedCurrentIsContinuous, false)
        XCTAssertFalse(Transaction.current.isContinuous)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testFinishTransactionUpdateCallsPostUpdateBeforeClearingUpdatingFlag() {
        let host = GraphHost()
        var postUpdateNeedsFollowUp: [Bool] = []
        var wasUpdatingDuringPostUpdate = false

        host.startTransactionUpdate()
        host.finishTransactionUpdate(in: host.data.rootSubgraph, postUpdate: { needsFollowUp in
            wasUpdatingDuringPostUpdate = host.isUpdating
            postUpdateNeedsFollowUp.append(needsFollowUp)
        }, id: nil)

        XCTAssertEqual(postUpdateNeedsFollowUp, [false])
        XCTAssertTrue(wasUpdatingDuringPostUpdate)
        XCTAssertFalse(host.isUpdating)
        host.data.withCurrent {
            XCTAssertEqual(host.data.transactionSeed, 1)
        }
    }

    func testFinishTransactionUpdateRunsRootSubgraphUpdateBeforePostUpdate() {
        let host = GraphHost()
        var source: Attribute<Int>!
        var derived: Attribute<Int>!
        var observedDuringPostUpdate: Int?

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                source = host.data.graph.makeInput(value: 1)
                derived = host.data.graph.makeRule {
                    source.value * 2
                }
            }
            XCTAssertEqual(derived.value, 2)
        }

        host.startTransactionUpdate()
        host.continueTransaction(CustomGraphMutation {
            source.setValue(3)
        })
        host.finishTransactionUpdate(in: host.data.rootSubgraph, postUpdate: { _ in
            observedDuringPostUpdate = derived.value
        }, id: nil)

        XCTAssertEqual(observedDuringPostUpdate, 6)
        XCTAssertFalse(host.isUpdating)
    }

    func testFinishTransactionUpdateRepeatsWhenDrainEnqueuesMorePendingWork() {
        let host = GraphHost()
        let recorder = FinishTransactionUpdateRecorder()
        var postUpdateNeedsFollowUp: [Bool] = []
        var wasUpdatingDuringPostUpdate: [Bool] = []
        var needsTransactionDuringPostUpdate: [Bool] = []

        host.startTransactionUpdate()
        host.continueTransaction(
            FinishTransactionUpdateMutation(host: host, recorder: recorder, name: "first", nextName: "second")
        )
        host.finishTransactionUpdate(in: host.data.rootSubgraph, postUpdate: { needsFollowUp in
            wasUpdatingDuringPostUpdate.append(host.isUpdating)
            needsTransactionDuringPostUpdate.append(host.needsTransaction)
            postUpdateNeedsFollowUp.append(needsFollowUp)
            recorder.events.append("post:\(needsFollowUp)")
        }, id: nil)

        XCTAssertEqual(recorder.events, ["first", "post:true", "second", "post:false"])
        XCTAssertEqual(postUpdateNeedsFollowUp, [true, false])
        XCTAssertEqual(wasUpdatingDuringPostUpdate, [true, true])
        XCTAssertEqual(needsTransactionDuringPostUpdate, [true, false])
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.isUpdating)
    }

    func testFinishTransactionUpdateStopsAfterEightFollowUpPasses() {
        let host = GraphHost()
        let recorder = FinishTransactionUpdateRecorder()
        var postUpdateNeedsFollowUp: [Bool] = []

        host.startTransactionUpdate()
        host.continueTransaction(RequeuingFinishTransactionUpdateMutation(host: host, recorder: recorder))
        host.finishTransactionUpdate(in: host.data.rootSubgraph, postUpdate: { needsFollowUp in
            postUpdateNeedsFollowUp.append(needsFollowUp)
        }, id: nil)

        XCTAssertEqual(recorder.applyCount, 8)
        XCTAssertEqual(postUpdateNeedsFollowUp, Array(repeating: true, count: 8))
        XCTAssertTrue(host.needsTransaction)
        XCTAssertTrue(host.needsTransaction)
        XCTAssertFalse(host.isUpdating)
    }

    func testBeginNextUpdateIncrementsUpdateSeedEachCallAndResetsOnlyForTimeChange() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        viewGraph.nextUpdate.views.interval(0.25, reason: 7)
        viewGraph.beginNextUpdate(at: Time(seconds: 0))

        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.data.updateSeed, 1)
            XCTAssertEqual(viewGraph.data.transactionSeed, 0)
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.interval, 0.25)
        XCTAssertEqual(viewGraph.nextUpdate.views.reasons, [7])

        viewGraph.beginNextUpdate(at: Time(seconds: 1))

        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.data.updateSeed, 2)
            XCTAssertEqual(viewGraph.data.transactionSeed, 0)
        }
        XCTAssertTrue(viewGraph.nextUpdate.views.interval.isInfinite)
        XCTAssertTrue(viewGraph.nextUpdate.views.reasons.isEmpty)
    }

    func testUpdateOutputsAdvancesBothUpdateAndTransactionSeeds() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        viewGraph.updateOutputs(at: Time(seconds: 0))

        viewGraph.data.withCurrent {
            XCTAssertEqual(viewGraph.data.updateSeed, 1)
            XCTAssertEqual(viewGraph.data.transactionSeed, 1)
        }
        XCTAssertFalse(viewGraph.isUpdating)
    }
}

private final class FinishTransactionUpdateRecorder {
    var events: [String] = []
    var applyCount = 0
}

private struct FinishTransactionUpdateMutation: GraphMutation {
    var host: GraphHost
    var recorder: FinishTransactionUpdateRecorder
    var name: String
    var nextName: String?

    func apply() {
        recorder.events.append(name)
        if let nextName {
            host.continueTransaction(
                FinishTransactionUpdateMutation(
                    host: host,
                    recorder: recorder,
                    name: nextName,
                    nextName: nil
                )
            )
        }
    }
}

private struct RequeuingFinishTransactionUpdateMutation: GraphMutation {
    var host: GraphHost
    var recorder: FinishTransactionUpdateRecorder

    func apply() {
        recorder.applyCount += 1
        host.continueTransaction(Self(host: host, recorder: recorder))
    }
}
