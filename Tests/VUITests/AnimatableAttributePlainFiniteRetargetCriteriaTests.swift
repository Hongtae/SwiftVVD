import XCTest
@testable import VUI

final class AnimatableAttributePlainFiniteRetargetCriteriaTests: XCTestCase {
    func testPlainFiniteLinearRetargetCriteriaMovement() {
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            oldRole: "firstLongLinear",
            replacementAnimation: .linear(duration: 0.35),
            replacementRole: "secondShortLinear",
            retargetTime: 0.20,
            expectedEvents: [
                "firstLongLinearRemoved",
                "secondShortLinearRemoved",
                "secondShortLinearLogical",
                "firstLongLinearLogical",
            ],
            label: "longLinearToShortLinear"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.35),
            oldRole: "firstShortLinear",
            replacementAnimation: .linear(duration: 0.80),
            replacementRole: "secondLongLinear",
            retargetTime: 0.20,
            expectedEvents: [
                "firstShortLinearLogical",
                "firstShortLinearRemoved",
                "secondLongLinearRemoved",
                "secondLongLinearLogical",
            ],
            label: "shortLinearToLongLinear"
        )
    }

    func testPlainFiniteBezierRetargetCriteriaMovement() {
        assertRetargetOrder(
            oldAnimation: Self.longBezier,
            oldRole: "firstLongBezier",
            replacementAnimation: .linear(duration: 0.35),
            replacementRole: "secondShortLinear",
            retargetTime: 0.20,
            expectedEvents: [
                "firstLongBezierRemoved",
                "secondShortLinearRemoved",
                "secondShortLinearLogical",
                "firstLongBezierLogical",
            ],
            label: "bezierToLinear"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.35),
            oldRole: "firstShortLinear",
            replacementAnimation: Self.longBezier,
            replacementRole: "secondLongBezier",
            retargetTime: 0.20,
            expectedEvents: [
                "firstShortLinearLogical",
                "firstShortLinearRemoved",
                "secondLongBezierRemoved",
                "secondLongBezierLogical",
            ],
            label: "linearToBezier"
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

        let oldEnd = oldAnimation.box.duration
        let replacementEnd = retargetTime + replacementAnimation.box.duration
        let lastSampleTime = max(oldEnd, replacementEnd) + 1.0

        var sampleTime = retargetTime + frame
        while sampleTime <= lastSampleTime && recorder.events.count < expectedEvents.count {
            let previousEventCount = recorder.events.count
            harness.setTime(sampleTime)
            let sampledValue = harness.currentValue().opacity
            harness.flushCompletionActions()
            let newEvents = recorder.events.dropFirst(previousEventCount)
            if newEvents.contains(where: { $0.hasSuffix("Removed") }) {
                XCTAssertEqual(
                    sampledValue,
                    target,
                    accuracy: 0.000_001,
                    label,
                    file: file,
                    line: line
                )
            }
            sampleTime += frame
        }

        XCTAssertEqual(recorder.events, expectedEvents, label, file: file, line: line)
        XCTAssertNotEqual(retargetStartValue, target, label, file: file, line: line)
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

    private static var longBezier: Animation {
        .timingCurve(0.25, 0.10, 0.25, 1.0, duration: 0.90)
    }
}
