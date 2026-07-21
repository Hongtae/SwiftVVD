import XCTest
@testable import VUI

final class AnimatableAttributeInfiniteToCustomRetargetCompletionTests: XCTestCase {
    func testRepeatForeverOldRecordsMoveToCustomNilBoundary() {
        assertInfiniteToCustomRetarget(
            label: "repeat true nil",
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            replacementLogicalAt: nil,
            replacementNilAt: 0.50,
            shouldMergeResult: true,
            expectedEarlyEvents: [],
            expectedFinalEvents: [
                "first removed",
                "replacement removed",
                "replacement logical",
                "first logical",
            ]
        )
    }

    func testRepeatForeverToCustomLogicalDrainsReplacementLogicalOnlyBeforeNil() {
        assertInfiniteToCustomRetarget(
            label: "repeat true logical",
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            replacementLogicalAt: 0.25,
            replacementNilAt: 0.70,
            shouldMergeResult: true,
            expectedEarlyEvents: ["replacement logical"],
            expectedFinalEvents: [
                "replacement logical",
                "first removed",
                "replacement removed",
                "first logical",
            ]
        )
    }

    func testRepeatForeverToCustomFalseMergeStillUsesCustomNilBoundary() {
        assertInfiniteToCustomRetarget(
            label: "repeat false nil",
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            replacementLogicalAt: nil,
            replacementNilAt: 0.50,
            shouldMergeResult: false,
            expectedEarlyEvents: [],
            expectedFinalEvents: [
                "first removed",
                "replacement removed",
                "replacement logical",
                "first logical",
            ]
        )
    }

    func testSpeedZeroAndNegativeOldRecordsMoveToCustomNilBoundary() {
        assertInfiniteToCustomRetarget(
            label: "speed zero true nil",
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            replacementLogicalAt: nil,
            replacementNilAt: 0.50,
            shouldMergeResult: true,
            expectedEarlyEvents: [],
            expectedFinalEvents: [
                "first removed",
                "replacement removed",
                "replacement logical",
                "first logical",
            ]
        )
        assertInfiniteToCustomRetarget(
            label: "speed negative true nil",
            oldAnimation: Animation.linear(duration: 0.40).speed(-1),
            replacementLogicalAt: nil,
            replacementNilAt: 0.50,
            shouldMergeResult: true,
            expectedEarlyEvents: [],
            expectedFinalEvents: [
                "first removed",
                "replacement removed",
                "replacement logical",
                "first logical",
            ]
        )
    }

    private let retargetTime: TimeInterval = 0.45
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }

    private func assertInfiniteToCustomRetarget(
        label: String,
        oldAnimation: Animation,
        replacementLogicalAt: TimeInterval?,
        replacementNilAt: TimeInterval,
        shouldMergeResult: Bool,
        expectedEarlyEvents: [String],
        expectedFinalEvents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
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
                    InfiniteToCustomRecordingAnimation(
                        label: "replacement",
                        logicalAt: replacementLogicalAt,
                        nilAt: replacementNilAt,
                        shouldMergeResult: shouldMergeResult,
                        recorder: sampleRecorder
                    )
                ),
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, label, file: file, line: line)

        if let replacementLogicalAt {
            harness.setTime(replacementActivationTime + replacementLogicalAt + frameInterval)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        XCTAssertEqual(completionRecorder.events, expectedEarlyEvents, label, file: file, line: line)

        harness.setTime(replacementActivationTime + replacementNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedFinalEvents, label, file: file, line: line)
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
        harness.setTime(replacementActivationTime + frameInterval * 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }
}

private struct InfiniteToCustomRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var shouldMergeResult: Bool
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: InfiniteToCustomRecordingAnimation,
        rhs: InfiniteToCustomRecordingAnimation
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
