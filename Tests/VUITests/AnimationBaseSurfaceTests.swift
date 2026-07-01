import XCTest
@testable import VUI

final class AnimationBaseSurfaceTests: XCTestCase {
    func testBuiltInAnimationsExposeConcreteCustomAnimationBases() throws {
        XCTAssertTrue(Animation.default.base is DefaultAnimation)

        let linear = try XCTUnwrap(Animation.linear(duration: 0.25).base as? BezierAnimation)
        XCTAssertEqual(linear.duration, 0.25, accuracy: 0.000_001)

        let circular = try XCTUnwrap(
            Animation.timingCurve(.circularEaseInOut, duration: 0.30).base as? UnitCurveAnimation
        )
        XCTAssertEqual(circular.duration, 0.30, accuracy: 0.000_001)

        let fluid = try XCTUnwrap(
            Animation.spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0).base
                as? FluidSpringAnimation
        )
        XCTAssertEqual(fluid.response, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(fluid.dampingFraction, 0.70, accuracy: 0.000_001)
        XCTAssertEqual(fluid.blendDuration, 0.0, accuracy: 0.000_001)

        let directSpring = try XCTUnwrap(
            Animation.interpolatingSpring(
                mass: 1.0,
                stiffness: 100.0,
                damping: 10.0,
                initialVelocity: 0.0
            ).base as? SpringAnimation
        )
        XCTAssertEqual(directSpring.mass, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(directSpring.stiffness, 100.0, accuracy: 0.000_001)
        XCTAssertEqual(directSpring.damping, 10.0, accuracy: 0.000_001)
        XCTAssertEqual(directSpring.initialVelocity.valuePerSecond, 0.0, accuracy: 0.000_001)
    }

    func testBuiltInWrappersExposeInternalModifiedContentBase() throws {
        let linear = Animation.linear(duration: 0.25)

        let delay = try XCTUnwrap(
            linear.delay(0.10).base
                as? InternalCustomAnimationModifiedContent<BezierAnimation, DelayAnimation>
        )
        XCTAssertEqual(delay.base.duration, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(delay.modifier.delay, 0.10, accuracy: 0.000_001)

        let speed = try XCTUnwrap(
            linear.speed(2.0).base
                as? InternalCustomAnimationModifiedContent<BezierAnimation, SpeedAnimation>
        )
        XCTAssertEqual(speed.base.duration, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(speed.modifier.speed, 2.0, accuracy: 0.000_001)

        let finiteRepeat = try XCTUnwrap(
            linear.repeatCount(2, autoreverses: false).base
                as? InternalCustomAnimationModifiedContent<BezierAnimation, RepeatAnimation>
        )
        XCTAssertEqual(finiteRepeat.base.duration, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(finiteRepeat.modifier.repeatCount, 2)
        XCTAssertFalse(finiteRepeat.modifier.autoreverses)

        let circularDelay = try XCTUnwrap(
            Animation.timingCurve(.circularEaseInOut, duration: 0.30).delay(0.10).base
                as? InternalCustomAnimationModifiedContent<UnitCurveAnimation, DelayAnimation>
        )
        XCTAssertEqual(circularDelay.base.duration, 0.30, accuracy: 0.000_001)
        XCTAssertEqual(circularDelay.modifier.delay, 0.10, accuracy: 0.000_001)
    }

    func testSourceDefinedCustomWrappersPreservePublicCarrierSplit() throws {
        let source = Animation(SourceCustomAnimation(label: "source", duration: 0.30))

        let sourceBase = try XCTUnwrap(source.base as? SourceCustomAnimation)
        XCTAssertEqual(sourceBase.label, "source")
        XCTAssertEqual(sourceBase.duration, 0.30, accuracy: 0.000_001)

        let sourceDelay = try XCTUnwrap(
            source.delay(0.10).base
                as? CustomAnimationModifiedContent<SourceCustomAnimation, DelayAnimation>
        )
        XCTAssertEqual(sourceDelay.base.label, "source")
        XCTAssertEqual(sourceDelay.modifier.delay, 0.10, accuracy: 0.000_001)

        let sourceSpeed = try XCTUnwrap(
            source.speed(2.0).base
                as? CustomAnimationModifiedContent<SourceCustomAnimation, SpeedAnimation>
        )
        XCTAssertEqual(sourceSpeed.base.label, "source")
        XCTAssertEqual(sourceSpeed.modifier.speed, 2.0, accuracy: 0.000_001)

        let sourceRepeat = try XCTUnwrap(
            source.repeatCount(2, autoreverses: false).base
                as? CustomAnimationModifiedContent<SourceCustomAnimation, RepeatAnimation>
        )
        XCTAssertEqual(sourceRepeat.base.label, "source")
        XCTAssertEqual(sourceRepeat.modifier.repeatCount, 2)
        XCTAssertFalse(sourceRepeat.modifier.autoreverses)

        let sourceDelaySpeed = try XCTUnwrap(
            source.delay(0.10).speed(2.0).base
                as? InternalCustomAnimationModifiedContent<
                    CustomAnimationModifiedContent<SourceCustomAnimation, DelayAnimation>,
                    SpeedAnimation
                >
        )
        XCTAssertEqual(sourceDelaySpeed.base.base.label, "source")
        XCTAssertEqual(sourceDelaySpeed.base.modifier.delay, 0.10, accuracy: 0.000_001)
        XCTAssertEqual(sourceDelaySpeed.modifier.speed, 2.0, accuracy: 0.000_001)
    }

    func testBuiltInBaseFunctionsExposeExpectedDescriptorCases() throws {
        let bezier = Animation.timingCurve(
            0.10,
            0.20,
            0.30,
            0.40,
            duration: 0.25
        ).function
        guard case let .bezier(bezierDuration, start, end) = bezier else {
            return XCTFail("Expected bezier descriptor, got \(bezier)")
        }
        XCTAssertEqual(bezierDuration, 0.25)
        XCTAssertEqual(start.x, 0.10, accuracy: 0.000_000_000_001)
        XCTAssertEqual(start.y, 0.20, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.x, 0.30, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.y, 0.40, accuracy: 0.000_000_000_001)

        let circularEaseIn = Animation.timingCurve(.circularEaseIn, duration: 0.30).function
        guard case let .circularEaseIn(circularEaseInDuration) = circularEaseIn else {
            return XCTFail("Expected circular ease-in descriptor, got \(circularEaseIn)")
        }
        XCTAssertEqual(circularEaseInDuration, 0.30)

        let circularEaseOut = Animation.timingCurve(.circularEaseOut, duration: 0.35).function
        guard case let .circularEaseOut(circularEaseOutDuration) = circularEaseOut else {
            return XCTFail("Expected circular ease-out descriptor, got \(circularEaseOut)")
        }
        XCTAssertEqual(circularEaseOutDuration, 0.35)

        let circularEaseInOut = Animation.timingCurve(.circularEaseInOut, duration: 0.40).function
        guard case let .circularEaseInOut(circularEaseInOutDuration) = circularEaseInOut else {
            return XCTFail("Expected circular ease-in-out descriptor, got \(circularEaseInOut)")
        }
        XCTAssertEqual(circularEaseInOutDuration, 0.40)

        let fluidSpring = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        ).function
        guard case let .spring(_, fluidMass, fluidStiffness, fluidDamping, fluidInitialVelocity) =
                fluidSpring else {
            return XCTFail("Expected fluid spring descriptor, got \(fluidSpring)")
        }
        XCTAssertEqual(fluidMass, 1.0)
        XCTAssertGreaterThan(fluidStiffness, 0.0)
        XCTAssertGreaterThan(fluidDamping, 0.0)
        XCTAssertEqual(fluidInitialVelocity, 0.0)

        let interpolatingSpring = Animation.interpolatingSpring(
            mass: 2.0,
            stiffness: 30.0,
            damping: 5.0,
            initialVelocity: 0.60
        ).function
        guard case let .spring(_, mass, stiffness, damping, initialVelocity) = interpolatingSpring else {
            return XCTFail("Expected spring descriptor, got \(interpolatingSpring)")
        }
        XCTAssertEqual(mass, 2.0)
        XCTAssertEqual(stiffness, 30.0)
        XCTAssertEqual(damping, 5.0)
        XCTAssertEqual(initialVelocity, 0.60)
    }

    func testBuiltInFunctionDescriptorsPreserveNegativeCurveDurations() throws {
        let negative = -0.20
        let bezier = Animation.timingCurve(
            0.25,
            0.10,
            0.25,
            1.0,
            duration: negative
        ).function
        guard case let .bezier(bezierDuration, start, end) = bezier else {
            return XCTFail("Expected bezier descriptor, got \(bezier)")
        }
        XCTAssertEqual(bezierDuration, negative)
        XCTAssertEqual(start.x, 0.25, accuracy: 0.000_000_000_001)
        XCTAssertEqual(start.y, 0.10, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.x, 0.25, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.y, 1.0, accuracy: 0.000_000_000_001)

        let cubicUnitCurve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.18, y: 0.07),
            endControlPoint: UnitPoint(x: 0.82, y: 0.96)
        )
        let cubicLowered = Animation.timingCurve(cubicUnitCurve, duration: negative).function
        guard case let .bezier(cubicDuration, cubicStart, cubicEnd) = cubicLowered else {
            return XCTFail("Expected cubic UnitCurve to lower to bezier descriptor, got \(cubicLowered)")
        }
        XCTAssertEqual(cubicDuration, negative)
        XCTAssertEqual(cubicStart.x, 0.18, accuracy: 0.000_000_000_001)
        XCTAssertEqual(cubicStart.y, 0.07, accuracy: 0.000_000_000_001)
        XCTAssertEqual(cubicEnd.x, 0.82, accuracy: 0.000_000_000_001)
        XCTAssertEqual(cubicEnd.y, 0.96, accuracy: 0.000_000_000_001)

        let circular = Animation.timingCurve(.circularEaseInOut, duration: negative).function
        guard case let .circularEaseInOut(circularDuration) = circular else {
            return XCTFail("Expected circular ease-in-out descriptor, got \(circular)")
        }
        XCTAssertEqual(circularDuration, negative)
    }

    func testBuiltInWrapperFunctionPreservesRecursiveModifierOrder() throws {
        let function = Animation.timingCurve(.circularEaseInOut, duration: 0.30)
            .delay(0.10)
            .speed(2.0)
            .repeatCount(3, autoreverses: false)
            .function

        guard case let .repeat(repeatCount, autoreverses, repeatBase) = function else {
            return XCTFail("Expected repeat wrapper function, got \(function)")
        }
        XCTAssertEqual(repeatCount, 3)
        XCTAssertFalse(autoreverses)

        guard case let .speed(speed, speedBase) = repeatBase else {
            return XCTFail("Expected speed wrapper function, got \(repeatBase)")
        }
        XCTAssertEqual(speed, 2.0)

        guard case let .delay(delay, delayBase) = speedBase else {
            return XCTFail("Expected delay wrapper function, got \(speedBase)")
        }
        XCTAssertEqual(delay, 0.10)

        guard case let .circularEaseInOut(duration) = delayBase else {
            return XCTFail("Expected circular ease-in-out base function, got \(delayBase)")
        }
        XCTAssertEqual(duration, 0.30)
    }

    func testSourceDefinedWrapperFunctionStartsFromCustomFunctionAndPreservesOrder() throws {
        let function = Animation(SourceCustomAnimation(label: "source", duration: 0.30))
            .delay(0.10)
            .speed(2.0)
            .function

        guard case let .speed(speed, speedBase) = function else {
            return XCTFail("Expected speed wrapper function, got \(function)")
        }
        XCTAssertEqual(speed, 2.0)

        guard case let .delay(delay, delayBase) = speedBase else {
            return XCTFail("Expected delay wrapper function, got \(speedBase)")
        }
        XCTAssertEqual(delay, 0.10)

        guard case .customFunction = delayBase else {
            return XCTFail("Expected source-defined custom base function, got \(delayBase)")
        }
    }
}

private struct SourceCustomAnimation: CustomAnimation {
    var label: String
    var duration: TimeInterval

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        time >= duration ? value : nil
    }
}
