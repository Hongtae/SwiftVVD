import XCTest
@testable import VUI

final class AnimatableAttributeResidualSameFamilyRetargetCompletionTests: XCTestCase {
    func testDefaultAnimationRetargetPreservesOldLogicalBeforeReplacementLogical() {
        assertResidualSameFamilyRetarget(
            oldAnimation: .default,
            replacementAnimation: .default,
            label: "defaultToDefault",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSlowFluidSpringRetargetedToFastFluidSpringClampsOldLogicalToFinalSnap() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.slowFluidSpring,
            replacementAnimation: Self.fastFluidSpring,
            label: "slowFluidToFastFluid",
            logicalOrdering: .replacementBeforeClampedOld,
            expectedFinalEvents: [
                "replacement logical",
                "old removed",
                "replacement removed",
                "old logical",
            ]
        )
    }

    func testFastFluidSpringRetargetedToSlowFluidSpringPreservesOldLogicalBeforeReplacementLogical() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.fastFluidSpring,
            replacementAnimation: Self.slowFluidSpring,
            label: "fastFluidToSlowFluid",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSlowSmoothRetargetedToFastSnappyClampsOldLogicalToFinalSnap() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.slowSmooth,
            replacementAnimation: Self.fastSnappy,
            label: "slowSmoothToFastSnappy",
            logicalOrdering: .replacementBeforeClampedOld,
            expectedFinalEvents: [
                "replacement logical",
                "old removed",
                "replacement removed",
                "old logical",
            ]
        )
    }

    func testFastBouncyRetargetedToSlowSmoothPreservesOldLogicalBeforeReplacementLogical() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.fastBouncy,
            replacementAnimation: Self.slowSmooth,
            label: "fastBouncyToSlowSmooth",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSlowDirectSpringRetargetedToFastDirectSpringKeepsOldLogicalBeforeFinalSnap() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.slowSpring,
            replacementAnimation: Self.fastSpring,
            label: "slowSpringToFastSpring",
            logicalOrdering: .replacementBeforeOldBeforeFinal,
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testFastDirectSpringRetargetedToSlowDirectSpringPreservesOldLogicalBeforeReplacementLogical() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.fastSpring,
            replacementAnimation: Self.slowSpring,
            label: "fastSpringToSlowSpring",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testDurationSpringRetargetedToSpringValueKeepsOldLogicalBeforeFinalSnap() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.slowDurationSpring,
            replacementAnimation: Self.fastSpringValueAnimation,
            label: "durationToSpringValue",
            logicalOrdering: .replacementBeforeOldBeforeFinal,
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testSpringValueRetargetedToDurationSpringPreservesOldLogicalBeforeReplacementLogical() {
        assertResidualSameFamilyRetarget(
            oldAnimation: Self.fastSpringValueAnimation,
            replacementAnimation: Self.slowDurationSpring,
            label: "springValueToDuration",
            logicalOrdering: .oldBeforeReplacement,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testPropertyAndNoArgFluidSpringAliasesKeepSampledSameFamilyCriteriaOrder() {
        assertResidualSameFamilyRetarget(
            oldAnimation: .spring,
            replacementAnimation: .interactiveSpring,
            label: "springPropertyToInteractiveProperty",
            logicalOrdering: .replacementBeforeOldBeforeFinal,
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
        assertResidualSameFamilyRetarget(
            oldAnimation: .interactiveSpring,
            replacementAnimation: .spring,
            label: "interactivePropertyToSpringProperty",
            logicalOrdering: .oldBeforeRetarget,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
        assertResidualSameFamilyRetarget(
            oldAnimation: .spring(),
            replacementAnimation: .interactiveSpring(),
            label: "springNoArgToInteractiveNoArg",
            logicalOrdering: .replacementBeforeOldBeforeFinal,
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
        assertResidualSameFamilyRetarget(
            oldAnimation: .interactiveSpring(),
            replacementAnimation: .spring(),
            label: "interactiveNoArgToSpringNoArg",
            logicalOrdering: .oldBeforeRetarget,
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    private enum LogicalOrdering {
        case oldBeforeRetarget
        case oldBeforeReplacement
        case replacementBeforeOldBeforeFinal
        case replacementBeforeClampedOld
    }

    private func assertResidualSameFamilyRetarget(
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

        harness.advanceTime(to: retargetTime)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        if logicalOrdering == .oldBeforeRetarget {
            XCTAssertEqual(recorder.events, ["old logical"], label, file: file, line: line)
        } else {
            XCTAssertEqual(recorder.events, [], label, file: file, line: line)
        }

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
        if logicalOrdering == .oldBeforeRetarget {
            XCTAssertEqual(recorder.events, ["old logical"], label, file: file, line: line)
        } else {
            XCTAssertEqual(recorder.events, [], label, file: file, line: line)
        }

        let replacementHorizon = replacementAnimation.box.terminalSamplingHorizon(
            for: target - retargetStartValue
        )
        var snappedValue: Double?
        var sampleTime = retargetTime + frame
        let lastSampleTime =
            retargetTime +
            max(
                replacementHorizon,
                max(
                    oldAnimation.box.duration,
                    replacementAnimation.box.duration
                )
            ) +
            2.0
        while sampleTime <= lastSampleTime {
            harness.advanceTime(to: sampleTime)
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

    private static var slowSmooth: Animation {
        .smooth(duration: 1.50, extraBounce: 0.0)
    }

    private static var fastSnappy: Animation {
        .snappy(duration: 0.25, extraBounce: 0.0)
    }

    private static var fastBouncy: Animation {
        .bouncy(duration: 0.50, extraBounce: 0.0)
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

    private static var slowDurationSpring: Animation {
        .interpolatingSpring(duration: 1.20, bounce: 0.0, initialVelocity: 0.0)
    }

    private static var fastSpringValueAnimation: Animation {
        .interpolatingSpring(
            Spring(mass: 1.0, stiffness: 100.0, damping: 10.0),
            initialVelocity: 0.0
        )
    }
}
