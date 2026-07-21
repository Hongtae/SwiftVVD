import XCTest
@testable import VUI

final class AnimatableAttributeInfiniteWrapperPresentationRetargetTests: XCTestCase {
    func testRepeatForeverOldRetargetedToFluidSpringStartsFromCycleValue() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.37

        start(
            harness,
            animation: repeatForever,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 1.0)

        retarget(
            harness,
            animation: fluidSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.10)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart - 0.45)
        XCTAssertLessThan(earlyReplacement, 0.10)

        harness.setTime(retargetTime + 0.60)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testRepeatForeverOldRetargetedToDirectSpringKeepsCycleContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.37

        start(
            harness,
            animation: repeatForever,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 1.0)

        retarget(
            harness,
            animation: directSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.04)
        let cycleHigh = harness.currentValue().opacity
        XCTAssertGreaterThan(cycleHigh, retargetStart)

        harness.setTime(retargetTime + 0.08)
        let cycleDrop = harness.currentValue().opacity
        XCTAssertLessThan(cycleDrop, 0.15)

        harness.setTime(retargetTime + 0.25)
        let replacementProgress = harness.currentValue().opacity
        XCTAssertLessThan(replacementProgress, -0.30)
    }

    func testLinearRetargetedToRepeatForeverRepeatsTargetHittingCycles() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(
            harness,
            animation: Animation.linear(duration: 0.80),
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.15)
        XCTAssertLessThan(retargetStart, 0.40)

        retarget(
            harness,
            animation: repeatForever,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.19)
        XCTAssertLessThan(harness.currentValue().opacity, -0.45)

        harness.setTime(retargetTime + 0.24)
        let restartedCycle = harness.currentValue().opacity
        XCTAssertGreaterThan(restartedCycle, 0.25)

        harness.setTime(retargetTime + 0.41)
        let laterRestartedCycle = harness.currentValue().opacity
        XCTAssertGreaterThan(laterRestartedCycle, 0.25)
    }

    private func start(
        _ harness: AnimatableAttributeHarness,
        animation: Animation,
        target: Double
    ) {
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: Transaction(animation: animation)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()
    }

    private func retarget(
        _ harness: AnimatableAttributeHarness,
        animation: Animation,
        target: Double
    ) {
        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: Transaction(animation: animation)
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
    }

    private func sampleFrames(
        _ harness: AnimatableAttributeHarness,
        through endTime: Double
    ) {
        var time = 1.0 / 60.0
        while time <= endTime {
            harness.setTime(time)
            _ = harness.currentValue()
            time += 1.0 / 60.0
        }
    }

    private var repeatForever: Animation {
        .linear(duration: 0.20).repeatForever(autoreverses: false)
    }

    private var fluidSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0)
    }

    private var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }
}
