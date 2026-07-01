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

    func testFiniteRepeatOldRecordsStayPendingWithSpeedZeroReplacement() {
        assertOldAnimationToInfiniteReplacement(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatCount(2, autoreverses: false),
            replacementAnimation: Animation.linear(duration: 0.30).speed(0),
            oldLabel: "old repeat",
            replacementLabel: "speedZero",
            logicalSampleTime: 0.55,
            pendingSampleTime: 1.20,
            expectedEventsAfterLogicalSample: []
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

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setTime(0.35)
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

        harness.setTime(logicalSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expectedEventsAfterLogicalSample, file: file, line: line)

        harness.setTime(pendingSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expectedEventsAfterLogicalSample, file: file, line: line)
    }
}
