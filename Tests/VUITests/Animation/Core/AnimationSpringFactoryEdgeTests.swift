import XCTest
@testable import VUI

final class AnimationSpringFactoryEdgeTests: XCTestCase {
    func testDurationBounceFluidSpringFactoriesPreserveEdgeStorage() throws {
        try assertFluidSpring(
            Animation.spring(duration: 0.50, bounce: -0.50, blendDuration: 0.10),
            response: 0.50,
            dampingFraction: 2.0,
            blendDuration: 0.10
        )
        XCTAssertEqual(
            Animation.spring(duration: 0.50, bounce: -0.50, blendDuration: 0.10),
            Animation.spring(response: 0.50, dampingFraction: 2.0, blendDuration: 0.10)
        )

        try assertFluidSpring(
            Animation.spring(duration: 0.50, bounce: 1.20, blendDuration: 0.10),
            response: 0.50,
            dampingFraction: 0.0,
            blendDuration: 0.10
        )
        XCTAssertEqual(
            Animation.spring(duration: 0.50, bounce: 1.20, blendDuration: 0.10),
            Animation.spring(response: 0.50, dampingFraction: 0.0, blendDuration: 0.10)
        )

        try assertFluidSpring(
            Animation.spring(duration: 0.0, bounce: 0.20, blendDuration: 0.10),
            response: 0.0,
            dampingFraction: 0.8,
            blendDuration: 0.10
        )
        XCTAssertEqual(
            Animation.spring(duration: 0.0, bounce: 0.20, blendDuration: 0.10),
            Animation.spring(response: 0.0, dampingFraction: 0.8, blendDuration: 0.10)
        )
        try assertFluidSpring(
            Animation.spring(duration: -0.20, bounce: 0.20, blendDuration: 0.10),
            response: -0.20,
            dampingFraction: 0.8,
            blendDuration: 0.10
        )
        XCTAssertEqual(
            Animation.spring(duration: -0.20, bounce: 0.20, blendDuration: 0.10),
            Animation.spring(response: -0.20, dampingFraction: 0.8, blendDuration: 0.10)
        )
    }

    func testFluidSpringAliasesUseDurationBounceOffsets() throws {
        try assertFluidSpring(
            Animation.interactiveSpring(duration: 0.15, extraBounce: -0.30, blendDuration: 0.25),
            response: 0.15,
            dampingFraction: 1.0 / 0.85,
            blendDuration: 0.25
        )
        XCTAssertEqual(
            Animation.interactiveSpring(duration: 0.15, extraBounce: -0.30, blendDuration: 0.25),
            Animation.spring(duration: 0.15, bounce: -0.15, blendDuration: 0.25)
        )

        try assertFluidSpring(
            Animation.interactiveSpring(duration: 0.15, extraBounce: 1.20, blendDuration: 0.25),
            response: 0.15,
            dampingFraction: 0.0,
            blendDuration: 0.25
        )
        XCTAssertEqual(
            Animation.interactiveSpring(duration: 0.15, extraBounce: 1.20, blendDuration: 0.25),
            Animation.spring(duration: 0.15, bounce: 1.35, blendDuration: 0.25)
        )

        try assertFluidSpring(
            Animation.interactiveSpring(duration: 0.0, extraBounce: 0.05, blendDuration: 0.25),
            response: 0.0,
            dampingFraction: 0.8,
            blendDuration: 0.25
        )
        try assertFluidSpring(
            Animation.interactiveSpring(duration: -0.20, extraBounce: 0.05, blendDuration: 0.25),
            response: -0.20,
            dampingFraction: 0.8,
            blendDuration: 0.25
        )

        try assertFluidSpring(
            Animation.smooth(duration: 0.50, extraBounce: -0.50),
            response: 0.50,
            dampingFraction: 2.0,
            blendDuration: 0.0
        )
        XCTAssertEqual(
            Animation.smooth(duration: 0.50, extraBounce: -0.50),
            Animation.spring(duration: 0.50, bounce: -0.50)
        )
        try assertFluidSpring(
            Animation.smooth(duration: 0.50, extraBounce: 1.20),
            response: 0.50,
            dampingFraction: 0.0,
            blendDuration: 0.0
        )
        try assertFluidSpring(
            Animation.smooth(duration: 0.0, extraBounce: 0.20),
            response: 0.0,
            dampingFraction: 0.8,
            blendDuration: 0.0
        )

        try assertFluidSpring(
            Animation.snappy(duration: 0.50, extraBounce: -0.50),
            response: 0.50,
            dampingFraction: 1.0 / 0.65,
            blendDuration: 0.0
        )
        XCTAssertEqual(
            Animation.snappy(duration: 0.50, extraBounce: -0.50),
            Animation.spring(duration: 0.50, bounce: -0.35)
        )
        try assertFluidSpring(
            Animation.snappy(duration: 0.50, extraBounce: 1.20),
            response: 0.50,
            dampingFraction: 0.0,
            blendDuration: 0.0
        )
        try assertFluidSpring(
            Animation.snappy(duration: -0.20, extraBounce: 0.05),
            response: -0.20,
            dampingFraction: 0.8,
            blendDuration: 0.0
        )

        try assertFluidSpring(
            Animation.bouncy(duration: 0.50, extraBounce: -0.50),
            response: 0.50,
            dampingFraction: 1.25,
            blendDuration: 0.0
        )
        XCTAssertEqual(
            Animation.bouncy(duration: 0.50, extraBounce: -0.50),
            Animation.spring(duration: 0.50, bounce: -0.20)
        )
        try assertFluidSpring(
            Animation.bouncy(duration: 0.50, extraBounce: 1.20),
            response: 0.50,
            dampingFraction: 0.0,
            blendDuration: 0.0
        )
        try assertFluidSpring(
            Animation.bouncy(duration: -0.20, extraBounce: -0.10),
            response: -0.20,
            dampingFraction: 0.8,
            blendDuration: 0.0
        )
    }

    func testDurationBounceSpringAnimationFactoriesPreserveEdgeStorage() throws {
        let stiffness = pow(2.0 * Double.pi / 0.50, 2)

        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: 0.50, bounce: -0.50, initialVelocity: 0.30),
            stiffness: stiffness,
            damping: 2.0 * sqrt(stiffness) * 2.0,
            initialVelocity: 0.30
        )
        XCTAssertEqual(
            Animation.interpolatingSpring(duration: 0.50, bounce: -0.50, initialVelocity: 0.30),
            Animation.interpolatingSpring(
                mass: 1.0,
                stiffness: stiffness,
                damping: 2.0 * sqrt(stiffness) * 2.0,
                initialVelocity: 0.30
            )
        )

        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: 0.50, bounce: 1.20, initialVelocity: 0.30),
            stiffness: stiffness,
            damping: 0.0,
            initialVelocity: 0.30
        )

        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: 0.0, bounce: 0.20, initialVelocity: 0.30),
            stiffness: .infinity,
            damping: .infinity,
            initialVelocity: 0.30
        )
        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: -0.20, bounce: 0.20, initialVelocity: 0.30),
            stiffness: .infinity,
            damping: .infinity,
            initialVelocity: 0.30
        )
        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: 0.0, bounce: 1.20, initialVelocity: 0.30),
            stiffness: .infinity,
            damping: .nan,
            initialVelocity: 0.30
        )
        try assertSpringAnimation(
            Animation.interpolatingSpring(duration: -0.20, bounce: 1.20, initialVelocity: 0.30),
            stiffness: .infinity,
            damping: .nan,
            initialVelocity: 0.30
        )
    }

    func testInterpolatingSpringWithInfiniteStiffnessIsRuntimeImmediate() {
        let animations = [
            Animation.interpolatingSpring(duration: 0.0, bounce: 0.20, initialVelocity: 0.30),
            Animation.interpolatingSpring(duration: -0.20, bounce: 0.20, initialVelocity: 0.30),
            Animation.interpolatingSpring(duration: 0.0, bounce: 1.20, initialVelocity: 0.30),
            Animation.interpolatingSpring(duration: -0.20, bounce: 1.20, initialVelocity: 0.30),
        ]

        for animation in animations {
            XCTAssertTrue(animation.box.isImmediatelyComplete)

            var context = AnimationContext<Double>()
            XCTAssertNil(animation.animate(value: 1.0, time: 0, context: &context))
            XCTAssertTrue(context.isLogicallyComplete)
        }
    }
}

private func assertFluidSpring(
    _ animation: Animation,
    response: TimeInterval,
    dampingFraction: Double,
    blendDuration: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? FluidSpringAnimationBox, file: file, line: line)
    XCTAssertDoubleEqual(box.response, response, file: file, line: line)
    XCTAssertDoubleEqual(box.dampingFraction, dampingFraction, file: file, line: line)
    XCTAssertDoubleEqual(box.blendDuration, blendDuration, file: file, line: line)
}

private func assertSpringAnimation(
    _ animation: Animation,
    mass: Double = 1.0,
    stiffness: Double,
    damping: Double,
    initialVelocity: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? SpringAnimationBox, file: file, line: line)
    XCTAssertDoubleEqual(box.mass, mass, file: file, line: line)
    XCTAssertDoubleEqual(box.stiffness, stiffness, file: file, line: line)
    XCTAssertDoubleEqual(box.damping, damping, file: file, line: line)
    XCTAssertDoubleEqual(box.initialVelocity, initialVelocity, file: file, line: line)
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
        XCTAssertEqual(actual, expected, accuracy: 0.000_000_000_001, file: file, line: line)
    }
}
