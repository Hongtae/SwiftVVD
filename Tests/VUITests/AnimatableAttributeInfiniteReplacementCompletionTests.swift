import XCTest
@testable import VUI

final class AnimatableAttributeInfiniteReplacementCompletionTests: XCTestCase {
    func testResidualDelayWrapperOldLogicalSurvivesRepeatForeverReplacement() {
        assertResidualWrapperToInfiniteReplacement(
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
            pendingSampleTime: 2.00
        )
    }

    func testResidualSpeedWrapperOldLogicalSurvivesSpeedZeroReplacement() {
        assertResidualWrapperToInfiniteReplacement(
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
            pendingSampleTime: 3.20
        )
    }

    private func assertResidualWrapperToInfiniteReplacement(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        oldLabel: String,
        replacementLabel: String,
        logicalSampleTime: Double,
        pendingSampleTime: Double,
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
        XCTAssertEqual(recorder.events, ["\(oldLabel) logical"], file: file, line: line)

        harness.setTime(pendingSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["\(oldLabel) logical"], file: file, line: line)
    }
}
