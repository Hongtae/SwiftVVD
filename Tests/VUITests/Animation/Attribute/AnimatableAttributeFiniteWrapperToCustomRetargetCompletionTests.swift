import XCTest
@testable import VUI

final class AnimatableAttributeFiniteWrapperToCustomRetargetCompletionTests: XCTestCase {
    func testDelayToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "delay true nil",
            oldAnimation: .linear(duration: 0.50).delay(0.30),
            oldLogicalTime: 0.80,
            replacementLogicalAt: nil,
            replacementNilAt: 1.20,
            shouldMergeResult: true,
            expectedAtOldLogical: ["first logical"],
            expectedFinalEvents: [
                "first logical",
                "first removed",
                "second removed",
                "second logical",
            ]
        )
    }

    func testDelayToCustomTrueLogicalPreservesBothEarlyLogicalRows() {
        assertPreservedWrapperLogical(
            label: "delay true logical",
            oldAnimation: .linear(duration: 0.50).delay(0.30),
            oldLogicalTime: 0.80,
            replacementLogicalAt: 0.45,
            replacementNilAt: 1.20,
            shouldMergeResult: true,
            expectedAtOldLogical: [
                "second logical",
                "first logical",
            ],
            expectedFinalEvents: [
                "second logical",
                "first logical",
                "first removed",
                "second removed",
            ]
        )
    }

    func testDelayToCustomFalseNilStillMovesRemovedToCustomNil() {
        assertPreservedWrapperLogical(
            label: "delay false nil",
            oldAnimation: .linear(duration: 0.50).delay(0.30),
            oldLogicalTime: 0.80,
            replacementLogicalAt: nil,
            replacementNilAt: 1.20,
            shouldMergeResult: false,
            expectedAtOldLogical: ["first logical"],
            expectedFinalEvents: [
                "first logical",
                "first removed",
                "second removed",
                "second logical",
            ]
        )
    }

    func testSpeedToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "speed true nil",
            oldAnimation: .linear(duration: 0.80).speed(2.0),
            oldLogicalTime: 0.40,
            replacementLogicalAt: nil,
            replacementNilAt: 1.20,
            shouldMergeResult: true,
            expectedAtOldLogical: ["first logical"],
            expectedFinalEvents: [
                "first logical",
                "first removed",
                "second removed",
                "second logical",
            ]
        )
    }

    func testRepeatToCustomTrueNilMovesOldLogicalWithRemovedToCustomNil() {
        assertRepeatWrapperMovedToCustomNil(
            label: "repeat true nil",
            oldAnimation: .linear(duration: 0.20)
                .repeatCount(3, autoreverses: false),
            oldLogicalTime: 0.60,
            replacementNilAt: 2.00
        )
    }

    private let retargetTime: TimeInterval = 0.18
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }

    private func assertPreservedWrapperLogical(
        label: String,
        oldAnimation: Animation,
        oldLogicalTime: TimeInterval,
        replacementLogicalAt: TimeInterval?,
        replacementNilAt: TimeInterval,
        shouldMergeResult: Bool,
        expectedAtOldLogical: [String],
        expectedFinalEvents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let setup = makeRetargetedHarness(
            label: label,
            oldAnimation: oldAnimation,
            replacementLogicalAt: replacementLogicalAt,
            replacementNilAt: replacementNilAt,
            shouldMergeResult: shouldMergeResult,
            file: file,
            line: line
        )
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, label, file: file, line: line)

        if let replacementLogicalAt {
            harness.setTime(replacementActivationTime + replacementLogicalAt + frameInterval)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        harness.setTime(oldLogicalTime + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedAtOldLogical, label, file: file, line: line)

        harness.setTime(replacementActivationTime + replacementNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedFinalEvents, label, file: file, line: line)
    }

    private func assertRepeatWrapperMovedToCustomNil(
        label: String,
        oldAnimation: Animation,
        oldLogicalTime: TimeInterval,
        replacementNilAt: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let setup = makeRetargetedHarness(
            label: label,
            oldAnimation: oldAnimation,
            replacementLogicalAt: nil,
            replacementNilAt: replacementNilAt,
            shouldMergeResult: true,
            file: file,
            line: line
        )
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, label, file: file, line: line)

        harness.setTime(oldLogicalTime + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        harness.setTime(replacementActivationTime + replacementNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "first removed",
                "second removed",
                "second logical",
                "first logical",
            ],
            label,
            file: file,
            line: line
        )
    }

    private func makeRetargetedHarness(
        label: String,
        oldAnimation: Animation,
        replacementLogicalAt: TimeInterval?,
        replacementNilAt: TimeInterval,
        shouldMergeResult: Bool,
        file: StaticString,
        line: UInt
    ) -> (
        harness: AnimatableAttributeHarness,
        completionRecorder: AnimationCompletionRecorder,
        sampleRecorder: CustomRetargetSampleRecorder
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "first",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    FiniteWrapperToCustomRecordingAnimation(
                        label: "second",
                        logicalAt: replacementLogicalAt,
                        nilAt: replacementNilAt,
                        shouldMergeResult: shouldMergeResult,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        return (harness, completionRecorder, sampleRecorder)
    }

    private func sampleRunningAnimationBeforeRetarget(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(retargetTime / 2.0)
        _ = harness.currentValue()
        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }

    private func activateReplacementAnimation(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(replacementActivationTime)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + frameInterval)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + (frameInterval * 2.0))
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }
}

private struct FiniteWrapperToCustomRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var shouldMergeResult: Bool
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: FiniteWrapperToCustomRecordingAnimation,
        rhs: FiniteWrapperToCustomRecordingAnimation
    ) -> Bool {
        lhs.label == rhs.label &&
            lhs.logicalAt == rhs.logicalAt &&
            lhs.nilAt == rhs.nilAt &&
            lhs.shouldMergeResult == rhs.shouldMergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(logicalAt)
        hasher.combine(nilAt)
        hasher.combine(shouldMergeResult)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if let logicalAt, time >= logicalAt {
            context.isLogicallyComplete = true
        }
        recorder.recordSample(label: label, time: time, input: doubleValue(value))
        guard time < nilAt else {
            return nil
        }
        var output = value
        output.scale(by: max(time / nilAt, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.recordShouldMerge()
        return shouldMergeResult
    }

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}
