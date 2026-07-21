import XCTest
@testable import VUI

final class AnimationWrapperFactoryEdgeTests: XCTestCase {
    func testBezierCurveFactoriesPreserveRawNegativeDurationInStorageEqualityAndHash() throws {
        let negative = -0.20
        let linearZero = Animation.linear(duration: 0)
        let linearNegative = Animation.linear(duration: negative)
        let timingLinearNegative = Animation.timingCurve(0, 0, 1, 1, duration: negative)
        let timingLinearZero = Animation.timingCurve(0, 0, 1, 1, duration: 0)
        let easeInOutNegative = Animation.easeInOut(duration: negative)
        let timingEaseInOutNegative = Animation.timingCurve(0.42, 0, 0.58, 1, duration: negative)
        let timingEaseInOutZero = Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0)
        let unitLinearNegative = Animation.timingCurve(.linear, duration: negative)
        let unitLinearZero = Animation.timingCurve(.linear, duration: 0)
        let unitEaseInOutNegative = Animation.timingCurve(.easeInOut, duration: negative)
        let unitCustomBezierNegative = Animation.timingCurve(
            .bezier(
                startControlPoint: UnitPoint(x: 0.25, y: 0.10),
                endControlPoint: UnitPoint(x: 0.25, y: 1.0)
            ),
            duration: negative
        )
        let timingCustomBezierNegative = Animation.timingCurve(
            0.25,
            0.10,
            0.25,
            1.0,
            duration: negative
        )

        try assertBezier(linearZero, duration: 0)
        try assertBezier(linearNegative, duration: negative)
        try assertBezier(timingEaseInOutNegative, duration: negative)
        try assertBezier(unitLinearNegative, duration: negative)
        try assertBezier(unitCustomBezierNegative, duration: negative)

        XCTAssertNotEqual(linearNegative, linearZero)
        XCTAssertEqual(linearNegative, timingLinearNegative)
        XCTAssertHashEqual(linearNegative, timingLinearNegative)
        XCTAssertNotEqual(linearNegative, timingLinearZero)
        XCTAssertEqual(easeInOutNegative, timingEaseInOutNegative)
        XCTAssertHashEqual(easeInOutNegative, timingEaseInOutNegative)
        XCTAssertNotEqual(easeInOutNegative, timingEaseInOutZero)
        XCTAssertEqual(unitLinearNegative, linearNegative)
        XCTAssertHashEqual(unitLinearNegative, linearNegative)
        XCTAssertNotEqual(unitLinearNegative, unitLinearZero)
        XCTAssertEqual(unitEaseInOutNegative, easeInOutNegative)
        XCTAssertHashEqual(unitEaseInOutNegative, easeInOutNegative)
        XCTAssertEqual(unitCustomBezierNegative, timingCustomBezierNegative)
        XCTAssertHashEqual(unitCustomBezierNegative, timingCustomBezierNegative)
    }

    func testCircularUnitCurveFactoriesPreserveRawNegativeDurationInStorageEqualityAndHash() throws {
        let negative = -0.20
        let circularZero = Animation.timingCurve(.circularEaseInOut, duration: 0)
        let circularNegative = Animation.timingCurve(.circularEaseInOut, duration: negative)
        let circularNegativeFresh = Animation.timingCurve(.circularEaseInOut, duration: negative)

        try assertUnitCurve(circularZero, duration: 0)
        try assertUnitCurve(circularNegative, duration: negative)

        XCTAssertNotEqual(circularNegative, circularZero)
        XCTAssertEqual(circularNegative, circularNegativeFresh)
        XCTAssertHashEqual(circularNegative, circularNegativeFresh)
    }

    func testRepeatFactoriesPreserveRawCountAndAutoreversesInStorageEqualityAndHash() throws {
        let linear = Animation.linear(duration: 0.25)
        let repeatNegative = linear.repeatCount(-2, autoreverses: true)
        let repeatNegativeFresh = Animation.linear(duration: 0.25).repeatCount(-2, autoreverses: true)
        let repeatNegativeNoAuto = linear.repeatCount(-2, autoreverses: false)
        let repeatZero = linear.repeatCount(0, autoreverses: true)
        let repeatZeroNoAuto = linear.repeatCount(0, autoreverses: false)
        let repeatOne = linear.repeatCount(1, autoreverses: true)
        let repeatTwo = linear.repeatCount(2, autoreverses: true)
        let foreverAuto = linear.repeatForever(autoreverses: true)
        let foreverNoAuto = linear.repeatForever(autoreverses: false)

        try assertRepeat(repeatNegative, repeatCount: -2, autoreverses: true)
        try assertRepeat(repeatZero, repeatCount: 0, autoreverses: true)
        try assertRepeat(repeatOne, repeatCount: 1, autoreverses: true)
        try assertRepeat(foreverAuto, repeatCount: nil, autoreverses: true)

        XCTAssertEqual(repeatNegative, repeatNegativeFresh)
        XCTAssertHashEqual(repeatNegative, repeatNegativeFresh)
        XCTAssertNotEqual(repeatNegative, repeatZero)
        XCTAssertNotEqual(repeatNegative, repeatOne)
        XCTAssertNotEqual(repeatZero, repeatOne)
        XCTAssertNotEqual(repeatZero, repeatTwo)
        XCTAssertNotEqual(repeatNegative, repeatNegativeNoAuto)
        XCTAssertNotEqual(repeatZero, repeatZeroNoAuto)
        XCTAssertNotEqual(foreverAuto, foreverNoAuto)
    }

    func testDelayFactoriesPreserveRawModifierValuesInStorageEqualityAndHash() throws {
        let linear = Animation.linear(duration: 0.25)
        let delayNegative = linear.delay(-0.125)
        let delayNegativeFresh = Animation.linear(duration: 0.25).delay(-0.125)
        let delayZero = linear.delay(0.0)
        let delayNegativeZero = linear.delay(-0.0)
        let delayInfinity = linear.delay(.infinity)
        let delayNegativeInfinity = linear.delay(-.infinity)
        let delayNaN = linear.delay(.nan)
        let delayNaNCopy = delayNaN
        let delayNaNFresh = Animation.linear(duration: 0.25).delay(.nan)

        try assertDelay(delayNegative, delay: -0.125)
        try assertDelay(delayZero, delay: 0.0)
        try assertDelay(delayNegativeZero, delay: -0.0, sign: .minus)
        try assertDelay(delayInfinity, delay: .infinity)
        try assertDelay(delayNegativeInfinity, delay: -.infinity)
        try assertDelay(delayNaN, delay: .nan)

        XCTAssertEqual(delayNegative, delayNegativeFresh)
        XCTAssertHashEqual(delayNegative, delayNegativeFresh)
        XCTAssertNotEqual(delayNegative, delayZero)
        XCTAssertEqual(delayNegativeZero, delayZero)
        XCTAssertHashEqual(delayNegativeZero, delayZero)
        XCTAssertNotEqual(delayInfinity, delayNegativeInfinity)
        XCTAssertNotEqual(delayNaN, delayNaNCopy)
        XCTAssertHashEqual(delayNaN, delayNaNCopy)
        XCTAssertNotEqual(delayNaN, delayNaNFresh)
        XCTAssertHashEqual(delayNaN, delayNaNFresh)
    }

    func testSpeedFactoriesPreserveRawModifierValuesInStorageEqualityAndHash() throws {
        let linear = Animation.linear(duration: 0.25)
        let speedNegative = linear.speed(-1.5)
        let speedNegativeFresh = Animation.linear(duration: 0.25).speed(-1.5)
        let speedZero = linear.speed(0.0)
        let speedNegativeZero = linear.speed(-0.0)
        let speedInfinity = linear.speed(.infinity)
        let speedNegativeInfinity = linear.speed(-.infinity)
        let speedNaN = linear.speed(.nan)
        let speedNaNCopy = speedNaN
        let speedNaNFresh = Animation.linear(duration: 0.25).speed(.nan)

        try assertSpeed(speedNegative, speed: -1.5)
        try assertSpeed(speedZero, speed: 0.0)
        try assertSpeed(speedNegativeZero, speed: -0.0, sign: .minus)
        try assertSpeed(speedInfinity, speed: .infinity)
        try assertSpeed(speedNegativeInfinity, speed: -.infinity)
        try assertSpeed(speedNaN, speed: .nan)

        XCTAssertEqual(speedNegative, speedNegativeFresh)
        XCTAssertHashEqual(speedNegative, speedNegativeFresh)
        XCTAssertNotEqual(speedNegative, speedZero)
        XCTAssertEqual(speedNegativeZero, speedZero)
        XCTAssertHashEqual(speedNegativeZero, speedZero)
        XCTAssertNotEqual(speedInfinity, speedNegativeInfinity)
        XCTAssertNotEqual(speedNaN, speedNaNCopy)
        XCTAssertHashEqual(speedNaN, speedNaNCopy)
        XCTAssertNotEqual(speedNaN, speedNaNFresh)
        XCTAssertHashEqual(speedNaN, speedNaNFresh)
    }
}

private func assertBezier(
    _ animation: Animation,
    duration: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? BezierAnimationBox, file: file, line: line)
    XCTAssertDoubleStorageEqual(box.storedDuration, duration, file: file, line: line)
}

private func assertUnitCurve(
    _ animation: Animation,
    duration: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? UnitCurveAnimationBox, file: file, line: line)
    XCTAssertDoubleStorageEqual(box.storedDuration, duration, file: file, line: line)
}

private func assertRepeat(
    _ animation: Animation,
    repeatCount: Int?,
    autoreverses: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? RepeatAnimationBox, file: file, line: line)
    XCTAssertEqual(box.repeatCount, repeatCount, file: file, line: line)
    XCTAssertEqual(box.autoreverses, autoreverses, file: file, line: line)
    XCTAssertTrue(box.base is BezierAnimationBox, file: file, line: line)
}

private func assertDelay(
    _ animation: Animation,
    delay: TimeInterval,
    sign: FloatingPointSign? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? DelayAnimationBox, file: file, line: line)
    XCTAssertDoubleStorageEqual(box.delay, delay, file: file, line: line)
    if let sign {
        XCTAssertEqual(box.delay.sign, sign, file: file, line: line)
    }
    XCTAssertTrue(box.base is BezierAnimationBox, file: file, line: line)
}

private func assertSpeed(
    _ animation: Animation,
    speed: Double,
    sign: FloatingPointSign? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let box = try XCTUnwrap(animation.box as? SpeedAnimationBox, file: file, line: line)
    XCTAssertDoubleStorageEqual(box.speed, speed, file: file, line: line)
    if let sign {
        XCTAssertEqual(box.speed.sign, sign, file: file, line: line)
    }
    XCTAssertTrue(box.base is BezierAnimationBox, file: file, line: line)
}

private func XCTAssertDoubleStorageEqual(
    _ actual: Double,
    _ expected: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if expected.isNaN {
        XCTAssertTrue(actual.isNaN, "expected NaN, got \(actual)", file: file, line: line)
    } else {
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

private func XCTAssertHashEqual(
    _ lhs: Animation,
    _ rhs: Animation,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var lhsHasher = Hasher()
    lhs.hash(into: &lhsHasher)
    var rhsHasher = Hasher()
    rhs.hash(into: &rhsHasher)
    XCTAssertEqual(lhsHasher.finalize(), rhsHasher.finalize(), file: file, line: line)
}
