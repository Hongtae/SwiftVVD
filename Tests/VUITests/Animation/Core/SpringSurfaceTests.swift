import XCTest
@testable import VUI

final class SpringSurfaceTests: XCTestCase {
    func testSpringStorageAndDerivedPropertiesMatchSampledSurface() {
        let spring = Spring(duration: 0.50, bounce: 0.20)

        XCTAssertEqual(MemoryLayout<Spring>.size, 24)
        XCTAssertEqual(MemoryLayout<Spring>.stride, 24)
        XCTAssertEqual(Mirror(reflecting: spring).children.map { $0.label ?? "_" },
                       ["angularFrequency", "decayConstant", "_mass"])
        assertSpring(
            spring,
            duration: 0.5,
            bounce: 0.2,
            response: 0.5,
            dampingRatio: 0.8,
            mass: 1.0,
            stiffness: 157.91367041742973,
            damping: 20.106192982974676
        )

        assertSpring(
            Spring(mass: 1.2, stiffness: 90.0, damping: 40.0, allowOverDamping: true),
            duration: 0.7255197456936871,
            bounce: -0.4803847577293368,
            response: 0.7255197456936871,
            dampingRatio: 1.9245008972987525,
            mass: 1.2,
            stiffness: 576.6666666666667,
            damping: 40.0
        )

        assertSpring(
            Spring(mass: 1.2, stiffness: 90.0, damping: 40.0),
            duration: 0.7255197456936871,
            bounce: 0.0,
            response: 0.7255197456936871,
            dampingRatio: 1.0,
            mass: 1.2,
            stiffness: 90.0,
            damping: 20.784609690826528
        )
    }

    // ASSERTIONS springDurationBounceBranchDisassemblyObserved
    func testSpringEdgeInputsPreserveSampledDerivedSurface() {
        assertSpring(
            Spring(duration: -0.20, bounce: 0.0),
            duration: 0.2,
            bounce: 2.0,
            response: 0.2,
            dampingRatio: -1.0,
            mass: 1.0,
            stiffness: 986.9604401089358,
            damping: -62.83185307179586
        )
        assertSpring(
            Spring(duration: 0.50, bounce: -0.50),
            duration: 0.5,
            bounce: -0.5,
            response: 0.5,
            dampingRatio: 2.0,
            mass: 1.0,
            stiffness: 1105.3956932012077,
            damping: 50.26548245743669
        )
        assertSpring(
            Spring(duration: 0.50, bounce: 1.20),
            duration: 0.5,
            bounce: 1.0,
            response: 0.5,
            dampingRatio: 0.0,
            mass: 1.0,
            stiffness: 157.91367041742973,
            damping: 0.0
        )
        assertSpring(
            Spring(duration: 0.50, bounce: -1.0),
            duration: .nan,
            bounce: .nan,
            response: .nan,
            dampingRatio: .nan,
            mass: 1.0,
            stiffness: .infinity,
            damping: .infinity
        )
        let extremeOverdamped = Spring(duration: 0.50, bounce: -1.0)
        let fields = Array(Mirror(reflecting: extremeOverdamped).children)
        XCTAssertEqual(fields[0].value as? Double, -.infinity)
        XCTAssertEqual(fields[1].value as? Double, .infinity)
        assertSpring(
            Spring(mass: -1.0, stiffness: 90.0, damping: 12.0),
            duration: 0.493653659795374,
            bounce: 1.4714045207910318,
            response: 0.493653659795374,
            dampingRatio: -0.4714045207910317,
            mass: -1.0,
            stiffness: -162.0,
            damping: 12.0
        )
        assertSpring(
            Spring(mass: 1.2, stiffness: -90.0, damping: 12.0),
            duration: 0.561985178483258,
            bounce: 0.5527864045000421,
            response: 0.561985178483258,
            dampingRatio: 0.4472135954999579,
            mass: 1.2,
            stiffness: 150.0,
            damping: 12.0
        )
    }

    func testSpringAnimationLoweringsUseResponseAndMassNormalizedFields() throws {
        let durationBounce = Spring(duration: 0.50, bounce: 0.20)
        let fluid = try XCTUnwrap(Animation.spring(durationBounce, blendDuration: 0.10).box as? FluidSpringAnimationBox)
        XCTAssertDoubleEqual(fluid.response, 0.5)
        XCTAssertDoubleEqual(fluid.dampingFraction, 0.8)
        XCTAssertDoubleEqual(fluid.blendDuration, 0.10)

        let massSpring = Spring(mass: 1.2, stiffness: 90.0, damping: 12.0)
        let spring = try XCTUnwrap(Animation.interpolatingSpring(massSpring, initialVelocity: 0.30).box as? SpringAnimationBox)
        XCTAssertDoubleEqual(spring.mass, 1.0)
        XCTAssertDoubleEqual(spring.stiffness, 75.0)
        XCTAssertDoubleEqual(spring.damping, 10.0)
        XCTAssertDoubleEqual(spring.initialVelocity, 0.30)
    }

    // ASSERTIONS springModelDurationDisassemblyObserved
    // ASSERTIONS springModelStorageDisassemblyObserved
    func testSpringModelOwnsScalarAnimationLifetime() throws {
        let underdamped = SpringModel(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        XCTAssertEqual(
            underdamped.duration(epsilon: 0.001),
            1.4727003346780925,
            accuracy: 1.0e-12
        )

        let duration = 1.2
        let naturalFrequency = 2 * Double.pi / duration
        let critical = SpringModel(
            mass: 1,
            stiffness: naturalFrequency * naturalFrequency,
            damping: 2 * naturalFrequency,
            initialVelocity: 0
        )
        XCTAssertEqual(
            critical.duration(epsilon: 0.001),
            1.8,
            accuracy: 1.0e-12
        )

        let animation = Animation.interpolatingSpring(
            duration: duration,
            bounce: 0,
            initialVelocity: 0
        )
        let box = try XCTUnwrap(animation.box as? SpringAnimationBox)
        XCTAssertEqual(box.duration, duration, accuracy: 1.0e-12)
        XCTAssertEqual(box.terminalSamplingHorizon, 1.8, accuracy: 1.0e-12)
        XCTAssertEqual(
            box.terminalSamplingHorizon(for: Double(0.001)),
            1.8,
            accuracy: 1.0e-12
        )
        XCTAssertEqual(
            box.terminalSamplingHorizon(for: Double(1_000)),
            1.8,
            accuracy: 1.0e-12
        )
    }

    // ASSERTIONS fluidSpringExtremeControlledObserved
    // ASSERTIONS fluidSpringNonfiniteSettlingBranchObserved
    func testExtremeFluidSpringPreservesDivergenceAndTerminatesNonfiniteState() {
        var overflowContext = AnimationContext<Double>()
        let overflow = Animation.spring(duration: 0.5, bounce: -0.99)
        XCTAssertEqual(
            overflow.animate(value: 1, time: 0, context: &overflowContext),
            0
        )
        let overflowHalf = overflow.animate(
            value: 1,
            time: 0.5,
            context: &overflowContext
        )
        XCTAssertGreaterThan(abs(overflowHalf ?? 0), 1.0e100)
        let overflowOne = overflow.animate(
            value: 1,
            time: 1,
            context: &overflowContext
        )
        XCTAssertGreaterThan(abs(overflowOne ?? 0), 1.0e200)
        XCTAssertNil(
            overflow.animate(value: 1, time: 2, context: &overflowContext)
        )

        var boundaryContext = AnimationContext<Double>()
        let boundary = Animation.spring(duration: 0.5, bounce: -1)
        XCTAssertEqual(
            boundary.animate(value: 1, time: 0, context: &boundaryContext),
            0
        )
        XCTAssertNil(
            boundary.animate(value: 1, time: 0.1, context: &boundaryContext)
        )

        var divergentContext = AnimationContext<Double>()
        let divergent = Animation.spring(duration: 0.5, bounce: -0.97)
        _ = divergent.animate(value: 1, time: 0, context: &divergentContext)
        let divergentHalf = divergent.animate(
            value: 1,
            time: 0.5,
            context: &divergentContext
        )
        XCTAssertGreaterThan(abs(divergentHalf ?? 0), 1.0e20)
        XCTAssertNotNil(
            divergent.animate(value: 1, time: 2, context: &divergentContext)
        )
    }

    // ASSERTIONS fluidSpringCatchUpClampObserved
    func testFluidSpringGapContinuesFromOneFrameBeforeCurrentTime() {
        let stiffness = fluidSpringStiffness(response: 1.2)

        var catchUpState = SpringState<Double>()
        _ = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 0,
            state: &catchUpState
        )
        _ = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 0.25,
            state: &catchUpState
        )
        let catchUp = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 1.5,
            state: &catchUpState
        )

        var oneFrameState = SpringState<Double>()
        _ = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 0,
            state: &oneFrameState
        )
        _ = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 0.25,
            state: &oneFrameState
        )
        let oneFrame = integratedFluidSpringValue(
            target: 1,
            dampingFraction: 0.7,
            stiffness: stiffness,
            time: 0.25 + 1.0 / 60.0,
            state: &oneFrameState
        )

        XCTAssertEqual(catchUp, oneFrame, accuracy: 1.0e-12)
        XCTAssertEqual(catchUpState.time, 1.5, accuracy: 1.0e-12)
    }

    // ASSERTIONS springSettlingDurationDisassemblyObserved
    // ASSERTIONS springSettlingEdgeObserved
    func testSpringSettlingDurationMatchesAnalyticAndFallbackBranches() {
        let ordinary = Spring(response: 0.5, dampingRatio: 0.8)
        XCTAssertEqual(
            ordinary.settlingDuration,
            0.9261291683659721,
            accuracy: 1.0e-12
        )
        XCTAssertEqual(
            ordinary.settlingDuration(
                target: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            1.1533551689258155,
            accuracy: 1.0e-12
        )
        XCTAssertEqual(
            ordinary.settlingDuration(
                fromValue: 3.0,
                toValue: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            1.1170873407650654,
            accuracy: 1.0e-12
        )

        XCTAssertEqual(
            Spring(response: 0.5, dampingRatio: 1.0).settlingDuration,
            0.8,
            accuracy: 1.0e-12
        )
        XCTAssertEqual(
            Spring(response: 0.5, dampingRatio: 2.0).settlingDuration,
            2.1,
            accuracy: 1.0e-12
        )

        let zeroResponse = Spring(response: 0, dampingRatio: 0.8)
        XCTAssertEqual(zeroResponse.settlingDuration, 0)
        XCTAssertEqual(
            zeroResponse.settlingDuration(
                target: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            0
        )
        XCTAssertEqual(
            zeroResponse.settlingDuration(
                fromValue: 3.0,
                toValue: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            0
        )

        let infiniteResponse = Spring(response: .infinity, dampingRatio: 0.8)
        XCTAssertEqual(infiniteResponse.settlingDuration, .infinity)
        XCTAssertEqual(
            infiniteResponse.settlingDuration(
                target: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            .infinity
        )
        XCTAssertEqual(
            infiniteResponse.settlingDuration(
                fromValue: 3.0,
                toValue: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            .infinity
        )

        let nanResponse = Spring(response: .nan, dampingRatio: 0.8)
        XCTAssertEqual(nanResponse.settlingDuration, 0)
        XCTAssertEqual(
            nanResponse.settlingDuration(
                target: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            0
        )
        XCTAssertEqual(
            nanResponse.settlingDuration(
                fromValue: 3.0,
                toValue: 10.0,
                initialVelocity: 2.0,
                epsilon: 0.001
            ),
            0
        )

        let zeroStiffness = Spring(
            mass: 1,
            stiffness: 0,
            damping: 0
        )
        XCTAssertEqual(zeroStiffness.settlingDuration, .infinity)

        XCTAssertEqual(
            ordinary.settlingDuration(
                target: 1.0,
                initialVelocity: 0.0,
                epsilon: 0
            ),
            .infinity
        )
        XCTAssertEqual(
            ordinary.settlingDuration(
                target: 1.0,
                initialVelocity: 0.0,
                epsilon: -0.001
            ),
            0
        )
        XCTAssertEqual(
            ordinary.settlingDuration(
                target: 1.0,
                initialVelocity: 0.0,
                epsilon: .nan
            ),
            0
        )
        XCTAssertEqual(
            ordinary.settlingDuration(
                target: 1.0,
                initialVelocity: 0.0,
                epsilon: .infinity
            ),
            0
        )
    }
}

private func assertSpring(
    _ spring: Spring,
    duration: Double,
    bounce: Double,
    response: Double,
    dampingRatio: Double,
    mass: Double,
    stiffness: Double,
    damping: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertDoubleEqual(spring.duration, duration, file: file, line: line)
    XCTAssertDoubleEqual(spring.bounce, bounce, file: file, line: line)
    XCTAssertDoubleEqual(spring.response, response, file: file, line: line)
    XCTAssertDoubleEqual(spring.dampingRatio, dampingRatio, file: file, line: line)
    XCTAssertDoubleEqual(spring.mass, mass, file: file, line: line)
    XCTAssertDoubleEqual(spring.stiffness, stiffness, file: file, line: line)
    XCTAssertDoubleEqual(spring.damping, damping, file: file, line: line)
}

private func XCTAssertDoubleEqual(
    _ actual: Double,
    _ expected: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if expected.isNaN {
        XCTAssertTrue(actual.isNaN, "expected NaN, got \(actual)", file: file, line: line)
    } else if expected.isInfinite {
        XCTAssertEqual(actual, expected, file: file, line: line)
    } else {
        XCTAssertEqual(actual, expected, accuracy: 0.000_001, file: file, line: line)
    }
}
