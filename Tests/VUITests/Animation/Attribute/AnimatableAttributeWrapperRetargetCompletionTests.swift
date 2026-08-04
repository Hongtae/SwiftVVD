import XCTest
@testable import VUI

final class AnimatableAttributeWrapperRetargetCompletionTests: XCTestCase {
    func testFiniteWrappersRetargetedToFluidSpringCompleteReplacementBeforeOldWrapper() {
        assertFiniteWrapperToFluidRetarget(
            oldAnimation: Animation.linear(duration: 0.80).delay(0.40),
            label: "delayToFluid"
        )
        assertFiniteWrapperToFluidRetarget(
            oldAnimation: Animation.linear(duration: 0.40)
                .repeatCount(3, autoreverses: false),
            label: "repeatToFluid"
        )
        assertFiniteWrapperToFluidRetarget(
            oldAnimation: Animation.linear(duration: 0.60).speed(0.5),
            label: "speedSlowToFluid"
        )
    }

    func testFluidSpringRetargetedToFiniteWrappersGroupsAtReplacementBoundary() {
        assertGroupedAtFiniteReplacementBoundary(
            oldAnimation: Self.longFluidSpring,
            replacementAnimation: Animation.linear(duration: 0.25).delay(0.30),
            label: "fluidToDelay"
        )
        assertGroupedAtFiniteReplacementBoundary(
            oldAnimation: Self.longFluidSpring,
            replacementAnimation: Animation.linear(duration: 0.20)
                .repeatCount(3, autoreverses: false),
            label: "fluidToRepeat"
        )
    }

    func testSlowDirectSpringRetargetedToFiniteReplacementsGroupsAtReplacementBoundary() {
        assertGroupedAtFiniteReplacementBoundary(
            oldAnimation: Self.slowSpring,
            replacementAnimation: .linear(duration: 0.55),
            label: "interpolatingToLinear"
        )
        assertGroupedAtFiniteReplacementBoundary(
            oldAnimation: Self.slowSpring,
            replacementAnimation: Animation.linear(duration: 0.25).delay(0.30),
            label: "interpolatingToDelay"
        )
    }

    private func assertFiniteWrapperToFluidRetarget(
        oldAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let replacementAnimation = Self.fastFluidSpring
        let retargetTime = 0.25
        let target = -0.5
        let frame = replacementAnimation.box.defaultDisplayFrameInterval

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: retargetTime)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: logicalCompletionTransaction(
                animation: replacementAnimation,
                label: "replacement",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        let replacementLogical = retargetTime + replacementAnimation.box.duration
        let replacementFinal = retargetTime + replacementAnimation.box.terminalSamplingHorizon(
            for: target - retargetStartValue
        )
        XCTAssertLessThan(replacementLogical, replacementFinal, label, file: file, line: line)

        harness.advanceTime(to: replacementLogical + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["replacement logical"], label, file: file, line: line)

        harness.advanceTime(to: replacementFinal + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement logical",
                "old logical",
            ],
            label,
            file: file,
            line: line
        )
    }

    private func assertGroupedAtFiniteReplacementBoundary(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = makeRetargetedHarness(
            oldAnimation: oldAnimation,
            replacementAnimation: replacementAnimation,
            retargetTime: 0.25,
            recorder: recorder,
            file: file,
            line: line
        )
        let retargetTime = 0.25
        let frame = replacementAnimation.box.defaultDisplayFrameInterval
        let replacementBoundary = retargetTime + replacementAnimation.box.duration

        XCTAssertGreaterThan(
            oldAnimation.box.duration,
            replacementBoundary,
            label,
            file: file,
            line: line
        )

        harness.advanceTime(to: replacementBoundary - frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: replacementBoundary + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(Set(recorder.events), ["old logical", "replacement logical"], label, file: file, line: line)
        XCTAssertEqual(recorder.events.count, 2, label, file: file, line: line)
    }

    private func makeRetargetedHarness(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        retargetTime: TimeInterval,
        recorder: AnimationCompletionRecorder,
        file: StaticString,
        line: UInt
    ) -> AnimatableAttributeHarness {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.advanceTime(to: retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: replacementAnimation,
                label: "replacement",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)
        return harness
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

    private static var fastFluidSpring: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var longFluidSpring: Animation {
        .spring(
            response: 1.20,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var slowSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 25.0,
            damping: 5.0,
            initialVelocity: 0.0
        )
    }
}
