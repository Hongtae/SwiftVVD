import XCTest
@testable import VUI

final class AnimatableAttributeDefaultBezierRetargetCriteriaTests: XCTestCase {
    func testShortEaseLogicalListenerFinishesBeforeDurationSpringReplacement() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let oldAnimation = Animation.easeInOut(duration: 0.55)
        let replacementAnimation = Animation.spring(duration: 0.8, bounce: 0.35)

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        var oldTransaction = Transaction(animation: oldAnimation)
        oldTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "oldEase",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.30)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()

        var replacementTransaction = Transaction(animation: replacementAnimation)
        replacementTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "replacementSpring",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: replacementTransaction
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        recorder.removeAll()

        let frame = min(
            oldAnimation.box.defaultDisplayFrameInterval,
            replacementAnimation.box.defaultDisplayFrameInterval
        )
        let replacementEnd = 0.30 + max(
            replacementAnimation.box.duration,
            replacementAnimation.box.presentationDuration(
                for: -0.5 - retargetStartValue
            )
        )
        var sampleTime = 0.30 + frame
        while sampleTime <= replacementEnd + 1.0,
              recorder.events.count < 2 {
            harness.setTime(sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            sampleTime += frame
        }

        XCTAssertEqual(recorder.events, [
            "oldEase removed",
            "replacementSpring removed",
        ])
    }

    func testDefaultAndBezierRetargetedToFluidSpringKeepSampledCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.fluidReplacement,
            replacementRole: "secondFluid",
            retargetTime: 0.12,
            expectedEvents: [
                "secondFluidLogical",
                "firstDefaultLogical",
                "firstDefaultRemoved",
                "secondFluidRemoved",
            ],
            label: "defaultToFluid"
        )
        assertRetargetOrder(
            oldAnimation: .easeInOut(duration: 0.90),
            oldRole: "firstEase",
            replacementAnimation: Self.fluidReplacement,
            replacementRole: "secondFluid",
            retargetTime: 0.25,
            expectedEvents: [
                "secondFluidLogical",
                "firstEaseRemoved",
                "secondFluidRemoved",
                "firstEaseLogical",
            ],
            label: "easeToFluid"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.snappyAlias,
            replacementRole: "secondSnappy",
            retargetTime: 0.12,
            expectedEvents: [
                "secondSnappyLogical",
                "firstDefaultRemoved",
                "secondSnappyRemoved",
                "firstDefaultLogical",
            ],
            label: "defaultToSnappy"
        )
        assertRetargetOrder(
            oldAnimation: .easeInOut(duration: 0.90),
            oldRole: "firstEase",
            replacementAnimation: Self.snappyAlias,
            replacementRole: "secondSnappy",
            retargetTime: 0.25,
            expectedEvents: [
                "secondSnappyLogical",
                "firstEaseRemoved",
                "secondSnappyRemoved",
                "firstEaseLogical",
            ],
            label: "easeToSnappy"
        )
    }

    func testFluidSpringRetargetedToDefaultAndBezierKeepSampledCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.slowFluid,
            oldRole: "firstFluid",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            retargetTime: 0.25,
            expectedEvents: [
                "secondDefaultLogical",
                "firstFluidRemoved",
                "secondDefaultRemoved",
                "firstFluidLogical",
            ],
            label: "fluidToDefault"
        )
        assertRetargetOrder(
            oldAnimation: Self.slowFluid,
            oldRole: "firstFluid",
            replacementAnimation: .easeInOut(duration: 0.55),
            replacementRole: "secondEase",
            retargetTime: 0.25,
            expectedEvents: [
                "firstFluidRemoved",
                "secondEaseRemoved",
                "secondEaseLogical",
                "firstFluidLogical",
            ],
            label: "fluidToEase"
        )
        assertRetargetOrder(
            oldAnimation: Self.bouncyAlias,
            oldRole: "firstBouncy",
            replacementAnimation: .easeInOut(duration: 0.55),
            replacementRole: "secondEase",
            retargetTime: 0.25,
            expectedEvents: [
                "firstBouncyRemoved",
                "secondEaseRemoved",
                "secondEaseLogical",
                "firstBouncyLogical",
            ],
            label: "bouncyToEase"
        )
        assertRetargetOrder(
            oldAnimation: Self.bouncyAlias,
            oldRole: "firstBouncy",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            retargetTime: 0.25,
            expectedEvents: [
                "secondDefaultLogical",
                "firstBouncyRemoved",
                "secondDefaultRemoved",
                "firstBouncyLogical",
            ],
            label: "bouncyToDefault"
        )
    }

    private func assertRetargetOrder(
        oldAnimation: Animation,
        oldRole: String,
        replacementAnimation: Animation,
        replacementRole: String,
        retargetTime: TimeInterval,
        expectedEvents: [String],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
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

    private static var fluidReplacement: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var slowFluid: Animation {
        .spring(
            response: 1.20,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var snappyAlias: Animation {
        .snappy(duration: 0.15, extraBounce: 0.0)
    }

    private static var bouncyAlias: Animation {
        .bouncy(duration: 1.20, extraBounce: 0.0)
    }
}
