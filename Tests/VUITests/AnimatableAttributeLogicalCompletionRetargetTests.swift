import XCTest
@testable import VUI

final class AnimatableAttributeLogicalCompletionRetargetTests: XCTestCase {
    func testLogicalCompletionWrapperDirectRetargetCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Animation.linear(duration: 0.90).logicallyComplete(after: 0.55),
            oldRole: "firstLogical",
            replacementAnimation: .linear(duration: 0.20),
            replacementRole: "secondLinear",
            retargetTime: 0.20,
            expectedEvents: [
                "firstLogicalRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstLogicalLogical",
            ],
            label: "logicalOldToLinear"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            oldRole: "firstLinear",
            replacementAnimation: Animation.linear(duration: 0.60).logicallyComplete(after: 0.25),
            replacementRole: "secondLogical",
            retargetTime: 0.20,
            expectedEvents: [
                "secondLogicalLogical",
                "firstLinearRemoved",
                "secondLogicalRemoved",
                "firstLinearLogical",
            ],
            label: "linearToLogicalReplacement"
        )
        assertRetargetOrder(
            oldAnimation: Animation.default.logicallyComplete(after: 0.25),
            oldRole: "firstLogicalDefault",
            replacementAnimation: .linear(duration: 0.20),
            replacementRole: "secondLinear",
            retargetTime: 0.20,
            expectedEvents: [
                "firstLogicalDefaultLogical",
                "firstLogicalDefaultRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
            ],
            label: "logicalDefaultOldToLinear"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Animation.default.logicallyComplete(after: 0.25),
            replacementRole: "secondLogicalDefault",
            retargetTime: 0.20,
            expectedEvents: [
                "secondLogicalDefaultLogical",
                "firstDefaultLogical",
                "firstDefaultRemoved",
                "secondLogicalDefaultRemoved",
            ],
            label: "defaultToLogicalReplacement"
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
            transaction: completionTransaction(
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
            transaction: completionTransaction(
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

    private func completionTransaction(
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
}
