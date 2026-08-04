import XCTest
@testable import VUI

final class AnimatableAttributeNegativeSpeedRetargetCompletionTests: XCTestCase {
    func testNegativeSpeedOldRecordsGroupWithFiniteReplacementBoundary() {
        let recorder = AnimationCompletionRecorder()
        let harness = makeHarness()
        let replacementStart = 0.25
        let replacementAnimation = Animation.linear(duration: 0.30)

        startAnimation(
            harness,
            animation: Animation.linear(duration: 0.30).speed(-1),
            label: "negative",
            target: 1,
            recorder: recorder
        )
        retarget(
            harness,
            at: replacementStart,
            animation: replacementAnimation,
            label: "linear",
            target: -0.5,
            recorder: recorder
        )

        sample(harness, at: replacementStart + 0.29)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        sample(harness, at: replacementStart + 0.31)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "negative removed",
                "linear removed",
                "linear logical",
                "negative logical",
            ]
        )
    }

    func testNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: Animation.spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ),
            replacementLabel: "fluid"
        )
    }

    func testNegativeSpeedOldRecordsWaitForDirectSpringReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: .interpolatingSpring(
                mass: 1.0,
                stiffness: 100.0,
                damping: 10.0,
                initialVelocity: 0.0
            ),
            replacementLabel: "spring"
        )
    }

    func testNegativeSpeedOldRecordsWaitForDefaultReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: .default,
            replacementLabel: "default"
        )
    }

    func testNegativeSpeedOldRecordsWaitForSnappyReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: .snappy(duration: 0.35, extraBounce: 0.0),
            replacementLabel: "snappy"
        )
    }

    func testNegativeSpeedOldRecordsWaitForSpringPropertyReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: .spring,
            replacementLabel: "springProperty"
        )
    }

    func testNegativeSpeedOldRecordsWaitForSpringNoArgumentReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
            replacementAnimation: .spring(),
            replacementLabel: "springNoArg"
        )
    }

    func testNegativeSpeedOldRecordsGroupWithSpringDurationReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsGroupAtResidualFinalSnap(
            replacementAnimation: .spring(duration: 0.50, bounce: 0.20, blendDuration: 0.0),
            replacementLabel: "springDuration"
        )
    }

    func testNegativeSpeedOldRecordsGroupWithSpringValueReplacementFinalSnap() {
        assertNegativeSpeedOldRecordsGroupAtResidualFinalSnap(
            replacementAnimation: .spring(Spring(duration: 0.50, bounce: 0.20), blendDuration: 0.0),
            replacementLabel: "springValue"
        )
    }

    private func assertNegativeSpeedOldRecordsWaitForResidualReplacementFinalSnap(
        replacementAnimation: Animation,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = makeHarness()
        let replacementStart = 0.25
        let logicalDuration = replacementAnimation.box.duration
        let terminalSamplingHorizon = replacementAnimation.box.terminalSamplingHorizon(
            for: Double(1.5)
        )
        XCTAssertGreaterThan(terminalSamplingHorizon, logicalDuration, file: file, line: line)

        startAnimation(
            harness,
            animation: Animation.linear(duration: 0.30).speed(-1),
            label: "negative",
            target: 1,
            recorder: recorder
        )
        retarget(
            harness,
            at: replacementStart,
            animation: replacementAnimation,
            label: replacementLabel,
            target: -0.5,
            recorder: recorder
        )

        sample(harness, at: replacementStart + logicalDuration + replacementAnimation.box.defaultDisplayFrameInterval)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["\(replacementLabel) logical"], file: file, line: line)

        var sampleTime = replacementStart + logicalDuration +
            replacementAnimation.box.defaultDisplayFrameInterval * 2
        let finalSampleTime = replacementStart + terminalSamplingHorizon + 1.0
        while sampleTime <= finalSampleTime,
              recorder.events.count < 4 {
            sample(harness, at: sampleTime)
            harness.flushCompletionActions()
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }
        XCTAssertEqual(
            recorder.events,
            [
                "\(replacementLabel) logical",
                "negative removed",
                "\(replacementLabel) removed",
                "negative logical",
            ],
            file: file,
            line: line
        )
    }

    private func assertNegativeSpeedOldRecordsGroupAtResidualFinalSnap(
        replacementAnimation: Animation,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = makeHarness()
        let replacementStart = 0.25

        startAnimation(
            harness,
            animation: Animation.linear(duration: 0.30).speed(-1),
            label: "negative",
            target: 1,
            recorder: recorder
        )
        retarget(
            harness,
            at: replacementStart,
            animation: replacementAnimation,
            label: replacementLabel,
            target: -0.5,
            recorder: recorder
        )

        var sampleTime = replacementStart + replacementAnimation.box.defaultDisplayFrameInterval
        let finalSampleTime = replacementStart + max(
            replacementAnimation.box.terminalSamplingHorizon(for: Double(1.5)),
            replacementAnimation.box.terminalSamplingHorizon
        ) + 1.0
        while sampleTime <= finalSampleTime,
              recorder.events.count < 4 {
            sample(harness, at: sampleTime)
            harness.flushCompletionActions()
            if recorder.events.count < 4 {
                XCTAssertEqual(recorder.events, [], file: file, line: line)
            }
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }
        XCTAssertEqual(
            recorder.events,
            [
                "negative removed",
                "\(replacementLabel) removed",
                "\(replacementLabel) logical",
                "negative logical",
            ],
            file: file,
            line: line
        )
    }

    func testNegativeSpeedReplacementKeepsRemovedAndReplacementLogicalPending() {
        let recorder = AnimationCompletionRecorder()
        let harness = makeHarness()
        let replacementStart = 0.20

        startAnimation(
            harness,
            animation: .linear(duration: 0.65),
            label: "linear",
            target: 1,
            recorder: recorder
        )
        retarget(
            harness,
            at: replacementStart,
            animation: Animation.linear(duration: 0.30).speed(-1),
            label: "negative",
            target: -0.5,
            recorder: recorder
        )

        sample(harness, at: 0.64)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        sample(harness, at: 0.67)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["linear logical"])

        sample(harness, at: 2.0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["linear logical"])
    }

    private func makeHarness(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AnimatableAttributeHarness {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(
            harness.currentValue().opacity,
            0,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        return harness
    }

    private func startAnimation(
        _ harness: AnimatableAttributeHarness,
        animation: Animation,
        label: String,
        target: Double,
        recorder: AnimationCompletionRecorder
    ) {
        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: completionTransaction(
                animation: animation,
                label: label,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
    }

    private func retarget(
        _ harness: AnimatableAttributeHarness,
        at time: Double,
        animation: Animation,
        label: String,
        target: Double,
        recorder: AnimationCompletionRecorder
    ) {
        sample(harness, at: time)
        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: completionTransaction(
                animation: animation,
                label: label,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
    }

    private func sample(
        _ harness: AnimatableAttributeHarness,
        at time: Double
    ) {
        harness.advanceTime(to: time)
        _ = harness.currentValue()
    }
}
