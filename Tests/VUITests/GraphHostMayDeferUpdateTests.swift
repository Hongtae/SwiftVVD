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

    func testViewGraphHostMayDeferUpdateAlsoRequiresScheduledDisplayLink() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        XCTAssertFalse(viewGraph.mayDeferUpdate)

        viewGraph.startDisplayLink(delay: 0.25)
        XCTAssertTrue(viewGraph.mayDeferUpdate)

        viewGraph.setNeedsUpdate(mayDeferUpdate: false, values: .size)
        XCTAssertFalse(viewGraph.mayDeferUpdate)

        viewGraph.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 63),
            mutation: MayDeferRecordingGraphMutation {}
        )
        viewGraph.flushTransactions()
        XCTAssertTrue(viewGraph.mayDeferUpdate)

        viewGraph.clearDisplayLink()
        XCTAssertFalse(viewGraph.mayDeferUpdate)
    }

    func testViewGraphHostMayDeferUpdateTreatsInfinityDisplayLinkUpdateAsUnscheduled() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        viewGraph.startDisplayLink(delay: .infinity)

        XCTAssertFalse(viewGraph.mayDeferUpdate)
    }

    func testDisplayLinkImmediateDelaySchedulesZeroTime() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        viewGraph.currentTimestamp = Time(seconds: 42)

        viewGraph.startDisplayLink(delay: 0.0005)

        XCTAssertEqual(viewGraph.scheduledDisplayLinkTime.seconds, 0)
        XCTAssertTrue(viewGraph.mayDeferUpdate)
    }

    func testUpdateTimerFloorsShortDelayAndKeepsEarlierScheduledTime() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        viewGraph.currentTimestamp = Time(seconds: 10)

        viewGraph.startUpdateTimer(delay: 0.03)

        XCTAssertTrue(viewGraph.hasScheduledUpdateTimer)
        XCTAssertEqual(viewGraph.scheduledUpdateTimerDelay, 0.1)
        XCTAssertEqual(viewGraph.scheduledUpdateTimerTime.seconds, 10.1, accuracy: 0.000001)
        XCTAssertFalse(viewGraph.isUpdateTimerGateOpen)

        viewGraph.startUpdateTimer(delay: 0.5)

        XCTAssertEqual(viewGraph.scheduledUpdateTimerTime.seconds, 10.1, accuracy: 0.000001)

        viewGraph.currentTimestamp = Time(seconds: 9)
        viewGraph.startUpdateTimer(delay: 0.2)

        XCTAssertEqual(viewGraph.scheduledUpdateTimerDelay, 0.2)
        XCTAssertEqual(viewGraph.scheduledUpdateTimerTime.seconds, 9.2, accuracy: 0.000001)
    }

    func testClearUpdateTimerResetsScheduledTimeAndGate() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        viewGraph.startUpdateTimer(delay: 0.2)
        viewGraph.clearUpdateTimer()

        XCTAssertFalse(viewGraph.hasScheduledUpdateTimer)
        XCTAssertNil(viewGraph.scheduledUpdateTimerDelay)
        XCTAssertEqual(viewGraph.scheduledUpdateTimerTime.seconds, Double.infinity)
        XCTAssertTrue(viewGraph.isUpdateTimerGateOpen)
    }

    func testWindowControllerRequestUpdateShortDelaySchedulesDisplayLink() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
        controller.viewGraph.currentTimestamp = Time(seconds: 5)
        controller.viewGraph.startUpdateTimer(delay: 0.5)

        controller.requestUpdate(after: 0.05)

        XCTAssertEqual(controller.viewGraph.scheduledDisplayLinkTime.seconds, 0.05, accuracy: 0.000001)
        XCTAssertTrue(controller.viewGraph.mayDeferUpdate)
        XCTAssertFalse(controller.viewGraph.hasScheduledUpdateTimer)
        XCTAssertTrue(controller.viewGraph.isUpdateTimerGateOpen)
    }

    func testWindowControllerRequestUpdateZeroDelayDoesNotScheduleDeferredTimers() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
        controller.viewGraph.currentTimestamp = Time(seconds: 7)

        controller.requestUpdate(after: 0)

        XCTAssertEqual(controller.viewGraph.scheduledDisplayLinkTime.seconds, Double.infinity)
        XCTAssertFalse(controller.viewGraph.mayDeferUpdate)
        XCTAssertFalse(controller.viewGraph.hasScheduledUpdateTimer)
        XCTAssertTrue(controller.viewGraph.isUpdateTimerGateOpen)
    }

    func testWindowControllerRequestUpdateLongDelaySchedulesUpdateTimer() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
        controller.viewGraph.currentTimestamp = Time(seconds: 12)

        controller.requestUpdate(after: 0.25)

        XCTAssertFalse(controller.viewGraph.mayDeferUpdate)
        XCTAssertTrue(controller.viewGraph.hasScheduledUpdateTimer)
        XCTAssertEqual(controller.viewGraph.scheduledUpdateTimerDelay, 0.25)
        XCTAssertEqual(controller.viewGraph.scheduledUpdateTimerTime.seconds, 12.25, accuracy: 0.000001)
        XCTAssertFalse(controller.viewGraph.isUpdateTimerGateOpen)
    }
}

private struct MayDeferRecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}
