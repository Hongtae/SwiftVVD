import XCTest
@testable import VUI

final class AnimatableAttributeVelocityTrackingPresentationTests: XCTestCase {
    func testZeroProjectedVelocityPublishesTrackedTargetAtWriteBoundary() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var transaction = Transaction()
        transaction.tracksVelocity = true

        harness.advanceTime(to: 0.60)
        harness.setSource(
            _OpacityEffect(opacity: 0.20),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.20, accuracy: 0.000_001)

        harness.advanceTime(to: 0.65)
        XCTAssertEqual(harness.currentValue().opacity, 0.20, accuracy: 0.000_001)
        harness.advanceTime(to: 0.70)
        XCTAssertEqual(harness.currentValue().opacity, 0.20, accuracy: 0.000_001)

        harness.advanceTime(to: 1.00)
        harness.setSource(
            _OpacityEffect(opacity: 0.40),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.40, accuracy: 0.000_001)
    }

    func testNoExplicitVelocityTrackingMultistepWritesStayWithinTargetRange() {
        let fastSamples = samplesForTrackedWrites(
            targets: [0.20, 0.40, 0.60, 0.80, 1.00],
            frameStep: 0.08
        )
        XCTAssertFalse(fastSamples.isEmpty)
        XCTAssertGreaterThanOrEqual(fastSamples.min() ?? 0, -0.000_001)
        XCTAssertLessThanOrEqual(fastSamples.max() ?? 0, 1.0 + 0.000_001)

        let tinySamples = samplesForTrackedWrites(
            targets: [0.001, 0.002, 0.003, 0.004, 0.005],
            frameStep: 0.08
        )
        XCTAssertFalse(tinySamples.isEmpty)
        XCTAssertGreaterThanOrEqual(tinySamples.min() ?? 0, -0.000_001)
        XCTAssertLessThanOrEqual(tinySamples.max() ?? 0, 0.005 + 0.000_001)
    }

    func testPlainNoAnimationWriteDoesNotCreateVelocityTrackingSamplingWindow() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: Transaction()
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)

        harness.advanceTime(to: 0.50)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertTrue(harness.nextUpdateReasons().isEmpty)
    }

    private func samplesForTrackedWrites(
        targets: [Double],
        frameStep: Double
    ) -> [Double] {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var samples: [Double] = []
        var time = 0.0

        for target in targets {
            time += frameStep
            harness.advanceTime(to: time)
            var transaction = Transaction()
            transaction.tracksVelocity = true
            harness.setSource(
                _OpacityEffect(opacity: target),
                transaction: transaction
            )
            harness.finalizeTransactionBody()
            samples.append(harness.currentValue().opacity)

            time += 1.0 / 60.0
            harness.advanceTime(to: time)
            samples.append(harness.currentValue().opacity)
        }

        return samples
    }
}
