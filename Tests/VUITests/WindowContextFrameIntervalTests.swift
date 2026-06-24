import XCTest
@testable import VUI

final class WindowContextFrameIntervalTests: XCTestCase {
    func testRequestedFrameIntervalCanOnlyTightenConfiguredInterval() {
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: 1.0 / 120.0
            ),
            1.0 / 120.0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: 0.5
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: 1.0 / 60.0
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
    }

    func testInvalidRequestedFrameIntervalFallsBackToConfiguredInterval() {
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: nil
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: 0
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: .infinity
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            WindowContext.resolvedFrameInterval(
                configured: 1.0 / 60.0,
                requested: .nan
            ),
            1.0 / 60.0,
            accuracy: 0.000_000_001
        )
    }
}
