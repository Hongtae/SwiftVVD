import XCTest
@testable import VUI

final class AnimatableAttributeDefaultPresentationRetargetTests: XCTestCase {
    func testLinearRetargetedToDefaultMovesImmediatelyTowardReplacementTarget() {
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
            animation: .default,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.10)
        let earlyReplacement = harness.currentValue().opacity
        XCTAssertLessThan(earlyReplacement, retargetStart - 0.20)
        XCTAssertLessThan(earlyReplacement, 0.05)

        harness.setTime(retargetTime + 0.90)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDirectSpringRetargetedToDefaultMovesThroughMergePath() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldSpring, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.45)
        XCTAssertLessThan(retargetStart, 0.70)

        retarget(harness, animation: .default, target: -0.5)

        harness.setTime(retargetTime + 0.10)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.25)

        harness.setTime(retargetTime + 0.15)
        XCTAssertLessThan(harness.currentValue().opacity, 0)

        harness.setTime(retargetTime + 0.85)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testBezierRetargetedToDefaultMovesThroughMergePath() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: oldBezier, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.35)
        XCTAssertLessThan(retargetStart, 0.60)

        retarget(harness, animation: .default, target: -0.5)

        harness.setTime(retargetTime + 0.10)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.20)

        harness.setTime(retargetTime + 0.15)
        XCTAssertLessThan(harness.currentValue().opacity, 0)

        harness.setTime(retargetTime + 0.85)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDefaultRetargetedToFiniteLinearUsesFiniteTiming() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: .default, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.85)

        retarget(harness, animation: shortLinear, target: -0.5)

        harness.setTime(retargetTime + 0.22)
        XCTAssertLessThan(harness.currentValue().opacity, 0.35)

        harness.setTime(retargetTime + 0.47)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDefaultRetargetedToBezierKeepsOldPresentationContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: .default, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.85)

        retarget(harness, animation: shortBezier, target: -0.5)

        harness.setTime(retargetTime + 0.03)
        XCTAssertGreaterThan(harness.currentValue().opacity, retargetStart + 0.02)

        harness.setTime(retargetTime + 0.24)
        XCTAssertLessThan(harness.currentValue().opacity, 0.20)

        harness.setTime(retargetTime + 0.47)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDefaultRetargetedToDirectSpringKeepsOldPresentationContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(
            harness,
            animation: .default,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.90)

        retarget(
            harness,
            animation: directSpring,
            target: -0.5
        )

        harness.setTime(retargetTime + 0.02)
        let firstRetargetFrame = harness.currentValue().opacity
        XCTAssertGreaterThan(firstRetargetFrame, retargetStart)

        harness.setTime(retargetTime + 0.12)
        let descendingFrame = harness.currentValue().opacity
        XCTAssertLessThan(descendingFrame, 0.45)

        harness.setTime(retargetTime + 0.28)
        let overshootFrame = harness.currentValue().opacity
        XCTAssertLessThan(overshootFrame, -0.45)
    }

    func testDefaultRetargetedToDefaultPreservesMergeState() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: .default, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.85)

        retarget(harness, animation: .default, target: -0.5)

        harness.setTime(retargetTime + 0.02)
        XCTAssertGreaterThan(harness.currentValue().opacity, retargetStart + 0.003)

        harness.setTime(retargetTime + 0.10)
        XCTAssertLessThan(harness.currentValue().opacity, 0.45)

        harness.setTime(retargetTime + 0.85)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testPositiveSpeedRetargetedToDefaultMovesThroughMergePath() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: finiteSpeed, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.08)
        XCTAssertLessThan(retargetStart, 0.18)

        retarget(harness, animation: .default, target: -0.5)

        harness.setTime(retargetTime + 0.08)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.08)

        harness.setTime(retargetTime + 0.22)
        XCTAssertLessThan(harness.currentValue().opacity, -0.25)

        harness.setTime(retargetTime + 0.85)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testFiniteRepeatRetargetedToDefaultMovesThroughMergePath() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: finiteRepeat, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.75)
        XCTAssertLessThan(retargetStart, 0.90)

        retarget(harness, animation: .default, target: -0.5)

        harness.setTime(retargetTime + 0.10)
        XCTAssertLessThan(harness.currentValue().opacity, retargetStart - 0.35)

        harness.setTime(retargetTime + 0.18)
        XCTAssertLessThan(harness.currentValue().opacity, -0.02)

        harness.setTime(retargetTime + 0.85)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDefaultRetargetedToPositiveSpeedUsesFiniteWrapperTiming() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(
            harness,
            animation: .default,
            target: 1
        )
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.90)

        retarget(
            harness,
            animation: Animation.linear(duration: 0.40).speed(2.0),
            target: -0.5
        )

        harness.setTime(retargetTime + 0.10)
        let middleFrame = harness.currentValue().opacity
        XCTAssertLessThan(middleFrame, 0.20)

        harness.setTime(retargetTime + 0.22)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
    }

    func testDefaultRetargetedToFiniteRepeatUsesWrapperLocalCycles() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.22

        start(harness, animation: .default, target: 1)
        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.60)
        XCTAssertLessThan(retargetStart, 0.85)

        retarget(harness, animation: shortRepeat, target: -0.5)

        harness.setTime(retargetTime + 0.19)
        XCTAssertLessThan(harness.currentValue().opacity, -0.40)

        harness.setTime(retargetTime + 0.24)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.25)

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

    private var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }

    private var oldSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 45.0,
            damping: 8.0,
            initialVelocity: 0.0
        )
    }

    private var oldBezier: Animation {
        .timingCurve(0.25, 0.10, 0.25, 1.0, duration: 0.80)
    }

    private var shortLinear: Animation {
        .linear(duration: 0.45)
    }

    private var shortBezier: Animation {
        .timingCurve(0.42, 0.0, 0.58, 1.0, duration: 0.45)
    }

    private var finiteSpeed: Animation {
        .linear(duration: 0.80).speed(0.5)
    }

    private var finiteRepeat: Animation {
        .linear(duration: 0.25).repeatCount(3, autoreverses: false)
    }

    private var shortRepeat: Animation {
        .linear(duration: 0.20).repeatCount(3, autoreverses: false)
    }
}
