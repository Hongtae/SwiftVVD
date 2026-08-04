import XCTest
@testable import VUI

final class AnimatableAttributeZeroDurationRetargetCriteriaTests: XCTestCase {
    func testZeroDurationRetargetPublishesTargetAndKeepsListenerDrainOrder() {
        assertZeroRetargetOrder(
            oldAnimation: .linear(duration: 0.80),
            replacementAnimation: .linear(duration: 0),
            label: "linearToZero"
        )
        assertZeroRetargetOrder(
            oldAnimation: .spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0.0
            ),
            replacementAnimation: .linear(duration: 0),
            label: "fluidToZero"
        )
        assertZeroRetargetOrder(
            oldAnimation: .linear(duration: 0.80),
            replacementAnimation: .linear(duration: 0.20).delay(-0.20),
            label: "linearToZeroDelay"
        )
        assertZeroRetargetOrder(
            oldAnimation: .linear(duration: 0.80),
            replacementAnimation: .linear(duration: -0.20),
            label: "linearToNegativeLinear"
        )
        assertZeroRetargetOrder(
            oldAnimation: .linear(duration: 0.80),
            replacementAnimation: .timingCurve(.circularEaseInOut, duration: -0.20),
            label: "linearToNegativeCircular"
        )
        assertZeroRetargetOrder(
            oldAnimation: .linear(duration: 0.80),
            replacementAnimation: .interpolatingSpring(
                duration: -0.20,
                bounce: 0.15,
                initialVelocity: 0
            ),
            label: "linearToNegativeInterpolatingSpring"
        )
    }

    private func assertZeroRetargetOrder(
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

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "first",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.advanceTime(to: 0.10)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.20)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        recorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: "zeroRetarget",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.000_001, file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "first removed",
                "zeroRetarget removed",
                "zeroRetarget logical",
                "first logical",
            ],
            label,
            file: file,
            line: line
        )
    }
}
