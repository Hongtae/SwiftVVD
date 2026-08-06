import XCTest
@testable import VUI

final class AnimationBaseSurfaceTests: XCTestCase {
    // ASSERTIONS matchedGeometryTransitionPhaseAnimationLookupObserved
    func testTransitionPhaseAnimationLookupSkipsDisabledNilOverride() throws {
        var transaction = Transaction(animation: .linear(duration: 0.25))
        transaction.animation = nil
        transaction.disablesAnimations = true

        XCTAssertNil(transaction.animation)
        let animation = try XCTUnwrap(
            transaction.animationIgnoringTransitionPhase
        )
        XCTAssertEqual(animation.box.duration, 0.25, accuracy: 0.000_001)

        var empty = Transaction()
        empty.animation = nil
        empty.disablesAnimations = true
        XCTAssertNil(empty.animationIgnoringTransitionPhase)
    }

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

    func testDefaultAnimationBoxDelegatesToFluidSpringBaseTiming() throws {
        let defaultBox = try XCTUnwrap(Animation.default.box as? DefaultAnimationBox)
        let fluidBase = FluidSpringAnimationBox(
            response: 0.5,
            dampingFraction: 1.0,
            blendDuration: 0
        )

        XCTAssertEqual(defaultBox.duration, fluidBase.duration, accuracy: 0.000_000_000_001)
        XCTAssertEqual(
            defaultBox.terminalSamplingHorizon,
            fluidBase.terminalSamplingHorizon,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            defaultBox.terminalSamplingHorizon(for: Double(1)),
            fluidBase.terminalSamplingHorizon(for: Double(1)),
            accuracy: 0.000_000_000_001
        )
        XCTAssertGreaterThan(defaultBox.terminalSamplingHorizon(for: Double(1)), defaultBox.duration)

        let progress = 0.30
        XCTAssertEqual(
            defaultBox.value(at: progress),
            fluidBase.value(at: progress),
            accuracy: 0.000_000_000_001
        )

        var defaultContext = AnimationContext<Double>()
        var fluidContext = AnimationContext<Double>()
        let defaultValue = try XCTUnwrap(
            defaultBox.animate(value: 1.0, time: defaultBox.duration * progress, context: &defaultContext)
        )
        let fluidValue = try XCTUnwrap(
            fluidBase.animate(value: 1.0, time: fluidBase.duration * progress, context: &fluidContext)
        )
        XCTAssertEqual(defaultValue, fluidValue, accuracy: 0.000_000_000_001)
        XCTAssertEqual(defaultContext.isLogicallyComplete, fluidContext.isLogicallyComplete)
    }

    func testSpringAnimationBoxesExposeResidualExecutionSamples() throws {
        let fluid = try XCTUnwrap(
            Animation.spring(response: 0.30, dampingFraction: 0.70, blendDuration: 0).box
                as? FluidSpringAnimationBox
        )
        XCTAssertEqual(fluid.duration, 0.30, accuracy: 0.000_000_000_001)
        XCTAssertGreaterThan(fluid.terminalSamplingHorizon(for: Double(1)), fluid.duration)

        var fluidContext = AnimationContext<Double>()
        let fluidOvershoot = try XCTUnwrap(
            fluid.animate(value: 1.0, time: 0.20, context: &fluidContext)
        )
        XCTAssertGreaterThan(fluidOvershoot, 1.02)
        XCTAssertFalse(fluidContext.isLogicallyComplete)

        let fluidLogicalValue = try XCTUnwrap(
            fluid.animate(value: 1.0, time: fluid.duration, context: &fluidContext)
        )
        XCTAssertGreaterThan(fluidLogicalValue, 1.0)
        XCTAssertTrue(fluidContext.isLogicallyComplete)

        let fluidResidualValue = try XCTUnwrap(
            fluid.animate(value: 1.0, time: fluid.duration + 0.05, context: &fluidContext)
        )
        XCTAssertGreaterThan(abs(fluidResidualValue - 1.0), 0.000_5)

        let direct = try XCTUnwrap(
            Animation.interpolatingSpring(
                mass: 1.20,
                stiffness: 90.0,
                damping: 12.0,
                initialVelocity: 0.30
            ).box as? SpringAnimationBox
        )
        let alias = try XCTUnwrap(
            Animation.interpolatingSpring(
                Spring(mass: 1.20, stiffness: 90.0, damping: 12.0),
                initialVelocity: 0.30
            ).box as? SpringAnimationBox
        )

        let directPresentationDuration = direct.terminalSamplingHorizon(for: Double(1))
        let aliasPresentationDuration = alias.terminalSamplingHorizon(for: Double(1))
        XCTAssertGreaterThan(directPresentationDuration, direct.duration)
        XCTAssertGreaterThan(alias.duration, direct.duration)
        XCTAssertEqual(aliasPresentationDuration, directPresentationDuration, accuracy: 0.03)

        var directContext = AnimationContext<Double>()
        var aliasContext = AnimationContext<Double>()
        let directSample = try XCTUnwrap(
            direct.animate(value: 1.0, time: 0.30, context: &directContext)
        )
        let aliasSample = try XCTUnwrap(
            alias.animate(value: 1.0, time: 0.30, context: &aliasContext)
        )
        XCTAssertEqual(aliasSample, directSample, accuracy: 0.000_000_000_001)
        XCTAssertEqual(directSample, 0.99, accuracy: 0.04)

        var directPeakContext = AnimationContext<Double>()
        let directPeak = try XCTUnwrap(
            direct.animate(value: 1.0, time: 0.436, context: &directPeakContext)
        )
        XCTAssertGreaterThan(directPeak, 1.06)
        XCTAssertFalse(directPeakContext.isLogicallyComplete)

        var directLogicalContext = AnimationContext<Double>()
        let directResidual = try XCTUnwrap(
            direct.animate(value: 1.0, time: direct.duration + 0.05, context: &directLogicalContext)
        )
        XCTAssertTrue(directLogicalContext.isLogicallyComplete)
        XCTAssertGreaterThan(abs(directResidual - 1.0), 0.000_5)
        XCTAssertNil(
            direct.animate(
                value: 1.0,
                time: directPresentationDuration + 0.05,
                context: &directLogicalContext
            )
        )
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

    func testSourceDefinedCustomAnimationContextForwardsDeltaStateAndMerge() throws {
        let recorder = ContextAnimationRecorder()
        let custom = Animation(
            ContextProbeAnimation(
                label: "custom",
                duration: 0.45,
                mergeResult: true,
                recorder: recorder
            )
        )
        var context = AnimationContext<Double>()

        let firstOutput = try XCTUnwrap(custom.animate(value: -0.8, time: 0, context: &context))
        XCTAssertEqual(firstOutput, 0, accuracy: 0.000_000_000_001)

        let secondOutput = try XCTUnwrap(
            custom.animate(value: -0.8, time: 1.0 / 60.0, context: &context)
        )
        XCTAssertEqual(
            secondOutput,
            -0.8 * (1.0 / 60.0) / 0.45,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            recorder.events.prefix(2),
            [
                "animate:custom:value=-0.8:time=0.0:logical=false:frame=0",
                "animate:custom:value=-0.8:time=0.016666666666666666:logical=false:frame=1",
            ]
        )
        XCTAssertEqual(context.state[ContextFrameKey.self], 2)

        XCTAssertNil(custom.animate(value: -0.8, time: 0.45, context: &context))
        XCTAssertTrue(context.isLogicallyComplete)
        XCTAssertEqual(
            recorder.events.suffix(2),
            [
                "animate:custom:value=-0.8:time=0.45:logical=false:frame=2",
                "nil:custom",
            ]
        )

        let previous = Animation(
            ContextProbeAnimation(
                label: "retargetFirst",
                duration: 0.80,
                mergeResult: true,
                recorder: recorder
            )
        )
        let replacement = Animation(
            ContextProbeAnimation(
                label: "retargetSecond",
                duration: 0.35,
                mergeResult: true,
                recorder: recorder
            )
        )
        var mergeContext = AnimationContext<Double>()
        for frame in 0..<16 {
            _ = previous.animate(
                value: -0.85,
                time: TimeInterval(frame) / 60.0,
                context: &mergeContext
            )
        }

        XCTAssertTrue(
            replacement.shouldMerge(
                previous: previous,
                value: -0.85,
                time: 0.25,
                context: &mergeContext
            )
        )
        XCTAssertEqual(
            recorder.events.last,
            "shouldMerge:retargetSecond:value=-0.85:time=0.25:logical=false:frame=16"
        )

        let replacementOutput = try XCTUnwrap(
            replacement.animate(
                value: -0.10,
                time: 0.2667,
                context: &mergeContext
            )
        )
        XCTAssertEqual(replacementOutput, -0.10 * 0.2667 / 0.35, accuracy: 0.000_000_000_001)
        XCTAssertEqual(
            recorder.events.last,
            "animate:retargetSecond:value=-0.1:time=0.2667:logical=false:frame=16"
        )
        XCTAssertEqual(mergeContext.state[ContextFrameKey.self], 17)
        XCTAssertFalse(recorder.events.contains { $0.hasPrefix("velocity:") })
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

    func testUnitCurveCubicExecutionUsesNativeClampingAndQuantization() {
        let precision = 1.0 / 1_048_576.0
        let ease = UnitCurve.easeInOut

        XCTAssertEqual(ease.value(at: -0.25), 0)
        XCTAssertEqual(ease.velocity(at: -0.25), 0)
        XCTAssertEqual(ease.value(at: 0.333_333), 243_033 * precision)
        XCTAssertEqual(ease.velocity(at: 0.333_333), 1_461_093 * precision)
        XCTAssertEqual(ease.value(at: 0.731_25), 891_525 * precision)
        XCTAssertEqual(ease.velocity(at: 0.731_25), 1_194_546 * precision)
        XCTAssertEqual(ease.value(at: 1.25), 1)
        XCTAssertEqual(ease.velocity(at: 1.25), 0)

        let clampedX = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: -0.4, y: 1.3),
            endControlPoint: UnitPoint(x: 1.4, y: -0.2)
        )
        XCTAssertEqual(clampedX.value(at: 0.125), 535_889 * precision)
        XCTAssertEqual(clampedX.velocity(at: 0.125), 1_007_286 * precision)
        XCTAssertEqual(clampedX.value(at: 0.5), 563_610 * precision)
        XCTAssertEqual(clampedX.velocity(at: 0.5), -262_144 * precision)
        XCTAssertEqual(clampedX.value(at: 1), 1)
        XCTAssertEqual(clampedX.velocity(at: 1), .infinity)

        guard case let .bezier(_, start, end) =
                Animation.timingCurve(clampedX, duration: 0.4).function else {
            return XCTFail("Expected cubic UnitCurve to lower to a bezier descriptor.")
        }
        XCTAssertEqual(start.x, -0.4, accuracy: 0.000_000_000_001)
        XCTAssertEqual(start.y, 1.3, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.x, 1.4, accuracy: 0.000_000_000_001)
        XCTAssertEqual(end.y, -0.2, accuracy: 0.000_000_000_001)
    }

    func testCircularUnitCurveAnimationBoxSamplesValueAndVelocity() throws {
        let duration = 0.40
        let box = try XCTUnwrap(
            Animation.timingCurve(.circularEaseInOut, duration: duration).box
                as? UnitCurveAnimationBox
        )

        let progress = 0.25
        XCTAssertEqual(
            box.value(at: progress),
            UnitCurve.circularEaseInOut.value(at: progress),
            accuracy: 0.000_000_000_001
        )

        var context = AnimationContext<Double>()
        let animated = try XCTUnwrap(
            box.animate(value: 1.0, time: duration * progress, context: &context)
        )
        XCTAssertEqual(
            animated,
            UnitCurve.circularEaseInOut.value(at: progress),
            accuracy: 0.000_000_000_001
        )
        XCTAssertFalse(context.isLogicallyComplete)

        let velocity = try XCTUnwrap(
            box.velocity(
                value: 2.0,
                time: duration * progress,
                context: AnimationContext<Double>()
            )
        )
        XCTAssertEqual(
            velocity,
            2.0 * UnitCurve.circularEaseInOut.velocity(at: progress) / duration,
            accuracy: 0.000_000_000_001
        )

        let zeroDurationBox = try XCTUnwrap(
            Animation.timingCurve(.circularEaseInOut, duration: 0).box
                as? UnitCurveAnimationBox
        )
        XCTAssertNil(
            zeroDurationBox.velocity(
                value: 2.0,
                time: 0,
                context: AnimationContext<Double>()
            )
        )
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

    func testFunctionBezierFormReturnsOnlyBezierPayload() throws {
        let function = Animation.timingCurve(
            0.10,
            0.20,
            0.30,
            0.40,
            duration: 0.25
        ).function
        let bezier = try XCTUnwrap(function.bezierForm)
        XCTAssertEqual(bezier.duration, 0.25)
        XCTAssertEqual(bezier.cp1.x, 0.10, accuracy: 0.000_000_000_001)
        XCTAssertEqual(bezier.cp1.y, 0.20, accuracy: 0.000_000_000_001)
        XCTAssertEqual(bezier.cp2.x, 0.30, accuracy: 0.000_000_000_001)
        XCTAssertEqual(bezier.cp2.y, 0.40, accuracy: 0.000_000_000_001)

        XCTAssertNil(Animation.timingCurve(.circularEaseInOut, duration: 0.25).function.bezierForm)
        XCTAssertNil(Animation.linear(duration: 0.25).delay(0.10).function.bezierForm)
    }

    func testRepeatFunctionDescriptorsPreserveRawRepeatCounts() throws {
        let repeatZero = Animation.linear(duration: 0.20)
            .repeatCount(0, autoreverses: false)
            .function
        assertRepeatFunction(
            repeatZero,
            count: 0,
            autoreverses: false,
            baseDuration: 0.20
        )

        let repeatNegative = Animation.linear(duration: 0.20)
            .repeatCount(-2, autoreverses: true)
            .function
        assertRepeatFunction(
            repeatNegative,
            count: -2,
            autoreverses: true,
            baseDuration: 0.20
        )

        let repeatForever = Animation.linear(duration: 0.20)
            .repeatForever(autoreverses: false)
            .function
        assertRepeatFunction(
            repeatForever,
            count: .infinity,
            autoreverses: false,
            baseDuration: 0.20
        )
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

    func testSourceDefinedCustomModifiedContentRoutesExecutionThroughModifier() throws {
        let recorder = ModifierExecutionRecorder()
        let current = CustomAnimationModifiedContent(
            base: ModifierProbeAnimation(label: "current"),
            modifier: RecordingModifier(label: "currentModifier", recorder: recorder, mergeResult: true)
        )
        let previous = CustomAnimationModifiedContent(
            base: ModifierProbeAnimation(label: "previous"),
            modifier: RecordingModifier(label: "previousModifier", recorder: recorder, mergeResult: false)
        )

        var animateContext = AnimationContext<Double>()
        let animated = current.animate(value: 4.0, time: 0.50, context: &animateContext)
        XCTAssertEqual(animated, 2.0)
        XCTAssertTrue(animateContext.isLogicallyComplete)

        let velocityContext = AnimationContext<Double>(isLogicallyComplete: true)
        let velocity = current.velocity(value: 8.0, time: 0.25, context: velocityContext)
        XCTAssertEqual(velocity, 2.0)

        var mergeContext = AnimationContext<Double>()
        XCTAssertTrue(
            current.shouldMerge(
                previous: Animation(previous),
                value: 3.0,
                time: 0.75,
                context: &mergeContext
            )
        )
        XCTAssertTrue(mergeContext.isLogicallyComplete)

        let eventCountBeforeMismatch = recorder.events.count
        var mismatchedContext = AnimationContext<Double>()
        XCTAssertFalse(
            current.shouldMerge(
                previous: Animation.linear(duration: 0.20),
                value: 1.0,
                time: 0.10,
                context: &mismatchedContext
            )
        )
        XCTAssertEqual(recorder.events.count, eventCountBeforeMismatch)

        XCTAssertEqual(
            recorder.events,
            [
                "animate:currentModifier:base=current:value=4.0:time=0.5",
                "velocity:currentModifier:base=current:value=8.0:time=0.25:logical=true",
                "shouldMerge:currentModifier:previous=previousModifier:base=current:previousBase=previous:value=3.0:time=0.75",
            ]
        )
    }

    func testInternalCustomModifiedContentRoutesExecutionThroughModifier() throws {
        let recorder = ModifierExecutionRecorder()
        let current = InternalCustomAnimationModifiedContent(
            base: ModifierProbeAnimation(label: "current"),
            modifier: RecordingModifier(label: "currentModifier", recorder: recorder, mergeResult: true)
        )
        let previous = InternalCustomAnimationModifiedContent(
            base: ModifierProbeAnimation(label: "previous"),
            modifier: RecordingModifier(label: "previousModifier", recorder: recorder, mergeResult: false)
        )

        var animateContext = AnimationContext<Double>()
        let animated = current.animate(value: 6.0, time: 0.60, context: &animateContext)
        XCTAssertEqual(animated, 3.0)
        XCTAssertTrue(animateContext.isLogicallyComplete)

        let velocity = current.velocity(
            value: 12.0,
            time: 0.30,
            context: AnimationContext<Double>(isLogicallyComplete: false)
        )
        XCTAssertEqual(velocity, 3.0)

        var mergeContext = AnimationContext<Double>()
        XCTAssertTrue(
            current.shouldMerge(
                previous: Animation(previous),
                value: 5.0,
                time: 0.90,
                context: &mergeContext
            )
        )
        XCTAssertTrue(mergeContext.isLogicallyComplete)

        XCTAssertEqual(
            recorder.events,
            [
                "animate:currentModifier:base=current:value=6.0:time=0.6",
                "velocity:currentModifier:base=current:value=12.0:time=0.3:logical=false",
                "shouldMerge:currentModifier:previous=previousModifier:base=current:previousBase=previous:value=5.0:time=0.9",
            ]
        )
    }

    private func assertRepeatFunction(
        _ function: Animation.Function,
        count: Double,
        autoreverses: Bool,
        baseDuration: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .repeat(observedCount, observedAutoreverses, base) = function else {
            return XCTFail("Expected repeat function, got \(function)", file: file, line: line)
        }
        XCTAssertEqual(observedCount, count, file: file, line: line)
        XCTAssertEqual(observedAutoreverses, autoreverses, file: file, line: line)

        guard case let .bezier(duration, start, end) = base else {
            return XCTFail("Expected bezier repeat base, got \(base)", file: file, line: line)
        }
        XCTAssertEqual(duration, baseDuration, file: file, line: line)
        XCTAssertEqual(start.x, 0.0, accuracy: 0.000_000_000_001, file: file, line: line)
        XCTAssertEqual(start.y, 0.0, accuracy: 0.000_000_000_001, file: file, line: line)
        XCTAssertEqual(end.x, 1.0, accuracy: 0.000_000_000_001, file: file, line: line)
        XCTAssertEqual(end.y, 1.0, accuracy: 0.000_000_000_001, file: file, line: line)
    }
}

private final class ModifierExecutionRecorder {
    var events: [String] = []
}

private struct ModifierProbeAnimation: CustomAnimation {
    var label: String

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        nil
    }
}

private struct RecordingModifier: CustomAnimationModifier {
    var label: String
    var recorder: ModifierExecutionRecorder
    var mergeResult: Bool

    static func == (lhs: RecordingModifier, rhs: RecordingModifier) -> Bool {
        lhs.label == rhs.label
            && lhs.recorder === rhs.recorder
            && lhs.mergeResult == rhs.mergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(ObjectIdentifier(recorder))
        hasher.combine(mergeResult)
    }

    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        recorder.events.append(
            "animate:\(label):base=\(baseLabel(base)):value=\(doubleDescription(value)):time=\(time)"
        )
        context.isLogicallyComplete = true
        var output = value
        output.scale(by: 0.5)
        return output
    }

    func velocity<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        recorder.events.append(
            "velocity:\(label):base=\(baseLabel(base)):value=\(doubleDescription(value)):time=\(time):logical=\(context.isLogicallyComplete)"
        )
        var output = value
        output.scale(by: 0.25)
        return output
    }

    func shouldMerge<Value, Base>(
        base: Base,
        previous: RecordingModifier,
        previousBase: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic, Base: CustomAnimation {
        recorder.events.append(
            "shouldMerge:\(label):previous=\(previous.label):base=\(baseLabel(base)):previousBase=\(baseLabel(previousBase)):value=\(doubleDescription(value)):time=\(time)"
        )
        context.isLogicallyComplete = true
        return mergeResult
    }

    func function(base: Animation.Function) -> Animation.Function {
        base
    }

    func box(base: AnimationBoxBase) -> AnimationBoxBase {
        base
    }

    private func baseLabel<Base>(_ base: Base) -> String where Base: CustomAnimation {
        (base as? ModifierProbeAnimation)?.label ?? String(describing: Base.self)
    }

    private func doubleDescription<Value>(_ value: Value) -> String where Value: VectorArithmetic {
        if let value = value as? Double {
            return String(value)
        }
        return String(describing: value)
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

private final class ContextAnimationRecorder: @unchecked Sendable {
    var events: [String] = []
}

private enum ContextFrameKey: AnimationStateKey {
    static let defaultValue = 0
}

private struct ContextProbeAnimation: CustomAnimation, @unchecked Sendable {
    var label: String
    var duration: TimeInterval
    var mergeResult: Bool
    var recorder: ContextAnimationRecorder

    static func == (lhs: ContextProbeAnimation, rhs: ContextProbeAnimation) -> Bool {
        lhs.label == rhs.label &&
            lhs.duration == rhs.duration &&
            lhs.mergeResult == rhs.mergeResult &&
            lhs.recorder === rhs.recorder
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(duration)
        hasher.combine(mergeResult)
        hasher.combine(ObjectIdentifier(recorder))
    }

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        let frame = context.state[ContextFrameKey.self]
        context.state[ContextFrameKey.self] = frame + 1
        recorder.events.append(
            "animate:\(label):value=\(doubleDescription(value)):time=\(time):logical=\(context.isLogicallyComplete):frame=\(frame)"
        )
        guard time < duration else {
            context.isLogicallyComplete = true
            recorder.events.append("nil:\(label)")
            return nil
        }
        var output = value
        output.scale(by: time / duration)
        return output
    }

    func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        recorder.events.append(
            "velocity:\(label):value=\(doubleDescription(value)):time=\(time):logical=\(context.isLogicallyComplete)"
        )
        return nil
    }

    func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        let frame = context.state[ContextFrameKey.self]
        recorder.events.append(
            "shouldMerge:\(label):value=\(doubleDescription(value)):time=\(time):logical=\(context.isLogicallyComplete):frame=\(frame)"
        )
        return mergeResult
    }

    private func doubleDescription<Value>(_ value: Value) -> String where Value: VectorArithmetic {
        if let value = value as? Double {
            return String(value)
        }
        return String(describing: value)
    }
}
