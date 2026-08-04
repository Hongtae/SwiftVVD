import XCTest
@testable import VUI

final class AnimationStateKeyShapeTests: XCTestCase {
    func testSourceVisibleAnimationStateAndContextShape() {
        XCTAssertEqual(MemoryLayout<AnimationState<Double>>.size, 8)
        XCTAssertEqual(MemoryLayout<AnimationState<Double>>.stride, 8)
        XCTAssertEqual(MemoryLayout<AnimationState<Double>>.alignment, 8)

        var state = AnimationState<Double>()
        XCTAssertEqual(state[TestStateKey.self], 7)
        state[TestStateKey.self] = 42
        XCTAssertEqual(state[TestStateKey.self], 42)
        XCTAssertEqual(Mirror(reflecting: state).children.count, 1)

        XCTAssertEqual(MemoryLayout<AnimationContext<Double>>.size, 18)
        XCTAssertEqual(MemoryLayout<AnimationContext<Double>>.stride, 24)
        XCTAssertEqual(MemoryLayout<AnimationContext<Double>>.alignment, 8)

        let animation = Animation(SourceStateShapeAnimation())
        XCTAssertTrue(animation.base is SourceStateShapeAnimation)
    }

    func testHiddenAnimationStateKeyDefaultsUseSelfKeyedStorage() {
        let state = AnimationState<Double>()

        XCTAssertNil(state[AnimationFinishingDefinitionKey<Double>.self])

        let repeatState = state[RepeatState<Double>.self]
        XCTAssertEqual(repeatState.index, 0)
        XCTAssertEqual(repeatState.timeOffset, 0)

        let velocityState = state[VelocityState<Double>.self]
        XCTAssertTrue(velocityState.sampler.isEmpty)
        XCTAssertNil(velocityState.sampler.lastTime)
        XCTAssertEqual(velocityState.sampler.velocity.valuePerSecond, 0, accuracy: 0.000_001)

        XCTAssertTrue(state.combinedState.entries.isEmpty)

        let springState = state[SpringState<Double>.self]
        XCTAssertEqual(MemoryLayout<SpringState<Double>>.size, 56)
        XCTAssertEqual(MemoryLayout<SpringState<Double>>.stride, 56)
        XCTAssertEqual(MemoryLayout<SpringState<Double>>.alignment, 8)
        XCTAssertEqual(springState.offset, 0, accuracy: 0.000_001)
        XCTAssertEqual(springState.velocity, 0, accuracy: 0.000_001)
        XCTAssertEqual(springState.force, 0, accuracy: 0.000_001)
        XCTAssertEqual(springState.time, 0)
        XCTAssertEqual(springState.startTime, 0)
        XCTAssertEqual(springState.blendStart, 0)
        XCTAssertEqual(springState.blendInterval, 0)
    }

    func testHiddenAnimationStateKeysRoundTripIndependently() {
        var state = AnimationState<Double>()

        var velocityState = VelocityState<Double>()
        velocityState.sampler.addSample(1.0, time: 0)
        velocityState.sampler.addSample(3.0, time: 1)
        state[VelocityState<Double>.self] = velocityState

        state[RepeatState<Double>.self] = RepeatState(index: 2, timeOffset: 0.25)

        var childState = AnimationState<Double>()
        childState[RepeatState<Double>.self] = RepeatState(index: 7, timeOffset: 0.5)
        state.combinedState = CombinedAnimationState(
            entries: [
                CombinedAnimationState.Entry(value: 4.0, state: childState),
            ]
        )

        state[SpringState<Double>.self] = SpringState(
            offset: 0.3,
            velocity: 0.4,
            force: 0.5,
            time: 0.2,
            startTime: 0.55,
            blendStart: 0.6,
            blendInterval: 0.7
        )

        XCTAssertEqual(state[VelocityState<Double>.self].sampler.lastTime, 1)
        XCTAssertEqual(
            state[VelocityState<Double>.self].sampler.velocity.valuePerSecond,
            2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(state[RepeatState<Double>.self].index, 2)
        XCTAssertEqual(state[RepeatState<Double>.self].timeOffset, 0.25)
        XCTAssertEqual(state.combinedState.entries.map(\.value), [4.0])
        XCTAssertEqual(
            state.combinedState.entries.first?.state?[RepeatState<Double>.self].index,
            7
        )

        let springState = state[SpringState<Double>.self]
        XCTAssertEqual(springState.offset, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(springState.velocity, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(springState.force, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(springState.time, 0.2)
        XCTAssertEqual(springState.startTime, 0.55)
        XCTAssertEqual(springState.blendStart, 0.6)
        XCTAssertEqual(springState.blendInterval, 0.7)
    }

    func testAnimationContextHiddenStateAccessorsRoundTrip() {
        var context = AnimationContext<Double>()

        var velocityState = context.velocityState
        velocityState.sampler.addSample(2.0, time: 0)
        velocityState.sampler.addSample(5.0, time: 1)
        context.velocityState = velocityState

        context.finishingDefinition = TestFinishingDefinition.self
        context.isLogicallyComplete = true

        XCTAssertEqual(context.velocityState.sampler.lastTime, 1)
        XCTAssertEqual(context.velocityState.sampler.velocity.valuePerSecond, 3, accuracy: 0.000_001)
        XCTAssertTrue(context.shouldFinishEarly(data: .init(delta: 0, velocity: 0)))

        let transferred = context.withState(AnimationState<AnimatablePair<Double, Double>>())
        XCTAssertTrue(transferred.isLogicallyComplete)
        XCTAssertTrue(transferred.velocityState.sampler.isEmpty)
    }
}

private enum TestFinishingDefinition: AnimationFinishingDefinition {
    typealias Value = Double

    static func shouldFinishEarly(in context: AnimationSettlingContext<Double>) -> Bool {
        _ = context
        return true
    }
}

private struct TestStateKey: AnimationStateKey {
    static var defaultValue: Int { 7 }
}

private struct SourceStateShapeAnimation: CustomAnimation {
    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        value
    }
}
