import XCTest
@testable import VUI

final class AnimatableAttributeBuiltInRetargetCompletionTests: XCTestCase {
    func testRepeatedLinearRetargetKeepsLogicalDeadlinesSeparate() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.8),
                label: "second",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.50)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.6),
                label: "third",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.02)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["first logical"])

        harness.setTime(1.08)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "first logical",
                "second logical",
            ]
        )

        harness.setTime(1.14)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "first logical",
                "second logical",
                "third logical",
            ]
        )
    }

    func testFiniteRetargetCanDrainNewerLogicalBeforeOlderLogicalAfterActiveRetarget() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 2.4),
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.65)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.7),
                label: "middle",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(1.05)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 8.0),
                label: "active",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.30)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.42)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"])

        harness.setTime(2.55)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
        XCTAssertFalse(recorder.events.contains("active logical"))
    }

    func testNoAnimationRetargetPreservesOldLogicalDeadline() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        let nilTransaction = logicalCompletionTransaction(
            animation: nil,
            label: "nil",
            recorder: recorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: -0.5))
        }
        let nilRetargetValue = harness.currentValue().opacity
        harness.finalizeTransactionBody()
        XCTAssertGreaterThanOrEqual(nilRetargetValue, -1.500_001)
        XCTAssertLessThan(nilRetargetValue, -0.5)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["nil logical"])

        harness.setTime(0.50)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.6),
                label: "third",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(1.02)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["nil logical", "first logical"])

        harness.setTime(1.14)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "nil logical",
                "first logical",
                "third logical",
            ]
        )
    }

    func testLinearToFluidSpringSeparatesReplacementLogicalFromOldFinalization() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 0.30,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "spring",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.62)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["spring logical"])

        harness.setTime(0.82)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "spring logical",
                "first logical",
            ]
        )
    }

    func testFluidSpringToLinearGroupsOldSpringWithReplacementBoundary() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 0.80,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "spring",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.5),
                label: "linear",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.70)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.82)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "linear logical",
                "spring logical",
            ]
        )
    }

    private func logicalCompletionTransaction(
        animation: Animation?,
        label: String,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("\(label) logical")
        }
        return transaction
    }
}
