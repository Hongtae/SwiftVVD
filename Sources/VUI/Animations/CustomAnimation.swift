//
//  File: CustomAnimation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol AnimationStateKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct AnimationState<Value> where Value: VectorArithmetic {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {
    }

    public subscript<K>(key: K.Type) -> K.Value where K: AnimationStateKey {
        get {
            storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }
}

@available(*, unavailable)
extension AnimationState: Sendable {
}

struct AnimationSettlingContext<Value: VectorArithmetic> {
    struct Data {
        var delta: Value
        var velocity: Value

        init(delta: Value, velocity: Value) {
            self.delta = delta
            self.velocity = velocity
        }
    }

    var data: Data
    var environment: EnvironmentValues

    var delta: Value {
        data.delta
    }

    var velocity: Value {
        data.velocity
    }

    init(data: Data, environment: EnvironmentValues) {
        self.data = data
        self.environment = environment
    }

    init(delta: Value, velocity: Value, environment: EnvironmentValues) {
        self.init(
            data: Data(delta: delta, velocity: velocity),
            environment: environment
        )
    }
}

protocol AnimationFinishingDefinition<Value> {
    associatedtype Value: VectorArithmetic

    static func shouldFinishEarly(in context: AnimationSettlingContext<Value>) -> Bool
}

protocol ExtendedAnimatable: Animatable, AnimationFinishingDefinition where AnimatableData == Value {
}

struct AnimationFinishingDefinitionKey<AnimatableValue: VectorArithmetic>: AnimationStateKey {
    typealias Value = (any AnimationFinishingDefinition<AnimatableValue>.Type)?

    static var defaultValue: Value {
        nil
    }
}

struct RepeatState<AnimatableValue: VectorArithmetic>: AnimationStateKey {
    typealias Value = RepeatState<AnimatableValue>

    var index: Int = 0
    var timeOffset: TimeInterval = 0

    static var defaultValue: RepeatState<AnimatableValue> {
        RepeatState()
    }
}

struct VelocityState<AnimatableValue: VectorArithmetic>: AnimationStateKey {
    typealias Value = VelocityState<AnimatableValue>

    var sampler: VelocitySampler<AnimatableValue>

    init(sampler: VelocitySampler<AnimatableValue> = VelocitySampler()) {
        self.sampler = sampler
    }

    static var defaultValue: VelocityState<AnimatableValue> {
        VelocityState()
    }
}

struct VelocityTrackingAnimation: CustomAnimation {
    private static let decayPerMillisecond = 0.9880293350219727
    private static let activityWindow: TimeInterval = 2

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        var velocityState = context.velocityState
        if velocityState.sampler.isEmpty {
            velocityState.sampler.addSample(value, time: time)
            context.velocityState = velocityState
        }

        let activeUntil = (velocityState.sampler.lastTime ?? 0) + Self.activityWindow
        let projectedVelocity = velocity(value: value, time: time, context: context)
        if let projectedVelocity, projectedVelocity == .zero {
            return nil
        }
        return activeUntil > time ? value : nil
    }

    nonisolated func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        let velocityState = context.velocityState
        let lastTime = velocityState.sampler.lastTime ?? 0
        let decay = pow(Self.decayPerMillisecond, (time - lastTime) * 1000)
        var velocity = velocityState.sampler.velocity.valuePerSecond
        velocity.scale(by: decay)
        return velocity
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        var velocityState = context.velocityState
        velocityState.sampler.addSample(value, time: time)
        context.velocityState = velocityState
        return true
    }
}

struct CombinedAnimationState<AnimatableValue: VectorArithmetic>: AnimationStateKey {
    typealias Value = CombinedAnimationState<AnimatableValue>

    struct Entry {
        var value: AnimatableValue
        var state: AnimationState<AnimatableValue>?
    }

    var entries: [Entry] = []

    static var defaultValue: CombinedAnimationState<AnimatableValue> {
        CombinedAnimationState()
    }
}

extension AnimationState {
    var combinedState: CombinedAnimationState<Value> {
        get {
            self[CombinedAnimationState<Value>.self]
        }
        set {
            self[CombinedAnimationState<Value>.self] = newValue
        }
    }
}

struct DefaultCombiningAnimation: CustomAnimation {
    struct Entry: Hashable {
        var animation: Animation
        var elapsed: TimeInterval
    }

    var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    init(first: Animation, firstElapsed: TimeInterval, second: Animation) {
        if let box = first.box as? CustomAnimationBox<DefaultCombiningAnimation> {
            var entries = box.base.entries
            entries.append(Entry(animation: second, elapsed: firstElapsed))
            self.entries = entries
        } else {
            self.entries = [
                Entry(animation: first, elapsed: 0),
                Entry(animation: second, elapsed: firstElapsed),
            ]
        }
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        var combinedState = context.state.combinedState
        guard entries.count == combinedState.entries.count,
              !entries.isEmpty else {
            return nil
        }

        var output = Value.zero
        var lastChildIsLogicallyComplete = false
        var nextEntries = combinedState.entries

        for index in entries.indices {
            guard var childState = nextEntries[index].state else {
                if index == entries.indices.last {
                    combinedState.entries = nextEntries
                    context.state.combinedState = combinedState
                    return nil
                }
                output = nextEntries[index].value
                continue
            }

            var childValue = nextEntries[index].value
            childValue -= output
            let localTime = time - entries[index].elapsed
            var childContext = context.withState(childState)
            guard let childOutput = entries[index].animation.animate(
                value: childValue,
                time: localTime,
                context: &childContext
            ) else {
                nextEntries[index].state = nil
                if index == entries.indices.last {
                    combinedState.entries = nextEntries
                    context.state.combinedState = combinedState
                    context.isLogicallyComplete =
                        childContext.isLogicallyComplete
                    return nil
                }
                output = nextEntries[index].value
                continue
            }

            output += childOutput
            childState = childContext.state
            nextEntries[index].state = childState
            if index == entries.indices.last {
                lastChildIsLogicallyComplete = childContext.isLogicallyComplete
            }
        }

        combinedState.entries = nextEntries
        context.state.combinedState = combinedState
        context.isLogicallyComplete = lastChildIsLogicallyComplete
        return output
    }
}

func combineAnimation<Value>(
    into animation: inout Animation,
    state: inout AnimationState<Value>,
    value: Value,
    elapsed: TimeInterval,
    newAnimation: Animation,
    newValue: Value
) where Value: VectorArithmetic {
    var replacementValue = value
    replacementValue += newValue

    if animation.box is CustomAnimationBox<DefaultCombiningAnimation> {
        var combinedState = state.combinedState
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: replacementValue,
                state: AnimationState()
            )
        )
        // An existing combining animation keeps its outer state dictionary;
        // only the child-entry array grows on a later false-merge retarget.
        state.combinedState = combinedState
    } else {
        let previousState = state
        var combinedState = CombinedAnimationState<Value>()
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: value,
                state: previousState
            )
        )
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: replacementValue,
                state: AnimationState()
            )
        )
        // The first conversion moves the prior animation state into the first
        // child and installs the combined state into a fresh outer dictionary.
        state = AnimationState()
        state.combinedState = combinedState
    }
    animation = Animation(
        DefaultCombiningAnimation(
            first: animation,
            firstElapsed: elapsed,
            second: newAnimation
        )
    )
}

private final class AnimationContextEnvironmentBox {
    var value: EnvironmentValues

    init(_ value: EnvironmentValues) {
        self.value = value
    }
}

public struct AnimationContext<Value> where Value: VectorArithmetic {
    public var state: AnimationState<Value>
    private var environmentBox: AnimationContextEnvironmentBox
    public var isLogicallyComplete: Bool
    // Reserved storage byte retained as part of this value's observed layout.
    private var storageTag: UInt8

    public var environment: EnvironmentValues {
        environmentBox.value
    }

    init(
        state: AnimationState<Value> = AnimationState(),
        isLogicallyComplete: Bool = false,
        environment: EnvironmentValues = EnvironmentValues()
    ) {
        self.state = state
        self.environmentBox = AnimationContextEnvironmentBox(environment)
        self.isLogicallyComplete = isLogicallyComplete
        self.storageTag = 0
    }

    private init(
        state: AnimationState<Value>,
        isLogicallyComplete: Bool,
        environmentBox: AnimationContextEnvironmentBox,
        storageTag: UInt8
    ) {
        self.state = state
        self.environmentBox = environmentBox
        self.isLogicallyComplete = isLogicallyComplete
        self.storageTag = storageTag
    }

    var finishingDefinition: (any AnimationFinishingDefinition<Value>.Type)? {
        get {
            state[AnimationFinishingDefinitionKey<Value>.self]
        }
        set {
            state[AnimationFinishingDefinitionKey<Value>.self] = newValue
        }
    }

    var velocityState: VelocityState<Value> {
        get {
            state[VelocityState<Value>.self]
        }
        set {
            state[VelocityState<Value>.self] = newValue
        }
    }

    func shouldFinishEarly(
        data: @autoclosure () -> AnimationSettlingContext<Value>.Data
    ) -> Bool {
        guard let definition = finishingDefinition else {
            return false
        }
        return definition.shouldFinishEarly(
            in: AnimationSettlingContext(
                data: data(),
                environment: environment
            )
        )
    }

    public func withState<T>(_ state: AnimationState<T>) -> AnimationContext<T> where T: VectorArithmetic {
        AnimationContext<T>(
            state: state,
            isLogicallyComplete: isLogicallyComplete,
            environmentBox: environmentBox,
            storageTag: storageTag
        )
    }
}

@available(*, unavailable)
extension AnimationContext: Sendable {
}

func makeAnimationContext<AnimatedValue: Animatable>(
    for type: AnimatedValue.Type,
    state: AnimationState<AnimatedValue.AnimatableData>,
    isLogicallyComplete: Bool = false,
    environment: EnvironmentValues
) -> AnimationContext<AnimatedValue.AnimatableData> {
    makeAnimationContext(
        state: state,
        isLogicallyComplete: isLogicallyComplete,
        environment: environment,
        finishingDefinition: type as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type
    )
}

func makeAnimationContext<Value: VectorArithmetic>(
    state: AnimationState<Value>,
    isLogicallyComplete: Bool = false,
    environment: EnvironmentValues,
    finishingDefinition: (any AnimationFinishingDefinition<Value>.Type)?
) -> AnimationContext<Value> {
    var context = AnimationContext(
        state: state,
        isLogicallyComplete: isLogicallyComplete,
        environment: environment
    )
    context.finishingDefinition = finishingDefinition
    return context
}

extension _RotationEffect: ExtendedAnimatable {
    static func shouldFinishEarly(in context: AnimationSettlingContext<AnimatableData>) -> Bool {
        let delta = context.delta
        let velocity = context.velocity
        let angleThreshold = 1.28
        let angleMagnitudeSquared = delta.first * delta.first + velocity.first * velocity.first
        return angleMagnitudeSquared < angleThreshold * angleThreshold &&
            delta.second.first == 0 &&
            delta.second.second == 0
    }
}

extension EnvironmentValues {
    var animationPixelLength: CGFloat {
        defaultPixelLength ?? (1 / displayScale)
    }
}

@preconcurrency public protocol CustomAnimation: Hashable, Sendable {
    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic

    nonisolated func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic
}

extension CustomAnimation {
    nonisolated public func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        nil
    }

    nonisolated public func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        false
    }
}

protocol InternalCustomAnimation: CustomAnimation {
    var function: Animation.Function { get }
    var animationBox: AnimationBoxBase { get }
}

extension InternalCustomAnimation {
    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        animationBox.animate(value: value, time: time, context: &context)
    }

    func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        animationBox.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        animationBox.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    func modified<Modifier>(
        _ modifier: Modifier
    ) -> any CustomAnimation where Modifier: CustomAnimationModifier {
        InternalCustomAnimationModifiedContent(base: self, modifier: modifier)
    }
}

protocol CustomAnimationModifier: Hashable {
    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation

    func velocity<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation

    func shouldMerge<Value, Base>(
        base: Base,
        previous: Self,
        previousBase: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic, Base: CustomAnimation

    func function(base: Animation.Function) -> Animation.Function
    func box(base: AnimationBoxBase) -> AnimationBoxBase
}

extension CustomAnimationModifier {
    func velocity<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        nil
    }

    func shouldMerge<Value, Base>(
        base: Base,
        previous: Self,
        previousBase: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic, Base: CustomAnimation {
        false
    }

    func animationBox<Base>(for base: Base) -> AnimationBoxBase where Base: CustomAnimation {
        if let base = base as? any InternalCustomAnimation {
            return base.animationBox
        }
        return Animation(base).box
    }
}

struct DefaultAnimation: InternalCustomAnimation {
    var function: Animation.Function {
        FluidSpringAnimation(
            response: 0.5,
            dampingFraction: 1,
            blendDuration: 0
        ).function
    }

    var animationBox: AnimationBoxBase {
        DefaultAnimationBox()
    }
}

struct BezierAnimation: InternalCustomAnimation {
    var duration: TimeInterval
    var curve: UnitCurve.CubicSolver

    var function: Animation.Function {
        let points = curve.controlPointsForAnimation
        return .bezier(duration, points.startControlPoint, points.endControlPoint)
    }

    var animationBox: AnimationBoxBase {
        BezierAnimationBox(curve: curve, duration: duration)
    }
}

struct DelayAnimation: CustomAnimationModifier {
    var delay: TimeInterval

    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        box(base: animationBox(for: base)).animate(
            value: value,
            time: time,
            context: &context
        )
    }

    func function(base: Animation.Function) -> Animation.Function {
        .delay(delay, base)
    }

    func box(base: AnimationBoxBase) -> AnimationBoxBase {
        DelayAnimationBox(base: base, delay: delay)
    }
}

struct SpeedAnimation: CustomAnimationModifier {
    var speed: Double

    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        box(base: animationBox(for: base)).animate(
            value: value,
            time: time,
            context: &context
        )
    }

    func function(base: Animation.Function) -> Animation.Function {
        .speed(speed, base)
    }

    func box(base: AnimationBoxBase) -> AnimationBoxBase {
        SpeedAnimationBox(base: base, speed: speed)
    }
}

struct RepeatAnimation: CustomAnimationModifier {
    var repeatCount: Int?
    var autoreverses: Bool

    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        box(base: animationBox(for: base)).animate(
            value: value,
            time: time,
            context: &context
        )
    }

    func function(base: Animation.Function) -> Animation.Function {
        .repeat(repeatCount.map(Double.init) ?? .infinity, autoreverses, base)
    }

    func box(base: AnimationBoxBase) -> AnimationBoxBase {
        RepeatAnimationBox(base: base, repeatCount: repeatCount, autoreverses: autoreverses)
    }
}

struct LogicalCompletionModifier: CustomAnimationModifier {
    var duration: TimeInterval

    func animate<Value, Base>(
        base: Base,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic, Base: CustomAnimation {
        let wasLogicallyComplete = context.isLogicallyComplete
        let output = base.animate(value: value, time: time, context: &context)
        if !wasLogicallyComplete {
            context.isLogicallyComplete = time >= duration
        }
        return output
    }

    func function(base: Animation.Function) -> Animation.Function {
        base
    }

    func box(base: AnimationBoxBase) -> AnimationBoxBase {
        LogicalCompletionAnimationBox(base: base, duration: duration)
    }
}

struct CustomAnimationModifiedContent<Base, Modifier>: InternalCustomAnimation, @unchecked Sendable
where Base: CustomAnimation, Modifier: CustomAnimationModifier {
    var base: Base
    var modifier: Modifier

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        modifier.animate(base: base, value: value, time: time, context: &context)
    }

    func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        modifier.velocity(base: base, value: value, time: time, context: context)
    }

    func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        guard let previousBase = previous.base as? Self else { return false }
        return modifier.shouldMerge(
            base: base,
            previous: previousBase.modifier,
            previousBase: previousBase.base,
            value: value,
            time: time,
            context: &context
        )
    }

    var function: Animation.Function {
        modifier.function(base: .custom(base))
    }

    var animationBox: AnimationBoxBase {
        if let baseValue = base as? any InternalCustomAnimation {
            return modifier.box(base: baseValue.animationBox)
        }
        return modifier.box(base: Animation(base).box)
    }
}

struct InternalCustomAnimationModifiedContent<Base, Modifier>: InternalCustomAnimation, @unchecked Sendable
where Base: CustomAnimation, Modifier: CustomAnimationModifier {
    var _base: CustomAnimationModifiedContent<Base, Modifier>

    init(base: Base, modifier: Modifier) {
        self._base = CustomAnimationModifiedContent(base: base, modifier: modifier)
    }

    var base: Base {
        _base.base
    }

    var modifier: Modifier {
        _base.modifier
    }

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        modifier.animate(base: base, value: value, time: time, context: &context)
    }

    func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        modifier.velocity(base: base, value: value, time: time, context: context)
    }

    func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        guard let previousBase = previous.base as? Self else { return false }
        return modifier.shouldMerge(
            base: base,
            previous: previousBase.modifier,
            previousBase: previousBase.base,
            value: value,
            time: time,
            context: &context
        )
    }

    var function: Animation.Function {
        let baseFunction: Animation.Function
        if let base = _base.base as? any InternalCustomAnimation {
            baseFunction = base.function
        } else {
            baseFunction = .custom(_base.base)
        }
        return _base.modifier.function(base: baseFunction)
    }

    var animationBox: AnimationBoxBase {
        _base.animationBox
    }
}
