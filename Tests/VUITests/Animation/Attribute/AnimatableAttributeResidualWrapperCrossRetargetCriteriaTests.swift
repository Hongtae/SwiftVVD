import XCTest
@testable import VUI

final class AnimatableAttributeResidualWrapperCrossRetargetCriteriaTests: XCTestCase {
    func testFluidSpringWrappersRetargetedAcrossResidualWrappersKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.fluidDelay,
            oldRole: "firstFluidDelay",
            replacementAnimation: Self.fluidRepeat,
            replacementRole: "secondFluidRepeat",
            expectedEvents: [
                "secondFluidRepeatLogical",
                "firstFluidDelayLogical",
                "firstFluidDelayRemoved",
                "secondFluidRepeatRemoved",
            ],
            label: "fluidDelayToFluidRepeat"
        )
        assertRetargetOrder(
            oldAnimation: Self.fluidRepeat,
            oldRole: "firstFluidRepeat",
            replacementAnimation: Self.fluidDelay,
            replacementRole: "secondFluidDelay",
            expectedEvents: [
                "firstFluidRepeatLogical",
                "secondFluidDelayLogical",
                "firstFluidRepeatRemoved",
                "secondFluidDelayRemoved",
            ],
            label: "fluidRepeatToFluidDelay"
        )
        assertRetargetOrder(
            oldAnimation: Self.fluidSpeed,
            oldRole: "firstFluidSpeed",
            replacementAnimation: Self.springDelay,
            replacementRole: "secondSpringDelay",
            expectedEvents: [
                "firstFluidSpeedLogical",
                "secondSpringDelayLogical",
                "firstFluidSpeedRemoved",
                "secondSpringDelayRemoved",
            ],
            label: "fluidSpeedToSpringDelay"
        )
    }

    func testDefaultAndDirectSpringWrappersRetargetedAcrossResidualWrappersKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.defaultDelay,
            oldRole: "firstDefaultDelay",
            replacementAnimation: Self.fluidRepeat,
            replacementRole: "secondFluidRepeat",
            expectedEvents: [
                "secondFluidRepeatLogical",
                "firstDefaultDelayLogical",
                "firstDefaultDelayRemoved",
                "secondFluidRepeatRemoved",
            ],
            label: "defaultDelayToFluidRepeat"
        )
        assertRetargetOrder(
            oldAnimation: Self.springRepeat,
            oldRole: "firstSpringRepeat",
            replacementAnimation: Self.defaultDelay,
            replacementRole: "secondDefaultDelay",
            expectedEvents: [
                "firstSpringRepeatLogical",
                "secondDefaultDelayLogical",
                "firstSpringRepeatRemoved",
                "secondDefaultDelayRemoved",
            ],
            label: "springRepeatToDefaultDelay"
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

    private static var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }

    private static var fluidDelay: Animation {
        fluidSpring.delay(0.20)
    }

    private static var fluidRepeat: Animation {
        fluidSpring.repeatCount(2, autoreverses: false)
    }

    private static var fluidSpeed: Animation {
        fluidSpring.speed(0.5)
    }

    private static var springDelay: Animation {
        directSpring.delay(0.20)
    }

    private static var springRepeat: Animation {
        directSpring.repeatCount(2, autoreverses: false)
    }

    private static var defaultDelay: Animation {
        Animation.default.delay(0.20)
    }
}
