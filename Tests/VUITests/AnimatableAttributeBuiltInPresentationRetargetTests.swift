import XCTest
@testable import VUI

final class AnimatableAttributeBuiltInPresentationRetargetTests: XCTestCase {
    func testFiniteLinearOldRetargetedToDirectSpringKeepsOldContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldLinear, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.15)
        XCTAssertLessThan(retargetStart, 0.35)

        retarget(harness, animation: directSpring, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart)

        harness.setTime(retargetTime + 0.16)
        XCTAssertLessThan(harness.currentValue().opacity, -0.15)

        harness.setTime(retargetTime + 1.50)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringOldRetargetedToFiniteLinearKeepsEarlySpringContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: shortLinear, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart)

        harness.setTime(retargetTime + 0.22)
        XCTAssertLessThan(harness.currentValue().opacity, 0.30)

        harness.setTime(retargetTime + 0.47)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringOldRetargetedToDirectSpringKeepsOldContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: directSpring, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart + 0.02)

        harness.setTime(retargetTime + 0.18)
        XCTAssertLessThan(harness.currentValue().opacity, -0.05)

        harness.setTime(retargetTime + 0.34)
        XCTAssertLessThan(harness.currentValue().opacity, -0.65)

        harness.setTime(retargetTime + 1.50)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testFluidSpringOldRetargetedToDirectSpringKeepsOldContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: slowFluidSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.55)
        XCTAssertLessThan(retargetStart, 0.75)

        retarget(harness, animation: directSpring, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart + 0.02)

        harness.setTime(retargetTime + 0.16)
        XCTAssertLessThan(harness.currentValue().opacity, -0.03)

        harness.setTime(retargetTime + 0.34)
        XCTAssertLessThan(harness.currentValue().opacity, -0.65)

        harness.setTime(retargetTime + 1.50)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringOldRetargetedToFluidSpringUsesMergePresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: fluidSpring, target: -0.5)

        harness.setTime(retargetTime + 0.03)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.02)

        harness.setTime(retargetTime + 0.10)
        XCTAssertLessThan(harness.currentValue().opacity, 0)

        harness.setTime(retargetTime + 0.20)
        XCTAssertLessThan(harness.currentValue().opacity, -0.49)

        harness.setTime(retargetTime + 0.60)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testBezierOldRetargetedToDirectSpringUsesDirectSpringPresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldBezier, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.80)

        retarget(harness, animation: directSpring, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart - 0.05)

        harness.setTime(retargetTime + 0.18)
        XCTAssertLessThan(harness.currentValue().opacity, -0.15)

        harness.setTime(retargetTime + 0.36)
        XCTAssertLessThan(harness.currentValue().opacity, -0.65)
    }

    func testDirectSpringOldRetargetedToBezierUsesFinitePresentationBoundary() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: shortBezier, target: -0.5)

        harness.setTime(retargetTime + 0.06)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.30)

        harness.setTime(retargetTime + 0.24)
        XCTAssertLessThan(harness.currentValue().opacity, -0.35)

        harness.setTime(retargetTime + 0.46)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testFiniteDelayOldRetargetedToFluidSpringUsesMergePresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: delayedLinear, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.08)
        XCTAssertLessThan(retargetStart, 0.18)

        retarget(harness, animation: fluidSpring, target: -0.5)

        harness.setTime(retargetTime + 0.05)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart - 0.10)

        harness.setTime(retargetTime + 0.18)
        XCTAssertLessThan(harness.currentValue().opacity, -0.45)

        harness.setTime(retargetTime + 0.55)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringOldRetargetedToFiniteDelayKeepsHoldWindowContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: shortDelayedLinear, target: -0.5)

        harness.setTime(retargetTime + 0.10)
        let delayWindowValue = harness.currentValue().opacity
        XCTAssertGreaterThan(delayWindowValue, retargetStart + 0.20)

        harness.setTime(retargetTime + 0.30)
        XCTAssertLessThan(harness.currentValue().opacity, 0.50)

        harness.setTime(retargetTime + 0.47)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
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

    private var oldLinear: Animation {
        .linear(duration: 0.80)
    }

    private var shortLinear: Animation {
        .linear(duration: 0.45)
    }

    private var oldBezier: Animation {
        .timingCurve(0.20, 0.80, 0.35, 1.00, duration: 0.80)
    }

    private var shortBezier: Animation {
        .timingCurve(0.20, 0.80, 0.35, 1.00, duration: 0.45)
    }

    private var delayedLinear: Animation {
        .linear(duration: 0.80).delay(0.10)
    }

    private var shortDelayedLinear: Animation {
        .linear(duration: 0.25).delay(0.20)
    }

    private var oldSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 45.0,
            damping: 8.0,
            initialVelocity: 0.0
        )
    }

    private var directSpring: Animation {
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

    private var slowFluidSpring: Animation {
        .spring(response: 0.80, dampingFraction: 0.70, blendDuration: 0.0)
    }
}
