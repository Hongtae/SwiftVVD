import XCTest
@testable import VUI

final class ViewGraphNextUpdateTests: XCTestCase {
    func testMaxVelocitySchedulesHighFrameRateIntervals() {
        var update = ViewGraph.NextUpdate()
        update.maxVelocity(159.9)
        XCTAssertTrue(update.interval.isInfinite)
        XCTAssertTrue(update.reasons.isEmpty)

        update.maxVelocity(160)
        XCTAssertEqual(update.interval, 1.0 / 80.0, accuracy: 0.000_000_001)
        XCTAssertEqual(update.reasons, [2_555_904])

        update.maxVelocity(320)
        XCTAssertEqual(update.interval, 1.0 / 120.0, accuracy: 0.000_000_001)
        XCTAssertEqual(update.reasons, [2_555_904])
    }

    func testZeroIntervalRequestIgnoresSlowerFollowUpIntervals() {
        var update = ViewGraph.NextUpdate()
        update.interval(0)
        update.interval(0.5, reason: 9)
        XCTAssertTrue(update.interval.isInfinite)
        XCTAssertEqual(update.reasons, [9])

        update.maxVelocity(160)
        XCTAssertEqual(update.interval, 1.0 / 80.0, accuracy: 0.000_000_001)
        XCTAssertEqual(update.reasons, [9, 2_555_904])
    }
}