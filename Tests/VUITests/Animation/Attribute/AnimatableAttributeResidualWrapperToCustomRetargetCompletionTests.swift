import XCTest
@testable import VUI

final class AnimatableAttributeResidualWrapperToCustomRetargetCompletionTests: XCTestCase {
    func testFluidSpringDelayToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "fluid delay true nil",
            oldAnimation: fluidSpring.delay(0.20),
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

    func testFluidSpringDelayToCustomTrueLogicalPreservesBothEarlyLogicalRows() {
        assertPreservedWrapperLogical(
            label: "fluid delay true logical",
            oldAnimation: fluidSpring.delay(0.20),
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

    func testFluidSpringDelayToCustomFalseNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "fluid delay false nil",
            oldAnimation: fluidSpring.delay(0.20),
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

    func testSpringRepeatToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "spring repeat true nil",
            oldAnimation: directSpring.repeatCount(2, autoreverses: false),
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

    func testSpringDelayToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "spring delay true nil",
            oldAnimation: directSpring.delay(0.20),
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

    func testSpringSpeedToCustomTrueNilMovesOldLogicalWithCustomNil() {
        assertWrapperLogicalAtCustomNil(
            label: "spring speed true nil",
            oldAnimation: directSpring.speed(0.5),
            replacementNilAt: 1.20
        )
    }

    func testDefaultDelayToCustomTrueNilPreservesOldLogicalDeadline() {
        assertPreservedWrapperLogical(
            label: "default delay true nil",
            oldAnimation: Animation.default.delay(0.20),
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

    private let retargetTime: TimeInterval = 0.22
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

    private func assertPreservedWrapperLogical(
        label: String,
        oldAnimation: Animation,
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

        _ = replacementLogicalAt
        _ = oldAnimation
        var sawExpectedPreterminalEvents = expectedAtOldLogical.isEmpty
        var sampleTime = replacementActivationTime + frameInterval * 3
        let replacementTerminalTime =
            replacementActivationTime + replacementNilAt
        while sampleTime < replacementTerminalTime {
            harness.advanceTime(to: sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            if completionRecorder.events == expectedAtOldLogical {
                sawExpectedPreterminalEvents = true
            }
            sampleTime += frameInterval
        }
        XCTAssertTrue(
            sawExpectedPreterminalEvents,
            "\(label) did not expose the probed preterminal completion prefix",
            file: file,
            line: line
        )

        harness.advanceTime(to: replacementTerminalTime + frameInterval * 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedFinalEvents, label, file: file, line: line)
    }

    private func assertWrapperLogicalAtCustomNil(
        label: String,
        oldAnimation: Animation,
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

        _ = oldAnimation
        var sampleTime = replacementActivationTime + frameInterval * 3
        let searchEnd =
            replacementActivationTime + replacementNilAt + frameInterval * 4
        while sampleTime <= searchEnd, completionRecorder.events.isEmpty {
            harness.advanceTime(to: sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            sampleTime += frameInterval
        }
        let terminalCustomSample = sampleRecorder.samples.last {
            $0.label == "second"
        }
        XCTAssertGreaterThanOrEqual(
            terminalCustomSample?.time ?? -.infinity,
            replacementNilAt,
            label,
            file: file,
            line: line
        )
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
                    ResidualWrapperToCustomRecordingAnimation(
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

private struct ResidualWrapperToCustomRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var shouldMergeResult: Bool
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: ResidualWrapperToCustomRecordingAnimation,
        rhs: ResidualWrapperToCustomRecordingAnimation
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
