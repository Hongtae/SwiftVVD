import XCTest
@testable import VUI

final class AnimatableAttributeCustomResidualWrapperReplacementCompletionTests: XCTestCase {
    func testCustomNilToFluidSpringDelayKeepsOldSamplerUntilWrapperFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil fluid delay",
            oldLogicalAt: nil,
            oldNilAt: 1.20,
            replacement: fluidSpring.delay(0.20),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomLogicalToFluidSpringDelayDrainsOldLogicalBeforeReplacementLogical() {
        assertCustomToResidualWrapperReplacement(
            label: "custom logical fluid delay",
            oldLogicalAt: 0.35,
            oldNilAt: 1.20,
            replacement: fluidSpring.delay(0.20),
            expectedEventsAfterOldLogical: ["old logical"],
            expectedEventsAfterReplacementLogical: [
                "old logical",
                "replacement logical",
            ],
            expectedEventsAfterOldNil: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToFluidSpringSpeedKeepsRemovedUntilWrapperFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil fluid speed",
            oldLogicalAt: nil,
            oldNilAt: 1.60,
            replacement: fluidSpring.speed(0.5),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToFluidSpringRepeatKeepsRemovedUntilRepeatFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil fluid repeat",
            oldLogicalAt: nil,
            oldNilAt: 1.80,
            replacement: fluidSpring.repeatCount(2, autoreverses: false),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToDefaultDelayKeepsRemovedUntilWrapperFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil default delay",
            oldLogicalAt: nil,
            oldNilAt: 1.60,
            replacement: Animation.default.delay(0.20),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToDirectSpringDelayKeepsRemovedUntilWrapperFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil direct spring delay",
            oldLogicalAt: nil,
            oldNilAt: 1.20,
            replacement: directSpring.delay(0.20),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToDirectSpringSpeedKeepsRemovedUntilWrapperFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil direct spring speed",
            oldLogicalAt: nil,
            oldNilAt: 1.60,
            replacement: directSpring.speed(0.5),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testCustomNilToDirectSpringRepeatKeepsRemovedUntilRepeatFinalization() {
        assertCustomToResidualWrapperReplacement(
            label: "custom nil direct spring repeat",
            oldLogicalAt: nil,
            oldNilAt: 1.80,
            replacement: directSpring.repeatCount(2, autoreverses: false),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
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
    private var fluidSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0)
    }
    private var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }

    private func assertCustomToResidualWrapperReplacement(
        label: String,
        oldLogicalAt: TimeInterval?,
        oldNilAt: TimeInterval,
        replacement: Animation,
        expectedEventsAfterOldLogical: [String]?,
        expectedEventsAfterReplacementLogical: [String],
        expectedEventsAfterOldNil: [String],
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
                    CustomResidualWrapperSourceAnimation(
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

        if let oldLogicalAt, let expectedEventsAfterOldLogical {
            harness.advanceTime(to: retargetTime + oldLogicalAt + frameInterval)
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
        XCTAssertLessThan(
            replacementLogicalTime,
            retargetTime + oldNilAt,
            "\(label) replacement logical should precede old custom nil",
            file: file,
            line: line
        )
        harness.advanceTime(to: replacementLogicalTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterReplacementLogical,
            label,
            file: file,
            line: line
        )

        harness.advanceTime(to: retargetTime + oldNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        _ = expectedEventsAfterOldNil

        let finalizationTime = max(
            retargetTime + oldNilAt,
            replacementActivationTime +
                replacement.box.terminalSamplingHorizon(for: Double(1.5))
        ) + 1.0
        harness.advanceTime(to: finalizationTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedFinalEvents,
            label,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            sampleRecorder.samples.map(\.time).max() ?? 0,
            oldNilAt,
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
        harness.advanceTime(to: replacementActivationTime + (frameInterval * 2.0))
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }
}

private struct CustomResidualWrapperSourceAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CustomResidualWrapperSourceAnimation,
        rhs: CustomResidualWrapperSourceAnimation
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

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}
