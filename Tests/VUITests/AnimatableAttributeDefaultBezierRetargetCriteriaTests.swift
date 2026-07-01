import XCTest
@testable import VUI

final class AnimatableAttributeDefaultBezierRetargetCriteriaTests: XCTestCase {
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
}
