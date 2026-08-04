import XCTest
@testable import VUI

final class AnimatableAttributeInfiniteReplacementCompletionTests: XCTestCase {
    func testFiniteLinearOldLogicalSurvivesRepeatForeverReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.linear(duration: 0.50),
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old linear",
            replacementLabel: "repeatForever",
            logicalSampleTime: 0.55,
            pendingSampleTime: 1.20,
            expectedEventsAfterLogicalSample: ["old linear logical"]
        )
    }

    func testDefaultSpringAndBezierOldLogicalSurvivesRepeatForeverReplacement() {
        let oldDefault = Animation.default
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldDefault,
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old default",
            replacementLabel: "repeatForever",
            logicalSampleTime: oldDefault.box.duration + oldDefault.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.80,
            expectedEventsAfterLogicalSample: ["old default logical"]
        )

        let oldSpring = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldSpring,
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old spring",
            replacementLabel: "repeatForever",
            logicalSampleTime: oldSpring.box.duration + oldSpring.box.defaultDisplayFrameInterval,
            pendingSampleTime: 2.00,
            expectedEventsAfterLogicalSample: ["old spring logical"]
        )

        let oldBezier = Animation.timingCurve(0.10, 0.80, 0.20, 1.0, duration: 0.65)
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldBezier,
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old bezier",
            replacementLabel: "repeatForever",
            logicalSampleTime: oldBezier.box.duration + oldBezier.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.80,
            expectedEventsAfterLogicalSample: ["old bezier logical"]
        )
    }

    func testDirectFluidSpringOldLogicalSurvivesSpeedZeroReplacement() {
        let oldFluid = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0
        )
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldFluid,
            replacementAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "old fluid",
            replacementLabel: "speedZero",
            retargetTime: 0.20,
            logicalSampleTime: oldFluid.box.duration + oldFluid.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.40,
            expectedEventsAfterLogicalSample: ["old fluid logical"]
        )
    }

    func testFluidSpringAliasOldLogicalSurvivesInfiniteReplacement() {
        let oldSnappy = Animation.snappy(duration: 0.35, extraBounce: 0.05)
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldSnappy,
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old snappy",
            replacementLabel: "repeatForever",
            retargetTime: 0.20,
            logicalSampleTime: oldSnappy.box.duration + oldSnappy.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.80,
            expectedEventsAfterLogicalSample: ["old snappy logical"]
        )

        let oldBouncy = Animation.bouncy(duration: 0.35, extraBounce: 0.05)
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldBouncy,
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old bouncy",
            replacementLabel: "speedZero",
            retargetTime: 0.20,
            logicalSampleTime: oldBouncy.box.duration + oldBouncy.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.80,
            expectedEventsAfterLogicalSample: ["old bouncy logical"]
        )
    }

    func testFiniteDelayAndSpeedOldLogicalSurvivesInfiniteReplacement() {
        let oldDelay = Animation.linear(duration: 0.30).delay(0.20)
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldDelay,
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old delay",
            replacementLabel: "repeatForever",
            logicalSampleTime: oldDelay.box.duration + oldDelay.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.80,
            expectedEventsAfterLogicalSample: ["old delay logical"]
        )

        let oldSpeed = Animation.linear(duration: 0.60).speed(2.0)
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: oldSpeed,
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old speed",
            replacementLabel: "speedZero",
            retargetTime: 0.10,
            logicalSampleTime: oldSpeed.box.duration + oldSpeed.box.defaultDisplayFrameInterval,
            pendingSampleTime: 1.40,
            expectedEventsAfterLogicalSample: ["old speed logical"]
        )
    }

    func testFiniteRepeatOldLogicalDrainsWithSpeedZeroReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatCount(2, autoreverses: false),
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old repeat",
            replacementLabel: "speedZero",
            logicalSampleTime: 0.55,
            pendingSampleTime: 1.20,
            expectedEventsAfterLogicalSample: ["old repeat logical"]
        )
    }

    func testResidualDelayWrapperOldLogicalSurvivesRepeatForeverReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ).delay(0.20),
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old delay",
            replacementLabel: "repeatForever",
            logicalSampleTime: 0.90,
            pendingSampleTime: 2.00,
            expectedEventsAfterLogicalSample: ["old delay logical"]
        )
    }

    func testResidualSpeedWrapperOldLogicalSurvivesSpeedZeroReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.interpolatingSpring(
                mass: 1.0,
                stiffness: 100,
                damping: 10,
                initialVelocity: 0
            ).speed(0.5),
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old speed",
            replacementLabel: "speedZero",
            logicalSampleTime: 2.20,
            pendingSampleTime: 3.20,
            expectedEventsAfterLogicalSample: ["old speed logical"]
        )
    }

    func testResidualSpringRepeatOldLogicalSurvivesRepeatForeverReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.interpolatingSpring(
                mass: 1.0,
                stiffness: 100,
                damping: 10,
                initialVelocity: 0
            ).repeatCount(2, autoreverses: false),
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old spring repeat",
            replacementLabel: "repeatForever",
            logicalSampleTime: 1.40,
            pendingSampleTime: 3.20,
            expectedEventsAfterLogicalSample: ["old spring repeat logical"]
        )
    }

    func testResidualDefaultDelayOldLogicalSurvivesSpeedZeroReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.default.delay(0.20),
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old default delay",
            replacementLabel: "speedZero",
            logicalSampleTime: 0.90,
            pendingSampleTime: 2.00,
            expectedEventsAfterLogicalSample: ["old default delay logical"]
        )
    }

    func testResidualFluidSpeedOldLogicalSurvivesSpeedZeroReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ).speed(0.5),
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old fluid speed",
            replacementLabel: "speedZero",
            logicalSampleTime: 1.40,
            pendingSampleTime: 3.20,
            expectedEventsAfterLogicalSample: ["old fluid speed logical"]
        )
    }

    func testResidualSpringDelayOldLogicalSurvivesRepeatForeverReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.interpolatingSpring(
                mass: 1.0,
                stiffness: 100,
                damping: 10,
                initialVelocity: 0
            ).delay(0.20),
            replacementAnimation: Animation.linear(duration: 0.30)
                .repeatForever(autoreverses: false),
            oldLabel: "old spring delay",
            replacementLabel: "repeatForever",
            logicalSampleTime: 1.40,
            pendingSampleTime: 3.20,
            expectedEventsAfterLogicalSample: ["old spring delay logical"]
        )
    }

    private func assertOldAnimationToInfiniteReplacement(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        oldLabel: String,
        replacementLabel: String,
        retargetTime: Double = 0.35,
        logicalSampleTime: Double,
        pendingSampleTime: Double,
        expectedEventsAfterLogicalSample: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: oldLabel,
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()

        harness.advanceTime(to: max(0, retargetTime - 0.10))
        _ = harness.currentValue()
        harness.advanceTime(to: retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.75),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: replacementLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.advanceTime(to: logicalSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expectedEventsAfterLogicalSample, file: file, line: line)

        harness.advanceTime(to: pendingSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expectedEventsAfterLogicalSample, file: file, line: line)
    }
}
