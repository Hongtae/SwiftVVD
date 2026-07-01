import XCTest
@testable import VUI

final class AnimatableAttributeDefaultResidualWrapperRetargetCriteriaTests: XCTestCase {
    func testFiniteOldRetargetedToDefaultDelayKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.oldLinear,
            oldRole: "firstLinear",
            replacementAnimation: Self.defaultDelay,
            replacementRole: "secondDefaultDelay",
            expectedEvents: [
                "firstLinearLogical",
                "secondDefaultDelayLogical",
                "firstLinearRemoved",
                "secondDefaultDelayRemoved",
            ],
            label: "linearToDefaultDelay"
        )
    }

    func testDefaultDelayRetargetedToFiniteOrDirectSpringKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.defaultDelay,
            oldRole: "firstDefaultDelay",
            replacementAnimation: Self.shortLinear,
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstDefaultDelayRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstDefaultDelayLogical",
            ],
            label: "defaultDelayToLinear"
        )
        assertRetargetOrder(
            oldAnimation: Self.defaultDelay,
            oldRole: "firstDefaultDelay",
            replacementAnimation: Self.fastSpring,
            replacementRole: "secondSpring",
            expectedEvents: [
                "firstDefaultDelayLogical",
                "secondSpringLogical",
                "firstDefaultDelayRemoved",
                "secondSpringRemoved",
            ],
            label: "defaultDelayToSpring"
        )
    }

    func testFiniteOldRetargetedToDefaultNestedWrapperKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.oldLinear,
            oldRole: "firstLinear",
            replacementAnimation: Self.defaultDelayRepeat,
            replacementRole: "secondDefaultDelayRepeat",
            expectedEvents: [
                "firstLinearLogical",
                "secondDefaultDelayRepeatLogical",
                "firstLinearRemoved",
                "secondDefaultDelayRepeatRemoved",
            ],
            label: "linearToDefaultDelayRepeat"
        )
    }

    func testDefaultNestedWrappersRetargetedToFiniteOrDefaultKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.defaultDelayRepeat,
            oldRole: "firstDefaultDelayRepeat",
            replacementAnimation: Self.shortLinear,
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstDefaultDelayRepeatRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstDefaultDelayRepeatLogical",
            ],
            label: "defaultDelayRepeatToLinear"
        )
        assertRetargetOrder(
            oldAnimation: Self.defaultRepeatDelay,
            oldRole: "firstDefaultRepeatDelay",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstDefaultRepeatDelayLogical",
                "firstDefaultRepeatDelayRemoved",
                "secondDefaultRemoved",
            ],
            label: "defaultRepeatDelayToDefault"
        )
    }

    func testResidualWrappersRetargetedToPlainDefaultKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.fluidDelay,
            oldRole: "firstFluidDelay",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "firstFluidDelayLogical",
                "secondDefaultLogical",
                "firstFluidDelayRemoved",
                "secondDefaultRemoved",
            ],
            label: "fluidDelayToDefault"
        )
        assertRetargetOrder(
            oldAnimation: Self.springRepeat,
            oldRole: "firstSpringRepeat",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "firstSpringRepeatLogical",
                "secondDefaultLogical",
                "firstSpringRepeatRemoved",
                "secondDefaultRemoved",
            ],
            label: "springRepeatToDefault"
        )
        assertRetargetOrder(
            oldAnimation: Self.defaultRepeat,
            oldRole: "firstDefaultRepeat",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "firstDefaultRepeatLogical",
                "secondDefaultLogical",
                "firstDefaultRepeatRemoved",
                "secondDefaultRemoved",
            ],
            label: "defaultRepeatToDefault"
        )
    }

    func testPlainDefaultRetargetedToDirectSpringWrapperKeepsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.springDelay,
            replacementRole: "secondSpringDelay",
            expectedEvents: [
                "firstDefaultLogical",
                "secondSpringDelayLogical",
                "firstDefaultRemoved",
                "secondSpringDelayRemoved",
            ],
            label: "defaultToSpringDelay"
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

        harness.setTime(retargetTime)
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
            oldAnimation.box.presentationDuration(for: 1.0)
        )
        let replacementEnd = retargetTime + max(
            replacementAnimation.box.duration,
            replacementAnimation.box.presentationDuration(for: target - retargetStartValue)
        )
        let lastSampleTime = max(oldEnd, replacementEnd) + 3.0

        var sampleTime = retargetTime + frame
        while sampleTime <= lastSampleTime && recorder.events.count < expectedEvents.count {
            harness.setTime(sampleTime)
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

    private static var fluidSpring: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
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

    private static var oldLinear: Animation {
        .linear(duration: 0.65)
    }

    private static var shortLinear: Animation {
        .linear(duration: 0.25)
    }

    private static var fluidDelay: Animation {
        fluidSpring.delay(0.20)
    }

    private static var springRepeat: Animation {
        fastSpring.repeatCount(2, autoreverses: false)
    }

    private static var defaultRepeat: Animation {
        Animation.default.repeatCount(2, autoreverses: false)
    }

    private static var defaultDelay: Animation {
        Animation.default.delay(0.20)
    }

    private static var defaultDelayRepeat: Animation {
        Animation.default.delay(0.20).repeatCount(2, autoreverses: false)
    }

    private static var defaultRepeatDelay: Animation {
        Animation.default.repeatCount(2, autoreverses: false).delay(0.20)
    }

    private static var springDelay: Animation {
        fastSpring.delay(0.20)
    }
}
