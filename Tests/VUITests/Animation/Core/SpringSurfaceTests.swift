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
