import XCTest
@testable import VUI

final class AnimatableAttributeCustomDefaultRetargetCompletionTests: XCTestCase {
    func testSourceCustomForkNilDrainsLogicalBeforeDefaultTerminal() {
        assertSourceCustomToDefaultRetarget(
            label: "customToDefaultNil",
            oldLogicalAt: nil
        )
    }

    func testSourceCustomForkLogicalFlagDrainsBeforeDefaultTerminal() {
        assertSourceCustomToDefaultRetarget(
            label: "customToDefaultLogical",
            oldLogicalAt: 0.20
        )
    }

    func testSourceCustomNoAnimationRetargetNilBoundaryKeepsOldSamplerUntilCustomNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        let customNilAt: TimeInterval = 4.0
        let retargetSampleTime: TimeInterval = 0.60
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: Animation(
                    CriteriaRetargetRecordingAnimation(
                        label: "old",
                        logicalAt: nil,
                        nilAt: customNilAt,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)
        harness.advanceTime(to: 0.50)
        _ = harness.currentValue()
        harness.advanceTime(to: retargetSampleTime)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        guard let lastSampleBeforeRetarget = sampleRecorder.samples.map(\.time).max() else {
            XCTFail("missing pre-retarget custom sample")
            return
        }
        sampleRecorder.removeAll()

        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        var immediateRetargetValue: Double = 0
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: -0.5))
            immediateRetargetValue = harness.currentValue().opacity
        }
        harness.finalizeTransactionBody()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(immediateRetargetValue, -1.5)
        XCTAssertLessThan(immediateRetargetValue, -0.5)
        XCTAssertEqual(sampleRecorder.shouldMergeCount, 0)
        guard let immediateOldSample = sampleRecorder.samples.last(where: { $0.label == "old" }) else {
            XCTFail("missing immediate post-retarget old custom sample")
            return
        }
        XCTAssertEqual(immediateOldSample.input, 1.0, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(
            immediateOldSample.time,
            lastSampleBeforeRetarget - 0.000_001
        )
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
        completionRecorder.removeAll()
        sampleRecorder.removeAll()

        harness.advanceTime(to: retargetSampleTime + frameInterval * 2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(sampleRecorder.shouldMergeCount, 0)
        guard let continuedOldSample = sampleRecorder.samples.last(where: { $0.label == "old" }) else {
            XCTFail("missing continued post-retarget old custom sample")
            return
        }
        XCTAssertEqual(continuedOldSample.input, 1.0, accuracy: 0.000_001)
        XCTAssertGreaterThan(continuedOldSample.time, immediateOldSample.time)

        harness.advanceTime(to: customNilAt + 1.0)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
    }

    func testDefaultForkLogicalBoundaryPrecedesSourceCustomNil() {
        let oldPresentationTime = defaultPresentationTime()
        assertDefaultToSourceCustomRetarget(
            label: "defaultToCustomNil",
            replacementLogicalAt: nil,
            replacementNilAt: max(0.30, oldPresentationTime - replacementActivationTime - frameInterval),
            earlyOldLogicalSampleTime: nil,
            expectedEventsAtNil: [
                "old logical",
                "old removed",
                "replacement removed",
                "replacement logical",
            ]
        )
    }

    func testDefaultAndReplacementLogicalFlagsFollowSampleOrder() {
        let oldPresentationTime = defaultPresentationTime()
        let replacementNilAt = max(0.95, oldPresentationTime + 0.35 - replacementActivationTime)
        assertDefaultToSourceCustomRetarget(
            label: "defaultToCustomLogical",
            replacementLogicalAt: 0.45,
            replacementNilAt: replacementNilAt,
            earlyOldLogicalSampleTime: oldPresentationTime + frameInterval,
            expectedEventsAtNil: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
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

        let oldCompletionSample = max(
            oldCustomNilAt,
            oldLogicalAt ?? oldCustomNilAt
        ) + frameInterval
        harness.advanceTime(to: oldCompletionSample)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            ["old logical"],
            file: file,
            line: line
        )

        let defaultFinalizationTime = replacementActivationTime +
            Animation.default.box.terminalSamplingHorizon(for: Double(1.0)) +
            frameInterval
        XCTAssertGreaterThan(defaultFinalizationTime, oldCustomNilAt, file: file, line: line)
        harness.advanceTime(to: defaultFinalizationTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old logical",
                "old removed",
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
            harness.advanceTime(to: earlyOldLogicalSampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "replacement logical",
                    "old logical",
                ],
                file: file,
                line: line
            )
        } else {
            XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        }

        harness.advanceTime(to: replacementActivationTime + replacementNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedEventsAtNil, file: file, line: line)
    }

    private func defaultPresentationTime() -> TimeInterval {
        let activeBeginTime = retargetTime - (frameInterval * 2.0)
        return activeBeginTime + Animation.default.box.terminalSamplingHorizon(for: Double(0.80))
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
