import XCTest
@testable import VUI

final class AnimatableAttributeFiniteWrapperPresentationRetargetTests: XCTestCase {
    func testPositiveSpeedOldRetargetedToFluidSpringUsesMergePresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: finiteSpeed,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.10)
        XCTAssertLessThan(retargetStart, 0.25)

        retarget(
            harness,
            animation: fluidSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.05)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart - 0.10)
        XCTAssertLessThan(earlyReplacement, 0.05)

        harness.setTime(retargetTime + 0.22)
        XCTAssertLessThan(harness.currentValue().opacity, -0.45)

        harness.setTime(retargetTime + 0.60)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testFiniteRepeatOldRetargetedToFluidSpringUsesMergePresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: finiteRepeat,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.90)
        XCTAssertLessThanOrEqual(retargetStart, 1.0)

        retarget(
            harness,
            animation: fluidSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.05)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart - 0.30)
        XCTAssertLessThan(earlyReplacement, 0.70)

        harness.setTime(retargetTime + 0.22)
        XCTAssertLessThan(harness.currentValue().opacity, -0.45)

        harness.setTime(retargetTime + 0.60)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testPositiveSpeedOldRetargetedToDirectSpringUsesDirectSpringPresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: finiteSpeed,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.10)
        XCTAssertLessThan(retargetStart, 0.25)

        retarget(
            harness,
            animation: replacementSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.05)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart)
        XCTAssertGreaterThan(earlyReplacement, 0.05)

        harness.setTime(retargetTime + 0.20)
        let descendingFrame = harness.currentValue().opacity
        XCTAssertLessThan(descendingFrame, -0.25)
    }

    func testFiniteRepeatOldRetargetedToDirectSpringUsesDirectSpringPresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: finiteRepeat,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.90)
        XCTAssertLessThanOrEqual(retargetStart, 1.0)

        retarget(
            harness,
            animation: replacementSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.06)
        let earlyRise = harness.currentValue().opacity
        XCTAssertLessThan(earlyRise, 0.20)
        XCTAssertGreaterThan(earlyRise, 0.05)

        harness.setTime(retargetTime + 0.20)
        let descendingFrame = harness.currentValue().opacity
        XCTAssertLessThan(descendingFrame, -0.25)
    }

    func testDirectSpringOldRetargetedToPositiveSpeedUsesWrapperLocalFiniteTiming() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: directSpring,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.50)
        XCTAssertLessThan(retargetStart, 0.75)

        retarget(
            harness,
            animation: shortSpeed,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.10)
        let midReplacement = harness.currentValue().opacity
        XCTAssertLessThan(midReplacement, 0.25)
        XCTAssertGreaterThan(midReplacement, 0.05)

        harness.setTime(retargetTime + 0.22)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringOldRetargetedToFiniteRepeatUsesWrapperLocalCycles() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.25

        start(
            harness,
            animation: directSpring,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.50)
        XCTAssertLessThan(retargetStart, 0.75)

        retarget(
            harness,
            animation: shortRepeat,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.19)
        XCTAssertLessThan(harness.currentValue().opacity, -0.40)

        harness.setTime(retargetTime + 0.24)
        let restartedCycle = harness.currentValue().opacity
        XCTAssertGreaterThan(restartedCycle, 0.25)

        harness.setTime(retargetTime + 0.39)
        XCTAssertLessThan(harness.currentValue().opacity, -0.30)
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

    private var finiteSpeed: Animation {
        .linear(duration: 0.80).speed(0.5)
    }

    private var finiteRepeat: Animation {
        .linear(duration: 0.25).repeatCount(3, autoreverses: false)
    }

    private var shortSpeed: Animation {
        .linear(duration: 0.40).speed(2.0)
    }

    private var shortRepeat: Animation {
        .linear(duration: 0.20).repeatCount(3, autoreverses: false)
    }

    private var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 45.0,
            damping: 8.0,
            initialVelocity: 0.0
        )
    }

    private var replacementSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }

    private var fluidSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0)
    }
}
