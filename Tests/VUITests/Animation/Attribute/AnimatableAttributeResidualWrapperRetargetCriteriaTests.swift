import XCTest
@testable import VUI

final class AnimatableAttributeResidualWrapperRetargetCriteriaTests: XCTestCase {
    func testFiniteOldRetargetedToResidualWrappersKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.oldLinear,
            oldRole: "firstLinear",
            replacementAnimation: Self.fluidDelay,
            replacementRole: "secondFluidDelay",
            expectedEvents: [
                "firstLinearLogical",
                "secondFluidDelayLogical",
                "firstLinearRemoved",
                "secondFluidDelayRemoved",
            ],
            label: "linearToFluidDelay"
        )
        assertRetargetOrder(
            oldAnimation: Self.oldLinear,
            oldRole: "firstLinear",
            replacementAnimation: Self.fluidRepeat,
            replacementRole: "secondFluidRepeat",
            expectedEvents: [
                "secondFluidRepeatLogical",
                "firstLinearLogical",
                "firstLinearRemoved",
                "secondFluidRepeatRemoved",
            ],
            label: "linearToFluidRepeat"
        )
        assertRetargetOrder(
            oldAnimation: Self.oldLinear,
            oldRole: "firstLinear",
            replacementAnimation: Self.fluidSpeed,
            replacementRole: "secondFluidSpeed",
            expectedEvents: [
                "firstLinearLogical",
                "secondFluidSpeedLogical",
                "firstLinearRemoved",
                "secondFluidSpeedRemoved",
            ],
            label: "linearToFluidSpeed"
        )
    }

    func testResidualWrappersRetargetedToFiniteOrDirectSpringKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.fluidDelay,
            oldRole: "firstFluidDelay",
            replacementAnimation: Self.shortLinear,
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstFluidDelayRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstFluidDelayLogical",
            ],
            label: "fluidDelayToLinear"
        )
        assertRetargetOrder(
            oldAnimation: Self.fluidDelay,
            oldRole: "firstFluidDelay",
            replacementAnimation: Self.fastSpring,
            replacementRole: "secondFastSpring",
            expectedEvents: [
                "firstFluidDelayLogical",
                "secondFastSpringLogical",
                "firstFluidDelayRemoved",
                "secondFastSpringRemoved",
            ],
            label: "fluidDelayToFastSpring"
        )
        assertRetargetOrder(
            oldAnimation: Self.fluidSpeed,
            oldRole: "firstFluidSpeed",
            replacementAnimation: Self.shortLinear,
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstFluidSpeedRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstFluidSpeedLogical",
            ],
            label: "fluidSpeedToLinear"
        )
        assertRetargetOrder(
            oldAnimation: Self.fluidSpeed,
            oldRole: "firstFluidSpeed",
            replacementAnimation: Self.fastSpring,
            replacementRole: "secondFastSpring",
            expectedEvents: [
                "firstFluidSpeedLogical",
                "secondFastSpringLogical",
                "firstFluidSpeedRemoved",
                "secondFastSpringRemoved",
            ],
            label: "fluidSpeedToFastSpring"
        )
    }

    func testDirectResidualFamiliesRetargetedToResidualWrappersKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.fluidDelay,
            replacementRole: "secondFluidDelay",
            expectedEvents: [
                "firstDefaultLogical",
                "secondFluidDelayLogical",
                "firstDefaultRemoved",
                "secondFluidDelayRemoved",
            ],
            label: "defaultToFluidDelay"
        )
        assertRetargetOrder(
            oldAnimation: Self.slowFluidSpring,
            oldRole: "firstSlowFluid",
            replacementAnimation: Self.fluidDelay,
            replacementRole: "secondFluidDelay",
            expectedEvents: [
                "secondFluidDelayLogical",
                "firstSlowFluidLogical",
                "firstSlowFluidRemoved",
                "secondFluidDelayRemoved",
            ],
            label: "slowFluidToFluidDelay"
        )
        assertRetargetOrder(
            oldAnimation: Self.fastSpring,
            oldRole: "firstSpring",
            replacementAnimation: Self.springDelay,
            replacementRole: "secondSpringDelay",
            expectedEvents: [
                "firstSpringLogical",
                "secondSpringDelayLogical",
                "firstSpringRemoved",
                "secondSpringDelayRemoved",
            ],
            label: "springToSpringDelay"
        )
    }

    private func assertRetargetOrder(
        oldAnimation: Animation,
        oldRole: String,
        replacementAnimation: Animation,
        replacementRole: String,
        expectedEvents: [String],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.15
        let target = -0.5
        let frame = min(
            oldAnimation.box.defaultDisplayFrameInterval,
            replacementAnimation.box.defaultDisplayFrameInterval
        )

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: criteriaTransaction(
                animation: oldAnimation,
                role: oldRole,
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: retargetTime)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: criteriaTransaction(
                animation: replacementAnimation,
                role: replacementRole,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        let oldEnd = max(
            oldAnimation.box.duration,
            oldAnimation.box.terminalSamplingHorizon(for: 1.0)
        )
        let replacementEnd = retargetTime + max(
            replacementAnimation.box.duration,
            replacementAnimation.box.terminalSamplingHorizon(for: target - retargetStartValue)
        )
        let lastSampleTime = max(oldEnd, replacementEnd) + 2.0

        var sampleTime = retargetTime + frame
        while sampleTime <= lastSampleTime && recorder.events.count < expectedEvents.count {
            harness.advanceTime(to: sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            sampleTime += frame
        }

        XCTAssertEqual(recorder.events, expectedEvents, label, file: file, line: line)
    }

    private func criteriaTransaction(
        animation: Animation,
        role: String,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("\(role)Logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("\(role)Removed")
        }
        return transaction
    }

    private static var oldLinear: Animation {
        .linear(duration: 0.65)
    }

    private static var shortLinear: Animation {
        .linear(duration: 0.25)
    }

    private static var fluidSpring: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var slowFluidSpring: Animation {
        .spring(
            response: 1.20,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var fluidDelay: Animation {
        fluidSpring.delay(0.20)
    }

    private static var fluidSpeed: Animation {
        fluidSpring.speed(0.5)
    }

    private static var fluidRepeat: Animation {
        fluidSpring.repeatCount(2, autoreverses: false)
    }

    private static var fastSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }

    private static var springDelay: Animation {
        fastSpring.delay(0.20)
    }
}
