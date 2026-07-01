import XCTest
@testable import VUI

final class AnimatableAttributeDefaultSpringRetargetCriteriaTests: XCTestCase {
    func testDefaultRetargetedToDirectSpringKeepsOldLogicalBeforeReplacementLogical() {
        assertDefaultSpringRetarget(
            oldAnimation: .default,
            replacementAnimation: Self.fastSpring,
            label: "defaultToFastSpring",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testFastDirectSpringRetargetedToDefaultKeepsOldLogicalBeforeReplacementLogical() {
        assertDefaultSpringRetarget(
            oldAnimation: Self.fastSpring,
            replacementAnimation: .default,
            label: "fastSpringToDefault",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSlowDirectSpringRetargetedToDefaultClampsOldLogicalToFinalSnap() {
        assertDefaultSpringRetarget(
            oldAnimation: Self.slowSpring,
            replacementAnimation: .default,
            label: "slowSpringToDefault",
            logicalOrdering: .replacementBeforeClampedOld,
            expectedFinalEvents: [
                "replacement logical",
                "old removed",
                "replacement removed",
                "old logical",
            ]
        )
    }

    private enum LogicalOrdering {
        case oldBeforeReplacement
        case replacementBeforeClampedOld
    }

    private func assertDefaultSpringRetarget(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        label: String,
        logicalOrdering: LogicalOrdering,
        expectedFinalEvents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25
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

        let oldLogical = oldAnimation.box.duration
        let replacementLogical = retargetTime + replacementAnimation.box.duration
        let replacementFinal = retargetTime + replacementAnimation.box.presentationDuration(
            for: target - retargetStartValue
        )
        XCTAssertLessThan(replacementLogical, replacementFinal, label, file: file, line: line)

        switch logicalOrdering {
        case .oldBeforeReplacement:
            XCTAssertLessThan(oldLogical, replacementLogical, label, file: file, line: line)
            harness.setTime(oldLogical + frame)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, ["old logical"], label, file: file, line: line)

            harness.setTime(replacementLogical + frame)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                recorder.events,
                [
                    "old logical",
                    "replacement logical",
                ],
                label,
                file: file,
                line: line
            )
        case .replacementBeforeClampedOld:
            XCTAssertGreaterThan(oldLogical, replacementFinal, label, file: file, line: line)
            harness.setTime(replacementLogical + frame)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, ["replacement logical"], label, file: file, line: line)

            harness.setTime((replacementLogical + replacementFinal) / 2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, ["replacement logical"], label, file: file, line: line)
        }

        var snappedValue: Double?
        var sampleTime = replacementFinal + frame
        let lastSampleTime = replacementFinal + 2.0
        while sampleTime <= lastSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.contains("replacement removed") {
                snappedValue = value
                break
            }
            sampleTime += frame
        }
        guard let snappedValue else {
            XCTFail("\(label) did not reach replacement final snap", file: file, line: line)
            return
        }
        XCTAssertEqual(snappedValue, target, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(recorder.events, expectedFinalEvents, label, file: file, line: line)
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
}
