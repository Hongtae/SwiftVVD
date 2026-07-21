import XCTest
@testable import VUI

final class TransactionScrollSurfaceTests: XCTestCase {
    func testScrollTargetAnchorDefaultsRoundTripAndReset() {
        var transaction = Transaction()

        XCTAssertNil(transaction.scrollTargetAnchor)

        transaction.scrollTargetAnchor = .center
        XCTAssertEqual(transaction.scrollTargetAnchor, .center)

        transaction.scrollTargetAnchor = UnitPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(transaction.scrollTargetAnchor, UnitPoint(x: 0.25, y: 0.75))

        transaction.scrollTargetAnchor = nil
        XCTAssertNil(transaction.scrollTargetAnchor)
    }

    func testScrollPositionUpdatePreservesVelocityDefaultsAndRoundTrips() {
        var transaction = Transaction()

        XCTAssertFalse(transaction.scrollPositionUpdatePreservesVelocity)

        transaction.scrollPositionUpdatePreservesVelocity = true
        XCTAssertTrue(transaction.scrollPositionUpdatePreservesVelocity)

        transaction.scrollPositionUpdatePreservesVelocity = false
        XCTAssertFalse(transaction.scrollPositionUpdatePreservesVelocity)

        XCTAssertFalse(transaction.scrollToRequiresCompleteVisibility)
        transaction.scrollToRequiresCompleteVisibility = true
        XCTAssertTrue(transaction.scrollToRequiresCompleteVisibility)
    }

    func testIsAnimatedRequiresAnimationAndHonorsDisableFlag() {
        XCTAssertFalse(Transaction().isAnimated)

        var transaction = Transaction(animation: .default)
        XCTAssertTrue(transaction.isAnimated)

        transaction.disablesAnimations = true
        XCTAssertFalse(transaction.isAnimated)
    }

    func testScrollContentOffsetAdjustmentBehaviorStorageDefaultsAndRoundTrips() {
        var transaction = Transaction()
        let automatic = ScrollContentOffsetAdjustmentBehavior.automatic
        let disabled = ScrollContentOffsetAdjustmentBehavior.disabled

        XCTAssertEqual(MemoryLayout<ScrollContentOffsetAdjustmentBehavior>.size, 1)
        XCTAssertEqual(MemoryLayout<ScrollContentOffsetAdjustmentBehavior>.stride, 1)
        XCTAssertEqual(bytes(of: automatic), [0])
        XCTAssertEqual(bytes(of: disabled), [2])
        XCTAssertEqual(mirrorChildren(of: automatic), ["role=automatic"])
        XCTAssertEqual(mirrorChildren(of: disabled), ["role=disabled"])

        XCTAssertEqual(bytes(of: transaction.scrollContentOffsetAdjustmentBehavior), bytes(of: automatic))

        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        XCTAssertEqual(bytes(of: transaction.scrollContentOffsetAdjustmentBehavior), bytes(of: disabled))

        transaction.scrollContentOffsetAdjustmentBehavior = .automatic
        XCTAssertEqual(bytes(of: transaction.scrollContentOffsetAdjustmentBehavior), bytes(of: automatic))
    }
}

private func bytes<T>(of value: T) -> [UInt8] {
    var value = value
    return withUnsafeBytes(of: &value) { Array($0) }
}

private func mirrorChildren(of value: Any) -> [String] {
    Mirror(reflecting: value).children.map { "\($0.label ?? "_")=\($0.value)" }
}
