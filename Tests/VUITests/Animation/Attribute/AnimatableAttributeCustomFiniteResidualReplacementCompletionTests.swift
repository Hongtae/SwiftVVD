import XCTest
@testable import VUI

final class AnimatableAttributeCustomFiniteResidualReplacementCompletionTests: XCTestCase {
    func testCustomNilToFiniteLinearGroupsPendingOldLogicalAtReplacementBoundary() {
        assertCustomToFiniteOrResidualReplacement(
            label: "custom nil linear",
            oldLogicalAt: nil,
            oldNilAt: 0.80,
            replacement: .linear(duration: 0.30),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ],
            expectedFinalEvents: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testCustomLogicalToFiniteLinearDrainsOldLogicalBeforeReplacementBoundary() {
        assertCustomToFiniteOrResidualReplacement(
            label: "custom logical linear",
            oldLogicalAt: 0.10,
            oldNilAt: 0.80,
            replacement: .linear(duration: 0.30),
            expectedEventsAfterOldLogical: ["old logical"],
            expectedEventsAfterReplacementLogical: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ],
            expectedFinalEvents: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    func testCustomNilToResidualSpringDrainsReplacementLogicalBeforeFinalSnap() {
        assertCustomToFiniteOrResidualReplacement(
            label: "custom nil spring",
            oldLogicalAt: nil,
            oldNilAt: 0.80,
            replacement: residualSpring,
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedFinalEvents: [
                "replacement logical",
                "old removed",
                "replacement removed",
                "old logical",
            ]
        )
    }

    func testCustomLogicalToResidualSpringKeepsOldLogicalBeforeReplacementLogical() {
        assertCustomToFiniteOrResidualReplacement(
            label: "custom logical spring",
            oldLogicalAt: 0.10,
            oldNilAt: 0.80,
            replacement: residualSpring,
            expectedEventsAfterOldLogical: ["old logical"],
            expectedEventsAfterReplacementLogical: [
                "old logical",
                "replacement logical",
            ],
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    private let retargetTime: TimeInterval = 0.20
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }
    private var residualSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0)
    }

    private func assertCustomToFiniteOrResidualReplacement(
        label: String,
        oldLogicalAt: TimeInterval?,
        oldNilAt: TimeInterval,
        replacement: Animation,
        expectedEventsAfterOldLogical: [String]?,
        expectedEventsAfterReplacementLogical: [String],
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
                animation: Animation(
                    CustomFiniteResidualSourceAnimation(
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
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
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
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
        XCTAssertFalse(
            sampleRecorder.samples.isEmpty,
            "old custom side-effect sampler should keep running after retarget",
            file: file,
            line: line
        )

        if let oldLogicalAt, let expectedEventsAfterOldLogical {
            harness.setTime(retargetTime + oldLogicalAt + frameInterval)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                expectedEventsAfterOldLogical,
                label,
                file: file,
                line: line
            )
        }

        let replacementLogicalTime = replacementActivationTime + replacement.box.duration + frameInterval
        harness.setTime(replacementLogicalTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterReplacementLogical,
            label,
            file: file,
            line: line
        )

        let replacementFinalTime = replacementActivationTime +
            max(replacement.box.duration, replacement.box.terminalSamplingHorizon(for: 1.5)) +
            frameInterval
        let oldNilTime = retargetTime + oldNilAt + frameInterval
        harness.setTime(max(replacementFinalTime, oldNilTime))
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

private struct CustomFiniteResidualSourceAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CustomFiniteResidualSourceAnimation,
        rhs: CustomFiniteResidualSourceAnimation
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
