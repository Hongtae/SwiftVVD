import XCTest
@testable import VUI

final class AnimatableAttributeBuiltInMultiPresentationRetargetTests: XCTestCase {
    func testRepeatedDirectSpringRetargetsKeepPriorPresentationContribution() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        start(harness, animation: springA, target: 1)
        sampleFrames(harness, through: secondRetargetTime)
        let secondStart = harness.currentValue().opacity
        XCTAssertGreaterThan(secondStart, 0.35)
        XCTAssertLessThan(secondStart, 0.65)

        retarget(harness, animation: springB, target: -0.8)

        harness.setTime(secondRetargetTime + 0.02)
        let earlySecond = harness.currentValue().opacity
        XCTAssertGreaterThan(earlySecond, secondStart)

        harness.setTime(secondRetargetTime + 0.12)
        XCTAssertLessThan(harness.currentValue().opacity, 0.15)

        sampleFrames(harness, from: secondRetargetTime + 0.02, through: thirdRetargetTime)
        let thirdStart = harness.currentValue().opacity
        XCTAssertLessThan(thirdStart, -0.50)

        retarget(harness, animation: springC, target: 1.2)

        harness.setTime(thirdRetargetTime + 0.03)
        let earlyThird = harness.currentValue().opacity
        XCTAssertLessThan(earlyThird, thirdStart)

        harness.setTime(thirdRetargetTime + 0.16)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.35)

        harness.setTime(thirdRetargetTime + 0.34)
        XCTAssertGreaterThan(harness.currentValue().opacity, 1.25)
    }

    func testRepeatedFluidSpringRetargetsContinueMergePresentation() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        start(harness, animation: fluidA, target: 1)
        sampleFrames(harness, through: secondRetargetTime)
        let secondStart = harness.currentValue().opacity
        XCTAssertGreaterThan(secondStart, 0.55)
        XCTAssertLessThan(secondStart, 0.85)

        retarget(harness, animation: fluidB, target: -0.8)

        harness.setTime(secondRetargetTime + 0.05)
        XCTAssertLessThan(harness.currentValue().opacity, secondStart - 0.20)

        sampleFrames(harness, from: secondRetargetTime + 0.05, through: thirdRetargetTime)
        let thirdStart = harness.currentValue().opacity
        XCTAssertLessThan(thirdStart, -0.65)

        retarget(harness, animation: fluidC, target: 1.2)

        harness.setTime(thirdRetargetTime + 0.05)
        XCTAssertGreaterThan(harness.currentValue().opacity, thirdStart + 0.08)

        harness.setTime(thirdRetargetTime + 0.16)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.25)

        harness.setTime(thirdRetargetTime + 0.36)
        XCTAssertGreaterThan(harness.currentValue().opacity, 1.0)
    }

    func testSpringFluidSpringUsesReplacementFamilyPresentationDirection() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        start(harness, animation: springA, target: 1)
        sampleFrames(harness, through: secondRetargetTime)
        let secondStart = harness.currentValue().opacity
        XCTAssertGreaterThan(secondStart, 0.35)
        XCTAssertLessThan(secondStart, 0.65)

        retarget(harness, animation: fluidB, target: -0.8)

        harness.setTime(secondRetargetTime + 0.05)
        XCTAssertLessThan(harness.currentValue().opacity, secondStart - 0.25)

        sampleFrames(harness, from: secondRetargetTime + 0.05, through: thirdRetargetTime)
        let thirdStart = harness.currentValue().opacity
        XCTAssertLessThan(thirdStart, -0.65)

        retarget(harness, animation: springC, target: 1.2)

        harness.setTime(thirdRetargetTime + 0.05)
        XCTAssertGreaterThan(harness.currentValue().opacity, thirdStart + 0.15)

        harness.setTime(thirdRetargetTime + 0.16)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.45)

        harness.setTime(thirdRetargetTime + 0.34)
        XCTAssertGreaterThan(harness.currentValue().opacity, 1.25)
    }

    func testFluidSpringFluidUsesReplacementFamilyPresentationDirection() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        start(harness, animation: fluidA, target: 1)
        sampleFrames(harness, through: secondRetargetTime)
        let secondStart = harness.currentValue().opacity
        XCTAssertGreaterThan(secondStart, 0.55)
        XCTAssertLessThan(secondStart, 0.85)

        retarget(harness, animation: springB, target: -0.8)

        harness.setTime(secondRetargetTime + 0.02)
        let earlySecond = harness.currentValue().opacity
        XCTAssertGreaterThan(earlySecond, secondStart)

        harness.setTime(secondRetargetTime + 0.13)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.05)

        sampleFrames(harness, from: secondRetargetTime + 0.13, through: thirdRetargetTime)
        let thirdStart = harness.currentValue().opacity
        XCTAssertLessThan(thirdStart, -0.55)

        retarget(harness, animation: fluidC, target: 1.2)

        harness.setTime(thirdRetargetTime + 0.05)
        XCTAssertGreaterThan(harness.currentValue().opacity, thirdStart + 0.08)

        harness.setTime(thirdRetargetTime + 0.16)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0.35)

        harness.setTime(thirdRetargetTime + 0.36)
        XCTAssertGreaterThan(harness.currentValue().opacity, 1.0)
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
        from startTime: Double = 1.0 / 60.0,
        through endTime: Double
    ) {
        var time = startTime
        while time <= endTime {
            harness.setTime(time)
            _ = harness.currentValue()
            time += 1.0 / 60.0
        }
    }

    private var secondRetargetTime: Double { 0.22 }
    private var thirdRetargetTime: Double { 0.44 }

    private var springA: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 42.0,
            damping: 7.0,
            initialVelocity: 0.0
        )
    }

    private var springB: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 85.0,
            damping: 8.0,
            initialVelocity: 0.0
        )
    }

    private var springC: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 120.0,
            damping: 12.0,
            initialVelocity: 0.0
        )
    }

    private var fluidA: Animation {
        .spring(response: 0.70, dampingFraction: 0.70, blendDuration: 0.0)
    }

    private var fluidB: Animation {
        .spring(response: 0.40, dampingFraction: 0.70, blendDuration: 0.0)
    }

    private var fluidC: Animation {
        .spring(response: 0.55, dampingFraction: 0.80, blendDuration: 0.0)
    }
}
