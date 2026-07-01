import XCTest
@testable import VUI

final class AnimatableAttributeResidualSpringCrossRetargetCompletionTests: XCTestCase {
    func testFluidSpringOldRetargetedToDirectSpringKeepsOldLogicalBeforeFinalSnap() {
        assertResidualCrossRetarget(
            oldAnimation: Self.slowFluidSpring,
            replacementAnimation: Self.fastSpring,
            label: "fluidToFastSpring",
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldLogical: [
                "replacement logical",
                "old logical",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testDirectSpringOldRetargetedToFluidSpringKeepsEarlierOldLogicalBeforeFinalSnap() {
        assertResidualCrossRetarget(
            oldAnimation: Self.fastSpring,
            replacementAnimation: Self.fastFluidSpring,
            label: "fastSpringToFluid",
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldLogical: [
                "replacement logical",
                "old logical",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSlowDirectSpringOldRetargetedToFluidSpringClampsOldLogicalToFinalSnap() {
        assertResidualCrossRetarget(
            oldAnimation: Self.slowSpring,
            replacementAnimation: Self.fastFluidSpring,
            label: "slowSpringToFluid",
            expectedEventsAfterReplacementLogical: ["replacement logical"],
            expectedEventsAfterOldLogical: nil,
            expectedFinalEvents: [
                "replacement logical",
                "old removed",
                "replacement removed",
                "old logical",
            ]
        )
    }

    private func assertResidualCrossRetarget(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        label: String,
        expectedEventsAfterReplacementLogical: [String],
        expectedEventsAfterOldLogical: [String]?,
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
        let frame = replacementAnimation.box.defaultDisplayFrameInterval

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
        XCTAssertLessThan(replacementLogical, replacementFinal, label, file: file, line: line)

        harness.setTime(replacementLogical + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expectedEventsAfterReplacementLogical, label, file: file, line: line)

        if let expectedEventsAfterOldLogical {
            XCTAssertLessThan(oldLogical, replacementFinal, label, file: file, line: line)
            harness.setTime(oldLogical + frame)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, expectedEventsAfterOldLogical, label, file: file, line: line)
        } else {
            XCTAssertGreaterThan(oldLogical, replacementFinal, label, file: file, line: line)
            harness.setTime((replacementLogical + replacementFinal) / 2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, expectedEventsAfterReplacementLogical, label, file: file, line: line)
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

    private static var fastFluidSpring: Animation {
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
}
