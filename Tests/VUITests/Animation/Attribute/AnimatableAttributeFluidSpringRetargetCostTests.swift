import Foundation
import XCTest
@testable import VUI

private final class FluidSpringMagnitudeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int {
        lock.withLock { storage }
    }

    func reset() {
        lock.withLock {
            storage = 0
        }
    }

    func recordMagnitudeRead() {
        lock.withLock {
            storage += 1
        }
    }
}

private struct MagnitudeCountingVector: VectorArithmetic {
    var value: Double
    var counter: FluidSpringMagnitudeCounter?

    static var zero: MagnitudeCountingVector {
        MagnitudeCountingVector(value: 0, counter: nil)
    }

    static func == (
        lhs: MagnitudeCountingVector,
        rhs: MagnitudeCountingVector
    ) -> Bool {
        lhs.value == rhs.value
    }

    static func + (
        lhs: MagnitudeCountingVector,
        rhs: MagnitudeCountingVector
    ) -> MagnitudeCountingVector {
        MagnitudeCountingVector(
            value: lhs.value + rhs.value,
            counter: lhs.counter ?? rhs.counter
        )
    }

    static func - (
        lhs: MagnitudeCountingVector,
        rhs: MagnitudeCountingVector
    ) -> MagnitudeCountingVector {
        MagnitudeCountingVector(
            value: lhs.value - rhs.value,
            counter: lhs.counter ?? rhs.counter
        )
    }

    mutating func scale(by rhs: Double) {
        value *= rhs
    }

    var magnitudeSquared: Double {
        counter?.recordMagnitudeRead()
        return value * value
    }
}

private struct MagnitudeCountingAnimatable: Animatable {
    var value: Double
    let counter: FluidSpringMagnitudeCounter

    var animatableData: MagnitudeCountingVector {
        get {
            MagnitudeCountingVector(value: value, counter: counter)
        }
        set {
            value = newValue.value
        }
    }
}

final class AnimatableAttributeFluidSpringRetargetCostTests: XCTestCase {
    func testDirectFluidSpringLogicalOnlySecondRetargetDoesNotScanTargetLifetime() {
        let counter = FluidSpringMagnitudeCounter()
        let harness = GenericAnimatableAttributeHarness(
            initialValue: MagnitudeCountingAnimatable(
                value: 0,
                counter: counter
            )
        )
        XCTAssertEqual(harness.currentValue().value, 0, accuracy: 0.000_001)

        harness.setSource(
            MagnitudeCountingAnimatable(value: 1, counter: counter),
            transaction: logicalSpringTransaction()
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.65)
        _ = harness.currentValue()
        harness.setSource(
            MagnitudeCountingAnimatable(value: 0, counter: counter),
            transaction: logicalSpringTransaction()
        )
        counter.reset()
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        XCTAssertEqual(counter.count, 0)

        harness.setTime(1.30)
        _ = harness.currentValue()
        harness.setSource(
            MagnitudeCountingAnimatable(value: 1, counter: counter),
            transaction: logicalSpringTransaction()
        )
        counter.reset()
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        XCTAssertEqual(
            counter.count,
            2,
            "A direct FluidSpring logical-only retarget must keep the live " +
                "spring sampler as the terminal owner instead of scanning a " +
                "target-vector presentation lifetime."
        )
    }

    private func logicalSpringTransaction() -> Transaction {
        var transaction = Transaction(
            animation: .spring(
                response: 5,
                dampingFraction: 0.65,
                blendDuration: 0
            )
        )
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {}
        return transaction
    }
}
