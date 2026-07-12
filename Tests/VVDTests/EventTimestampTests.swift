#if ENABLE_WAYLAND
import XCTest
@testable import VVD

final class EventTimestampTests: XCTestCase {
    func testMillisecondTimestampExtenderPreservesRolloverContinuity() {
        var clock = MillisecondTimestampExtender()

        let first = clock.timestamp(for: UInt32.max - 2)
        let second = clock.timestamp(for: UInt32.max)
        let wrapped = clock.timestamp(for: 3)

        XCTAssertEqual(second - first, 0.002, accuracy: 0.000_001)
        XCTAssertEqual(wrapped - second, 0.004, accuracy: 0.000_001)
        XCTAssertGreaterThan(wrapped, second)
    }

    func testMillisecondTimestampExtenderPreservesSignedBitRange() {
        var clock = MillisecondTimestampExtender()

        let beforeSignBit = clock.timestamp(for: 0x7fff_ffff)
        let afterSignBit = clock.timestamp(for: 0x8000_0001)

        XCTAssertEqual(afterSignBit - beforeSignBit, 0.002, accuracy: 0.000_001)
    }
}
#endif
