import XCTest
@testable import VUI

final class AnimationNoRegisteredFallbackDelayTests: XCTestCase {
    func testDirectSpringDelayUsesCriteriaSpecificNoRegisteredFallbackOffsets() throws {
        let spring = Self.directSpring()
        let baseDelay = try noRegisteredDelay(spring)
        let frame = spring.box.defaultDisplayFrameInterval

        XCTAssertGreaterThan(baseDelay, spring.box.duration)
        XCTAssertEqual(
            try noRegisteredDelay(spring, criteria: .logicallyComplete),
            baseDelay,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(spring, criteria: .removed),
            baseDelay,
            accuracy: Self.accuracy
        )

        let delayed = spring.delay(0.20)
        XCTAssertEqual(
            try noRegisteredDelay(delayed, criteria: .logicallyComplete),
            baseDelay + 0.20,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(delayed, criteria: .removed),
            baseDelay + 0.20 + frame,
            accuracy: Self.accuracy
        )

        let negativeDelay = spring.delay(-0.20)
        XCTAssertEqual(
            try noRegisteredDelay(negativeDelay, criteria: .logicallyComplete),
            baseDelay - 0.20,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(negativeDelay, criteria: .removed),
            baseDelay - 0.20 + frame,
            accuracy: Self.accuracy
        )
    }

    func testDirectSpringRepeatUsesCriteriaSpecificNoRegisteredFallbackOffset() throws {
        let spring = Self.directSpring()
        let baseDelay = try noRegisteredDelay(spring)
        let frame = spring.box.defaultDisplayFrameInterval
        let repeated = spring.repeatCount(2)

        XCTAssertEqual(
            try noRegisteredDelay(repeated, criteria: .logicallyComplete),
            baseDelay * 2 - frame,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(repeated, criteria: .removed),
            baseDelay * 2,
            accuracy: Self.accuracy
        )
    }

    func testSpeedWrappedDirectSpringRepeatCollapsesNoRegisteredFallbackBoundary() throws {
        let spring = Self.directSpring()
        let baseDelay = try noRegisteredDelay(spring)
        let speedThenRepeat = spring.speed(2).repeatCount(2)
        let repeatThenSpeed = spring.repeatCount(2).speed(2)

        for animation in [speedThenRepeat, repeatThenSpeed] {
            XCTAssertEqual(
                try noRegisteredDelay(animation, criteria: .logicallyComplete),
                baseDelay,
                accuracy: Self.accuracy
            )
            XCTAssertEqual(
                try noRegisteredDelay(animation, criteria: .removed),
                baseDelay,
                accuracy: Self.accuracy
            )
        }
    }

    func testFluidAndDefaultResidualWrappersUseCriteriaInsensitiveNoRegisteredFallback() throws {
        let fluid = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0
        )
        let fluidDelay = try noRegisteredDelay(fluid)
        XCTAssertGreaterThan(fluidDelay, fluid.box.duration)
        try assertNoRegisteredDelay(fluid.delay(0.20), equals: fluidDelay + 0.20)
        try assertNoRegisteredDelay(fluid.repeatCount(2, autoreverses: false), equals: fluidDelay * 2)
        try assertNoRegisteredDelay(fluid.speed(2).repeatCount(2, autoreverses: false), equals: fluidDelay)
        try assertNoRegisteredDelay(fluid.delay(-0.20), equals: max(0, fluidDelay - 0.20))

        let defaultAnimation = Animation.default
        let defaultDelay = try noRegisteredDelay(defaultAnimation)
        XCTAssertGreaterThan(defaultDelay, defaultAnimation.box.duration)
        try assertNoRegisteredDelay(
            defaultAnimation.delay(0.20).repeatCount(2, autoreverses: false),
            equals: (defaultDelay + 0.20) * 2
        )
        try assertNoRegisteredDelay(
            defaultAnimation.speed(2).repeatCount(2, autoreverses: false),
            equals: defaultDelay
        )
        try assertNoRegisteredDelay(
            defaultAnimation.delay(-0.20),
            equals: max(0, defaultDelay - 0.20)
        )
    }

    func testSourceDefinedCustomNoRegisteredFallbackSamplesToNilBoundary() throws {
        let custom = Animation(UnitLinearAnimation(duration: 0.35))

        XCTAssertEqual(
            try noRegisteredDelay(custom),
            0.4,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(custom, criteria: .logicallyComplete),
            0.4,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(custom, criteria: .removed),
            0.4,
            accuracy: Self.accuracy
        )
    }

    func testFiniteSourceDefinedCustomWrappersApplyNoRegisteredFallbackTiming() throws {
        let custom = Animation(UnitLinearAnimation(duration: 0.35))
        let sampledNilBoundary = try noRegisteredDelay(custom)

        XCTAssertEqual(
            try noRegisteredDelay(custom.delay(0.20)),
            sampledNilBoundary + 0.20,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(custom.speed(2)),
            sampledNilBoundary / 2,
            accuracy: Self.accuracy
        )
        XCTAssertEqual(
            try noRegisteredDelay(custom.repeatCount(2)),
            sampledNilBoundary * 2,
            accuracy: Self.accuracy
        )
    }

    func testNonCustomInfiniteWrappersDoNotScheduleNoRegisteredFallback() {
        let finiteBase = Animation.linear(duration: 0.35)
        let infiniteAnimations = [
            finiteBase.repeatForever(autoreverses: false),
            finiteBase.speed(0),
            finiteBase.speed(-1),
            finiteBase.delay(0.20).repeatForever(autoreverses: false),
            finiteBase.repeatForever(autoreverses: false).delay(0.20),
        ]

        for animation in infiniteAnimations {
            XCTAssertNil(animation.box.noRegisteredCompletionDelay())
            XCTAssertNil(animation.box.noRegisteredCompletionDelay(for: .logicallyComplete))
            XCTAssertNil(animation.box.noRegisteredCompletionDelay(for: .removed))
        }
    }

    func testCircularUnitCurveUsesFiniteNoRegisteredFallbackFamilies() throws {
        let circular = Animation.timingCurve(.circularEaseInOut, duration: 0.30)
        try assertNoRegisteredDelay(circular, equals: 0.30)
        try assertNoRegisteredDelay(
            Animation.timingCurve(.circularEaseInOut, duration: 0.0),
            equals: 0
        )
        try assertNoRegisteredDelay(
            Animation.timingCurve(.circularEaseInOut, duration: 0.20).delay(0.25),
            equals: 0.45
        )
        try assertNoRegisteredDelay(
            Animation.timingCurve(.circularEaseInOut, duration: 0.60).speed(2.0),
            equals: 0.30
        )
        try assertNoRegisteredDelay(
            Animation.timingCurve(.circularEaseInOut, duration: 0.15)
                .repeatCount(3, autoreverses: false),
            equals: 0.45
        )

        let infinite = Animation.timingCurve(.circularEaseInOut, duration: 0.20)
            .repeatForever(autoreverses: false)
        XCTAssertNil(infinite.box.noRegisteredCompletionDelay())
        XCTAssertNil(infinite.box.noRegisteredCompletionDelay(for: .logicallyComplete))
        XCTAssertNil(infinite.box.noRegisteredCompletionDelay(for: .removed))
    }

    func testZeroEffectiveFiniteWrappersUseImmediateNoRegisteredFallbackDelay() throws {
        let zeroLinear = Animation.linear(duration: 0)
        let negativeDelay = Animation.linear(duration: 0.20).delay(-0.30)
        let zeroSpeededDelay = Animation.linear(duration: 0.20)
            .speed(2)
            .delay(-0.10)

        for animation in [zeroLinear, negativeDelay, zeroSpeededDelay] {
            XCTAssertEqual(
                try noRegisteredDelay(animation),
                0,
                accuracy: Self.accuracy
            )
            XCTAssertEqual(
                try noRegisteredDelay(animation, criteria: .logicallyComplete),
                0,
                accuracy: Self.accuracy
            )
            XCTAssertEqual(
                try noRegisteredDelay(animation, criteria: .removed),
                0,
                accuracy: Self.accuracy
            )
        }
    }

    private static let accuracy: TimeInterval = 0.000_000_1

    private static func directSpring() -> Animation {
        .interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
    }

    private func noRegisteredDelay(
        _ animation: Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TimeInterval {
        try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(),
            file: file,
            line: line
        )
    }

    private func noRegisteredDelay(
        _ animation: Animation,
        criteria: AnimationCompletionCriteria,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TimeInterval {
        try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: criteria),
            file: file,
            line: line
        )
    }

    private func assertNoRegisteredDelay(
        _ animation: Animation,
        equals expectedDelay: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try noRegisteredDelay(animation, file: file, line: line),
            expectedDelay,
            accuracy: Self.accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try noRegisteredDelay(animation, criteria: .logicallyComplete, file: file, line: line),
            expectedDelay,
            accuracy: Self.accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try noRegisteredDelay(animation, criteria: .removed, file: file, line: line),
            expectedDelay,
            accuracy: Self.accuracy,
            file: file,
            line: line
        )
    }
}
