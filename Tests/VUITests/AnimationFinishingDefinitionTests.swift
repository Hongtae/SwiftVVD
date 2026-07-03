import XCTest
@testable import VUI

final class AnimationFinishingDefinitionTests: XCTestCase {
    func testRotationEffectFinishingDefinitionRequiresAngleSettledAndAnchorUnchanged() {
        let context = makeAnimationContext(
            for: _RotationEffect.self,
            state: AnimationState<_RotationEffect.AnimatableData>(),
            environment: EnvironmentValues()
        )

        XCTAssertTrue(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(1.0, UnitPoint.zero.animatableData),
                    velocity: _RotationEffect.AnimatableData(0.5, UnitPoint.zero.animatableData)
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(1.28, UnitPoint.zero.animatableData),
                    velocity: _RotationEffect.AnimatableData(0.0, UnitPoint.zero.animatableData)
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(0.0, UnitPoint(x: .ulpOfOne, y: 0).animatableData),
                    velocity: _RotationEffect.AnimatableData(0.0, UnitPoint.zero.animatableData)
                )
            )
        )
    }

    func testViewFrameFinishingDefinitionUsesPixelLengthForOriginAndDoubleForSize() {
        var environment = EnvironmentValues()
        environment.defaultPixelLength = 2
        let context = makeAnimationContext(
            for: ViewFrame.self,
            state: AnimationState<ViewFrame.AnimatableData>(),
            environment: environment
        )

        XCTAssertTrue(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint(x: 1.0, y: 1.0).animatableData,
                        ViewSize(width: 3.0, height: 3.0).animatableData
                    ),
                    velocity: ViewFrame.AnimatableData(
                        CGPoint(x: 1.0, y: 1.0).animatableData,
                        ViewSize(width: 2.0, height: 2.0).animatableData
                    )
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint(x: 2.0, y: 0.0).animatableData,
                        ViewSize(width: 0.0, height: 0.0).animatableData
                    ),
                    velocity: .zero
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint.zero.animatableData,
                        ViewSize(width: 4.0, height: 0.0).animatableData
                    ),
                    velocity: .zero
                )
            )
        )
    }

    func testFluidSpringAnimateUsesInstalledViewFrameFinishingDefinition() {
        var environment = EnvironmentValues()
        environment.defaultPixelLength = 2
        let target = ViewFrame.AnimatableData(
            CGPoint(x: 1.0, y: 1.0).animatableData,
            ViewSize(width: 3.0, height: 3.0).animatableData
        )
        let spring = FluidSpringAnimationBox(
            response: 0.35,
            dampingFraction: 0.7,
            blendDuration: 0
        )

        var plainContext = AnimationContext<ViewFrame.AnimatableData>(
            state: AnimationState(),
            environment: environment
        )
        XCTAssertNotNil(
            spring.animate(value: target, time: 0, context: &plainContext)
        )

        var finishingContext = makeAnimationContext(
            for: ViewFrame.self,
            state: AnimationState<ViewFrame.AnimatableData>(),
            environment: environment
        )
        XCTAssertNil(
            spring.animate(value: target, time: 0, context: &finishingContext)
        )
    }

    func testDelayAndSpeedWrappersForwardExistingFinishingContext() throws {
        let target = Self.viewFrameTarget

        let delayRecorder = WrapperFinishingContextRecorder()
        var delayContext = Self.makeViewFrameFinishingContext()
        let delayed = Animation(
            WrapperFinishingContextProbeAnimation(recorder: delayRecorder, returnsNil: false)
        )
        .delay(0.25)

        _ = delayed.animate(value: target, time: 0.10, context: &delayContext)
        XCTAssertEqual(delayRecorder.observations, [true])

        let speedRecorder = WrapperFinishingContextRecorder()
        var speedContext = Self.makeViewFrameFinishingContext()
        let sped = Animation(
            WrapperFinishingContextProbeAnimation(recorder: speedRecorder, returnsNil: false)
        )
        .speed(2.0)

        _ = sped.animate(value: target, time: 0.10, context: &speedContext)
        XCTAssertEqual(speedRecorder.observations, [true])
    }

    func testRepeatNonFiniteCycleResetDoesNotCopyFinishingDefinition() {
        let recorder = WrapperFinishingContextRecorder()
        let repeated = Animation(
            WrapperFinishingContextProbeAnimation(recorder: recorder, returnsNil: true)
        )
        .repeatCount(2, autoreverses: false)

        var context = Self.makeViewFrameFinishingContext()
        _ = repeated.animate(value: Self.viewFrameTarget, time: 0, context: &context)
        XCTAssertEqual(recorder.observations, [true])

        XCTAssertNil(repeated.animate(value: Self.viewFrameTarget, time: 0.1, context: &context))
        XCTAssertEqual(recorder.observations, [true, false])
        XCTAssertNil(context.finishingDefinition)
        XCTAssertEqual(context.state[RepeatState<ViewFrame.AnimatableData>.self].iteration, 2)
    }

    private static var viewFrameTarget: ViewFrame.AnimatableData {
        ViewFrame.AnimatableData(
            CGPoint(x: 1.0, y: 1.0).animatableData,
            ViewSize(width: 3.0, height: 3.0).animatableData
        )
    }

    private static func makeViewFrameFinishingContext() -> AnimationContext<ViewFrame.AnimatableData> {
        makeAnimationContext(
            for: ViewFrame.self,
            state: AnimationState<ViewFrame.AnimatableData>(),
            environment: EnvironmentValues()
        )
    }
}

private final class WrapperFinishingContextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedObservations: [Bool] = []

    var observations: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedObservations
    }

    func append(_ value: Bool) {
        lock.lock()
        storedObservations.append(value)
        lock.unlock()
    }
}

private struct WrapperFinishingContextProbeAnimation: CustomAnimation, @unchecked Sendable {
    let recorder: WrapperFinishingContextRecorder
    let returnsNil: Bool

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        recorder.append(context.finishingDefinition != nil)
        return returnsNil ? nil : value
    }

    static func == (
        lhs: WrapperFinishingContextProbeAnimation,
        rhs: WrapperFinishingContextProbeAnimation
    ) -> Bool {
        lhs.recorder === rhs.recorder && lhs.returnsNil == rhs.returnsNil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(recorder))
        hasher.combine(returnsNil)
    }
}
