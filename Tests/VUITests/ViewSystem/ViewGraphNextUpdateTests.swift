import XCTest
@testable import VUI

final class ViewGraphNextUpdateTests: XCTestCase {
    func testNextUpdateIntervalCombinesViewAndGestureLanes() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        XCTAssertEqual(viewGraph.nextUpdateInterval, 0)

        viewGraph.nextUpdate.gestures.interval(0.2, reason: 11)
        XCTAssertEqual(viewGraph.nextUpdateInterval, 0.2)
        XCTAssertEqual(viewGraph.nextUpdateReasons, [11])
        XCTAssertTrue(viewGraph.hasScheduledViewUpdate)

        viewGraph.nextUpdate.views.interval(0.25, reason: 12)
        XCTAssertEqual(viewGraph.nextUpdateInterval, 0.2)
        XCTAssertEqual(viewGraph.nextUpdateReasons, [11, 12])
    }

    func testZeroIntervalSuppressesLaterSlowIntervals() {
        var nextUpdate = ViewGraph.NextUpdate()

        nextUpdate.interval(0, reason: 10)
        XCTAssertTrue(nextUpdate.interval.isInfinite)
        XCTAssertEqual(nextUpdate.reasons, [10])

        nextUpdate.interval(0.25, reason: 11)
        XCTAssertTrue(nextUpdate.interval.isInfinite)
        XCTAssertEqual(nextUpdate.reasons, [10, 11])

        nextUpdate.interval(1.0 / 120.0, reason: 12)
        XCTAssertEqual(nextUpdate.interval, 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(nextUpdate.reasons, [10, 11, 12])
    }

    func testMaxVelocityMapsThresholdsToHighFrameRateIntervals() {
        var nextUpdate = ViewGraph.NextUpdate()

        nextUpdate.maxVelocity(159.99)
        XCTAssertTrue(nextUpdate.interval.isInfinite)
        XCTAssertTrue(nextUpdate.reasons.isEmpty)

        nextUpdate.maxVelocity(160)
        XCTAssertEqual(nextUpdate.interval, 1.0 / 80.0, accuracy: 0.000_001)
        XCTAssertEqual(nextUpdate.reasons, [2_555_904])

        nextUpdate.maxVelocity(320)
        XCTAssertEqual(nextUpdate.interval, 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(nextUpdate.reasons, [2_555_904])
    }

    func testUpdateOutputsResetsBeforeFlushingTransactionScheduledWork() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        _ = viewGraph.asyncTransaction {
            viewGraph.nextUpdate.views.at(Time(seconds: 2))
        }
        XCTAssertTrue(viewGraph.hasPendingTransactions)

        viewGraph.updateOutputs(at: Time(seconds: 1))

        XCTAssertFalse(viewGraph.hasPendingTransactions)
        XCTAssertEqual(
            viewGraph.nextUpdate.views.time.seconds,
            2,
            accuracy: 0.000_001
        )
    }

    func testTimeInputSideEffectSchedulesAfterNextUpdateReset() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        var evaluatedTimes: [Time] = []
        var timeConsumer: Attribute<Void>?
        viewGraph.data.withCurrent {
            guard let timeAttr = viewGraph.timeAttr else {
                return XCTFail("Expected the instantiated view graph to have a time input.")
            }
            AGSubgraphRef.withCurrent(viewGraph.data.rootSubgraph) {
                timeConsumer = viewGraph.data.graph.makeSideEffectRule {
                    let time = timeAttr.value
                    evaluatedTimes.append(time)
                    viewGraph.nextUpdate.views.at(time + 1)
                    return ()
                }
            }
        }
        XCTAssertEqual(evaluatedTimes.count, 1)
        guard let timeConsumer else {
            return XCTFail("Expected the time-dependent output to be created.")
        }
        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())

        viewGraph.updateOutputs(at: Time(seconds: 1))
        XCTAssertEqual(evaluatedTimes.map(\.seconds), [0])
        viewGraph.data.withCurrent {
            _ = timeConsumer.value
        }

        XCTAssertEqual(evaluatedTimes.map(\.seconds), [0, 1])
        XCTAssertEqual(
            viewGraph.nextUpdate.views.time.seconds,
            2,
            accuracy: 0.000_001
        )
    }
}
