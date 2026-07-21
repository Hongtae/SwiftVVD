import XCTest
@testable import VUI

final class AnimatableAttributeFiniteSpringRetargetCompletionTests: XCTestCase {
    func testFiniteOldRetargetedToDirectSpringMovesRemovedToSpringFinalSnap() {
        assertFiniteToSpringRetarget(
            oldAnimation: .linear(duration: 0.90),
            replacementAnimation: Self.fastSpring,
            label: "linearToSpring"
        )
        assertFiniteToSpringRetarget(
            oldAnimation: .linear(duration: 0.65).delay(0.25),
            replacementAnimation: Self.fastSpring,
            label: "delayToSpring"
        )
        assertFiniteToSpringRetarget(
            oldAnimation: .linear(duration: 0.90),
            replacementAnimation: Self.fastSpringValueAnimation,
            label: "linearToSpringValue"
        )
    }

    func testDirectSpringRetargetedToFiniteDelayGroupsAtFiniteBoundary() {
        assertSpringToFiniteDelayRetarget(
            oldAnimation: Self.slowSpring,
            label: "springToDelay"
        )
        assertSpringToFiniteDelayRetarget(
            oldAnimation: Self.slowDurationSpring,
            label: "durationSpringToDelay"
        )
    }

    private func assertSpringToFiniteDelayRetarget(
        oldAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let replacementAnimation = Animation.linear(duration: 0.25).delay(0.30)
        let retargetTime = 0.25

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: "replacement",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        let replacementBoundary = retargetTime + replacementAnimation.box.duration
        harness.setTime(replacementBoundary - replacementAnimation.box.defaultDisplayFrameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setTime(replacementBoundary + replacementAnimation.box.defaultDisplayFrameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ],
            label,
            file: file,
            line: line
        )
    }

    private func assertFiniteToSpringRetarget(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25
        let target = -0.5

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setTime(retargetTime)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: completionTransaction(
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
        let oldLogical = oldAnimation.box.duration
        let replacementFinal = retargetTime + replacementAnimation.box.presentationDuration(
            for: target - retargetStartValue
        )
        XCTAssertLessThan(replacementLogical, oldLogical, label, file: file, line: line)
        XCTAssertLessThan(oldLogical, replacementFinal, label, file: file, line: line)

        harness.setTime((replacementLogical + oldLogical) / 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["replacement logical"], label, file: file, line: line)

        harness.setTime((oldLogical + replacementFinal) / 2)
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

        var sampleTime = replacementFinal + replacementAnimation.box.defaultDisplayFrameInterval
        let lastSampleTime = replacementFinal + 1.0
        while sampleTime <= lastSampleTime {
            harness.setTime(sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            if recorder.events.contains("replacement removed") {
                break
            }
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }
        XCTAssertEqual(
            recorder.events,
            [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ],
            label,
            file: file,
            line: line
        )
    }

    private static var fastSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
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

    private static var fastSpringValueAnimation: Animation {
        .interpolatingSpring(
            Spring(mass: 1.0, stiffness: 100.0, damping: 10.0),
            initialVelocity: 0.0
        )
    }

    private static var slowDurationSpring: Animation {
        .interpolatingSpring(duration: 1.20, bounce: 0.0, initialVelocity: 0.0)
    }
}
