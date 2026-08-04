import XCTest
@testable import VUI

final class AnimationIdentitySurfaceTests: XCTestCase {
    func testAnimationLayoutAndMirrorShape() {
        XCTAssertEqual(MemoryLayout<Animation>.size, 8)
        XCTAssertEqual(MemoryLayout<Animation>.stride, 8)
        XCTAssertEqual(MemoryLayout<Animation>.alignment, 8)

        let mirror = Animation.linear(duration: 0.25).customMirror
        XCTAssertEqual(String(describing: mirror.subjectType), "Animation")
        XCTAssertEqual(mirror.children.count, 1)
        XCTAssertEqual(mirror.children.first?.label, "base")
    }

    func testBuiltInFactoryIdentityAndHashSurface() {
        let linear = Animation.linear(duration: 0.25)

        assertIdentity("default copy", Animation.default, Animation.default, equal: true)
        assertIdentity("linear same factory", linear, Animation.linear(duration: 0.25), equal: true)
        assertIdentity("linear property default duration", Animation.linear, Animation.linear(duration: 0.35), equal: true)
        assertIdentity("easeInOut property default duration", Animation.easeInOut, Animation.easeInOut(duration: 0.35), equal: true)
        assertIdentity("easeIn property default duration", Animation.easeIn, Animation.easeIn(duration: 0.35), equal: true)
        assertIdentity("easeOut property default duration", Animation.easeOut, Animation.easeOut(duration: 0.35), equal: true)
        assertIdentity(
            "timingCurve default duration",
            Animation.timingCurve(0.1, 0.2, 0.3, 0.4),
            Animation.timingCurve(0.1, 0.2, 0.3, 0.4, duration: 0.35),
            equal: true
        )

        assertIdentity("delay fresh base same modifier", linear.delay(0.10), Animation.linear(duration: 0.25).delay(0.10), equal: true)
        assertIdentity("speed fresh base same modifier", linear.speed(2.0), Animation.linear(duration: 0.25).speed(2.0), equal: true)
        assertIdentity("speed different modifier", linear.speed(2.0), linear.speed(3.0), equal: false)
        assertIdentity(
            "repeat fresh base same modifier",
            linear.repeatCount(3, autoreverses: true),
            Animation.linear(duration: 0.25).repeatCount(3, autoreverses: true),
            equal: true
        )
        assertIdentity("repeat different count", linear.repeatCount(3, autoreverses: true), linear.repeatCount(2, autoreverses: true), equal: false)
        assertIdentity(
            "repeat different autoreverses",
            linear.repeatCount(3, autoreverses: true),
            linear.repeatCount(3, autoreverses: false),
            equal: false
        )
        assertIdentity(
            "forever fresh base same modifier",
            linear.repeatForever(autoreverses: true),
            Animation.linear(duration: 0.25).repeatForever(autoreverses: true),
            equal: true
        )
        assertIdentity(
            "forever different autoreverses",
            linear.repeatForever(autoreverses: true),
            linear.repeatForever(autoreverses: false),
            equal: false
        )
        assertIdentity(
            "delay speed fresh chain",
            linear.delay(0.10).speed(2.0),
            Animation.linear(duration: 0.25).delay(0.10).speed(2.0),
            equal: true
        )
        assertIdentity("delay speed vs speed delay", linear.delay(0.10).speed(2.0), linear.speed(2.0).delay(0.10), equal: false)
        assertIdentity("nested delay vs collapsed delay", linear.delay(0.10).delay(0.20), linear.delay(0.30), equal: false)
    }

    func testSpringAndSourceCustomIdentityAndHashSurface() {
        assertIdentity(
            "spring same factory",
            Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2),
            Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2),
            equal: true
        )
        assertIdentity(
            "spring different response",
            Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2),
            Animation.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2),
            equal: false
        )
        assertIdentity("spring property call", Animation.spring, Animation.spring(), equal: true)
        assertIdentity(
            "spring duration vs response overload",
            Animation.spring(duration: 0.5, bounce: 0.0, blendDuration: 0.0),
            Animation.spring(response: 0.5, dampingFraction: 1.0, blendDuration: 0.0),
            equal: true
        )
        assertIdentity("default vs spring property", Animation.default, Animation.spring, equal: false)
        assertIdentity("interactiveSpring property call", Animation.interactiveSpring, Animation.interactiveSpring(), equal: true)
        assertIdentity(
            "interactiveSpring duration vs response overload",
            Animation.interactiveSpring(duration: 0.15, extraBounce: 0.0, blendDuration: 0.25),
            Animation.interactiveSpring(response: 0.15, dampingFraction: 0.85, blendDuration: 0.25),
            equal: true
        )
        assertIdentity(
            "interpolating same factory",
            Animation.interpolatingSpring(mass: 1.0, stiffness: 200.0, damping: 20.0, initialVelocity: 0.5),
            Animation.interpolatingSpring(mass: 1.0, stiffness: 200.0, damping: 20.0, initialVelocity: 0.5),
            equal: true
        )
        assertIdentity(
            "interpolating different velocity",
            Animation.interpolatingSpring(mass: 1.0, stiffness: 200.0, damping: 20.0, initialVelocity: 0.5),
            Animation.interpolatingSpring(mass: 1.0, stiffness: 200.0, damping: 20.0, initialVelocity: 0.6),
            equal: false
        )
        assertIdentity("smooth same factory", Animation.smooth(duration: 0.6, extraBounce: 0.1), Animation.smooth(duration: 0.6, extraBounce: 0.1), equal: true)
        assertIdentity("smooth vs snappy", Animation.smooth(duration: 0.6, extraBounce: 0.1), Animation.snappy(duration: 0.6, extraBounce: 0.1), equal: false)
        assertIdentity("snappy vs bouncy", Animation.snappy(duration: 0.6, extraBounce: 0.1), Animation.bouncy(duration: 0.6, extraBounce: 0.1), equal: false)
        assertIdentity("smooth property call", Animation.smooth, Animation.smooth(), equal: true)
        assertIdentity("snappy property call", Animation.snappy, Animation.snappy(), equal: true)
        assertIdentity("bouncy property call", Animation.bouncy, Animation.bouncy(), equal: true)

        let custom = Animation(SourceIdentityAnimation(id: 1))
        assertIdentity("custom same source value", custom, Animation(SourceIdentityAnimation(id: 1)), equal: true)
        assertIdentity("custom different source value", custom, Animation(SourceIdentityAnimation(id: 2)), equal: false)
        assertIdentity(
            "custom delay same source value",
            custom.delay(0.10),
            Animation(SourceIdentityAnimation(id: 1)).delay(0.10),
            equal: true
        )
        assertIdentity(
            "custom delay different source value",
            custom.delay(0.10),
            Animation(SourceIdentityAnimation(id: 2)).delay(0.10),
            equal: false
        )
        assertIdentity("custom delay different modifier", custom.delay(0.10), custom.delay(0.20), equal: false)
        assertIdentity("custom speed same source value", custom.speed(2.0), Animation(SourceIdentityAnimation(id: 1)).speed(2.0), equal: true)
        assertIdentity(
            "custom repeat same source value",
            custom.repeatCount(2, autoreverses: false),
            Animation(SourceIdentityAnimation(id: 1)).repeatCount(2, autoreverses: false),
            equal: true
        )
    }

    // ASSERTIONS animationFactoryAliasIdentityObserved
    func testFluidSpringFactoryAliasesHaveNoStoredFactoryIdentity() {
        assertIdentity(
            "spring duration vs smooth collision",
            Animation.spring(duration: 0.5, bounce: 0.2),
            Animation.smooth(duration: 0.5, extraBounce: 0.2),
            equal: true
        )
        assertIdentity(
            "spring duration vs snappy collision",
            Animation.spring(duration: 0.45, bounce: 0.15),
            Animation.snappy(duration: 0.45),
            equal: true
        )
        assertIdentity(
            "spring property vs smooth property collision",
            Animation.spring,
            Animation.smooth(),
            equal: true
        )
        assertIdentity(
            "nearby bounce values remain distinct",
            Animation.spring(duration: 0.5, bounce: 0.2),
            Animation.spring(duration: 0.5, bounce: 0.2000000001),
            equal: false
        )
    }
}

private struct SourceIdentityAnimation: CustomAnimation {
    var id: Int

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        value
    }
}

private func assertIdentity(
    _ label: String,
    _ lhs: Animation,
    _ rhs: Animation,
    equal expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs == rhs, expected, "\(label) equality", file: file, line: line)
    XCTAssertEqual(hashString(lhs) == hashString(rhs), expected, "\(label) hash equality", file: file, line: line)
}

private func hashString(_ animation: Animation) -> String {
    var hasher = Hasher()
    animation.hash(into: &hasher)
    return String(hasher.finalize())
}
