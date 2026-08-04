import XCTest
@testable import VUI

final class AnimatableAttributeCustomFiniteWrapperReplacementCompletionTests: XCTestCase {
    func testCustomNilToFiniteDelayDrainsOldLogicalAtOldNilBeforeWrapperBoundary() {
        assertCustomToFiniteWrapperReplacement(
            label: "custom nil delay",
            oldLogicalAt: nil,
            oldNilAt: 0.40,
            replacement: Animation.linear(duration: 0.30).delay(0.40),
            expectedEventsAfterOldLogical: [
                "old logical",
            ],
            expectedEventsAfterReplacementBoundary: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    func testCustomLogicalToFiniteDelayDrainsOldLogicalBeforeWrapperBoundary() {
        assertCustomToFiniteWrapperReplacement(
            label: "custom logical delay",
            oldLogicalAt: 0.10,
            oldNilAt: 1.20,
            replacement: Animation.linear(duration: 0.30).delay(0.40),
            expectedEventsAfterOldLogical: [
                "old logical",
            ],
            expectedEventsAfterReplacementBoundary: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    func testCustomNilToPositiveSpeedClampsPendingOldLogicalToWrapperBoundary() {
        assertCustomToFiniteWrapperReplacement(
            label: "custom nil speed",
            oldLogicalAt: nil,
            oldNilAt: 1.20,
            replacement: Animation.linear(duration: 0.60).speed(2.0),
            expectedEventsAfterOldLogical: [],
            expectedEventsAfterReplacementBoundary: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testCustomNilToFiniteRepeatClampsPendingOldLogicalToRepeatBoundary() {
        assertCustomToFiniteWrapperReplacement(
            label: "custom nil repeat",
            oldLogicalAt: nil,
            oldNilAt: 1.20,
            replacement: Animation.linear(duration: 0.20)
                .repeatCount(3, autoreverses: false),
            expectedEventsAfterOldLogical: [],
            expectedEventsAfterReplacementBoundary: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    private let retargetTime: TimeInterval = 0.20
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }

    private func assertCustomToFiniteWrapperReplacement(
        label: String,
        oldLogicalAt: TimeInterval?,
        oldNilAt: TimeInterval,
        replacement: Animation,
        expectedEventsAfterOldLogical: [String],
        expectedEventsAfterReplacementBoundary: [String],
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
                animation: Animation(
                    CustomFiniteWrapperSourceAnimation(
                        label: "old",
                        logicalAt: oldLogicalAt,
                        nilAt: oldNilAt,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        sampleRecorder.removeAll()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacement,
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertFalse(
            sampleRecorder.samples.isEmpty,
            "the interrupted custom animation should be sampled through its logical-listener fork",
            file: file,
            line: line
        )

        let oldLogicalSampleTime: TimeInterval
        if let oldLogicalAt {
            oldLogicalSampleTime = retargetTime + oldLogicalAt + frameInterval
        } else {
            oldLogicalSampleTime = retargetTime + oldNilAt + frameInterval
        }
        let wrapperBoundary = replacementActivationTime +
            max(replacement.box.duration, replacement.box.terminalSamplingHorizon(for: 1.5)) +
            frameInterval
        if oldLogicalSampleTime < wrapperBoundary {
            harness.advanceTime(to: oldLogicalSampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterOldLogical,
            label,
            file: file,
            line: line
        )

        harness.advanceTime(to: wrapperBoundary)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterReplacementBoundary,
            label,
            file: file,
            line: line
        )
    }

    private func sampleRunningAnimationBeforeRetarget(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.advanceTime(to: retargetTime / 2.0)
        _ = harness.currentValue()
        harness.advanceTime(to: retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }

    private func activateReplacementAnimation(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.advanceTime(to: replacementActivationTime)
        _ = harness.currentValue()
        harness.advanceTime(to: replacementActivationTime + frameInterval)
        _ = harness.currentValue()
        harness.advanceTime(to: replacementActivationTime + frameInterval * 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }
}

private struct CustomFiniteWrapperSourceAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CustomFiniteWrapperSourceAnimation,
        rhs: CustomFiniteWrapperSourceAnimation
    ) -> Bool {
        lhs.label == rhs.label &&
            lhs.logicalAt == rhs.logicalAt &&
            lhs.nilAt == rhs.nilAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(logicalAt)
        hasher.combine(nilAt)
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
        return true
    }

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}
