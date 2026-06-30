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
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: Transaction(animation: nil)
        )
        let nilRetargetValue = harness.currentValue().opacity
        harness.finalizeTransactionBody()
        XCTAssertGreaterThanOrEqual(nilRetargetValue, -1.500_001)
        XCTAssertLessThan(nilRetargetValue, -0.5)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

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
        XCTAssertEqual(recorder.events, ["first logical"])

        harness.setTime(1.14)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
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
