import XCTest
@testable import VUI

final class AnimatableAttributeCustomDefaultRetargetCompletionTests: XCTestCase {
    func testSourceCustomToDefaultNilBoundaryFinishesOldBeforeDefaultFinalization() {
        assertSourceCustomToDefaultRetarget(
            label: "customToDefaultNil",
            oldLogicalAt: nil
        )
    }

    func testSourceCustomToDefaultLogicalBoundaryDoesNotDrainBeforeOldNil() {
        assertSourceCustomToDefaultRetarget(
            label: "customToDefaultLogical",
            oldLogicalAt: 0.20
        )
    }

    func testDefaultToSourceCustomNilBoundaryGroupsOldDefaultWithCustomNil() {
        let oldPresentationTime = defaultPresentationTime()
        assertDefaultToSourceCustomRetarget(
            label: "defaultToCustomNil",
            replacementLogicalAt: nil,
            replacementNilAt: max(0.30, oldPresentationTime - replacementActivationTime - frameInterval),
            earlyOldLogicalSampleTime: nil,
            expectedEventsAtNil: [
                "old removed",
                "old logical",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    func testDefaultToSourceCustomLogicalBoundaryAllowsOldLogicalBeforeCustomNil() {
        let oldPresentationTime = defaultPresentationTime()
        let replacementNilAt = max(0.95, oldPresentationTime + 0.35 - replacementActivationTime)
        assertDefaultToSourceCustomRetarget(
            label: "defaultToCustomLogical",
            replacementLogicalAt: 0.45,
            replacementNilAt: replacementNilAt,
            earlyOldLogicalSampleTime: oldPresentationTime + frameInterval,
            expectedEventsAtNil: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    private let retargetTime: TimeInterval = 0.10
    private let oldCustomNilAt: TimeInterval = 0.35
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }

    private func assertSourceCustomToDefaultRetarget(
        label: String,
        oldLogicalAt: TimeInterval?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 1.0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 1.0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 0.20),
            transaction: completionTransaction(
                animation: Animation(
                    CriteriaRetargetRecordingAnimation(
                        label: "old",
                        logicalAt: oldLogicalAt,
                        nilAt: oldCustomNilAt,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 0.80),
            transaction: completionTransaction(
                animation: .default,
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        if let oldLogicalAt {
            harness.setTime(oldLogicalAt + frameInterval)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        }

        let defaultFinalizationTime = replacementActivationTime +
            Animation.default.box.presentationDuration(for: Double(1.0)) +
            frameInterval
        XCTAssertGreaterThan(defaultFinalizationTime, oldCustomNilAt, file: file, line: line)
        harness.setTime(defaultFinalizationTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "old logical",
                "replacement removed",
                "replacement logical",
            ],
            file: file,
            line: line
        )
    }

    private func assertDefaultToSourceCustomRetarget(
        label: String,
        replacementLogicalAt: TimeInterval?,
        replacementNilAt: TimeInterval,
        earlyOldLogicalSampleTime: TimeInterval?,
        expectedEventsAtNil: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 1.0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 1.0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 0.20),
            transaction: completionTransaction(
                animation: .default,
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 0.80),
            transaction: completionTransaction(
                animation: Animation(
                    CriteriaRetargetRecordingAnimation(
                        label: "replacement",
                        logicalAt: replacementLogicalAt,
                        nilAt: replacementNilAt,
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
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, file: file, line: line)

        if let earlyOldLogicalSampleTime {
            XCTAssertLessThan(
                earlyOldLogicalSampleTime,
                replacementActivationTime + replacementNilAt,
                file: file,
                line: line
            )
            harness.setTime(earlyOldLogicalSampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["old logical"], file: file, line: line)
        } else {
            XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        }

        harness.setTime(replacementActivationTime + replacementNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedEventsAtNil, file: file, line: line)
    }

    private func defaultPresentationTime() -> TimeInterval {
        let activeBeginTime = retargetTime - (frameInterval * 2.0)
        return activeBeginTime + Animation.default.box.presentationDuration(for: Double(0.80))
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

private struct CriteriaRetargetRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CriteriaRetargetRecordingAnimation,
        rhs: CriteriaRetargetRecordingAnimation
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
        recorder.recordShouldMerge()
        return true
    }

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}
