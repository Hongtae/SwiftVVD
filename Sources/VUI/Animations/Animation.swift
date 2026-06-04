//
//  File: Animation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
class AnimationBoxBase: CustomAnimation, CustomStringConvertible, @unchecked Sendable {
    // Box subclasses keep the public Animation value small while preserving
    // modifier composition such as delay, speed, repeat, and spring variants.
    var duration: TimeInterval { 0 }
    var presentationDuration: TimeInterval { duration }
    var preservesRetargetedCompletionDeadlines: Bool { false }
    var customAnimationBase: any CustomAnimation { self }

    @usableFromInline
    var description: String {
        String(describing: type(of: self))
    }

    @usableFromInline
    static func == (lhs: AnimationBoxBase, rhs: AnimationBoxBase) -> Bool {
        lhs === rhs
    }

    @usableFromInline
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func value(at progress: Double) -> Double {
        progress
    }

    func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        presentationDuration
    }

    @usableFromInline
    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard duration > 0 else {
            context.isLogicallyComplete = true
            return nil
        }
        if !duration.isFinite {
            var output = value
            output.scale(by: self.value(at: time))
            return output
        }
        let lifetime = max(duration, presentationDuration(for: value))
        if time >= duration {
            context.isLogicallyComplete = true
        }
        if time >= lifetime {
            return nil
        }
        let rawProgress = min(max(time / duration, 0), 1)
        var output = value
        output.scale(by: self.value(at: rawProgress))
        return output
    }

    @usableFromInline
    func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        nil
    }

    @usableFromInline
    func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        false
    }
}

@usableFromInline
final class DefaultAnimationBox: AnimationBoxBase, @unchecked Sendable {
    private let base = FluidSpringAnimationBox(
        response: 0.5,
        dampingFraction: 1.0,
        blendDuration: 0
    )

    override var duration: TimeInterval {
        base.duration
    }

    override var presentationDuration: TimeInterval {
        base.presentationDuration
    }

    override func value(at progress: Double) -> Double {
        base.value(at: progress)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        base.presentationDuration(for: value)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        base.animate(value: value, time: time, context: &context)
    }

    override func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        base.velocity(value: value, time: time, context: context)
    }

    override func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        base.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }
}

@usableFromInline
final class BezierAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let curve: UnitCurve
    let storedDuration: TimeInterval

    init(curve: UnitCurve, duration: TimeInterval) {
        self.curve = curve
        self.storedDuration = duration
    }

    override var duration: TimeInterval {
        storedDuration
    }

    override func value(at progress: Double) -> Double {
        curve.value(at: progress)
    }
}

@usableFromInline
final class DelayAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let delay: TimeInterval

    init(base: AnimationBoxBase, delay: TimeInterval) {
        self.base = base
        self.delay = delay
    }

    override var duration: TimeInterval {
        max(0, base.duration + delay)
    }

    override var presentationDuration: TimeInterval {
        max(0, base.presentationDuration + delay)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        max(0, base.presentationDuration(for: value) + delay)
    }

    override func value(at progress: Double) -> Double {
        guard base.duration > 0 else { return base.value(at: 1) }
        let localTime = progress * duration - delay
        let localProgress = min(max(localTime / base.duration, 0), 1)
        return base.value(at: localProgress)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        let localTime = time - delay
        guard localTime >= 0 else {
            var output = value
            output.scale(by: 0)
            return output
        }

        let output = base.animate(value: value, time: localTime, context: &context)
        if output == nil, time < presentationDuration(for: value) {
            return value
        }
        return output
    }
}

@usableFromInline
final class SpeedAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let speed: Double

    init(base: AnimationBoxBase, speed: Double) {
        self.base = base
        self.speed = speed
    }

    override var duration: TimeInterval {
        guard speed > 0 else { return .infinity }
        return base.duration / speed
    }

    override var presentationDuration: TimeInterval {
        guard speed > 0 else { return .infinity }
        return scaledPresentationDuration(basePresentationDuration: base.presentationDuration)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        guard speed > 0 else { return .infinity }
        return scaledPresentationDuration(
            basePresentationDuration: base.presentationDuration(for: value)
        )
    }

    override func value(at progress: Double) -> Double {
        guard speed > 0 else { return base.value(at: 0) }
        return base.value(at: progress)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard speed > 0 else {
            var output = value
            output.scale(by: base.value(at: 0))
            return output
        }

        let output = base.animate(value: value, time: time * speed, context: &context)
        if output == nil, time < presentationDuration(for: value) {
            return value
        }
        return output
    }

    private func scaledPresentationDuration(basePresentationDuration: TimeInterval) -> TimeInterval {
        basePresentationDuration / speed
    }
}

@usableFromInline
final class RepeatAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let repeatCount: Int?
    let autoreverses: Bool

    init(base: AnimationBoxBase, repeatCount: Int?, autoreverses: Bool) {
        self.base = base
        self.repeatCount = repeatCount
        self.autoreverses = autoreverses
    }

    private var resolvedRepeatCount: Int {
        max(repeatCount ?? 1, 1)
    }

    override var duration: TimeInterval {
        guard let repeatCount else { return .infinity }
        if baseHasResidualPresentation(basePresentationDuration: base.presentationDuration) {
            return base.duration
        }
        return base.duration * TimeInterval(max(repeatCount, 1))
    }

    override var presentationDuration: TimeInterval {
        guard repeatCount != nil else { return .infinity }
        let basePresentationDuration = base.presentationDuration
        guard baseHasResidualPresentation(basePresentationDuration: basePresentationDuration) else {
            return duration
        }
        return basePresentationDuration * TimeInterval(resolvedRepeatCount)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        guard repeatCount != nil else { return .infinity }
        let basePresentationDuration = base.presentationDuration(for: value)
        guard baseHasResidualPresentation(basePresentationDuration: basePresentationDuration) else {
            return duration
        }
        return basePresentationDuration * TimeInterval(resolvedRepeatCount)
    }

    override func value(at progress: Double) -> Double {
        guard base.duration > 0 else { return base.value(at: 1) }
        let cycles: Double
        if let repeatCount {
            cycles = Double(max(repeatCount, 1))
        } else {
            cycles = 1
        }

        let rawCycle: Double
        if repeatCount == nil {
            rawCycle = max(progress, 0).truncatingRemainder(dividingBy: 1)
        } else {
            rawCycle = min(max(progress, 0), 1) * cycles
        }

        if repeatCount != nil, rawCycle >= cycles {
            let endsReversed = autoreverses && resolvedRepeatCount.isMultiple(of: 2)
            return base.value(at: endsReversed ? 0 : 1)
        }

        let cycleIndex = Int(floor(rawCycle))
        var localProgress = rawCycle - Double(cycleIndex)
        if autoreverses && !cycleIndex.isMultiple(of: 2) {
            localProgress = 1 - localProgress
        }
        return base.value(at: min(max(localProgress, 0), 1))
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard repeatCount == nil else {
            let basePresentationDuration = base.presentationDuration(for: value)
            guard baseHasResidualPresentation(basePresentationDuration: basePresentationDuration) else {
                return super.animate(value: value, time: time, context: &context)
            }
            if time >= base.duration {
                context.isLogicallyComplete = true
            }
            return residualRepeatValue(
                value: value,
                time: time,
                basePresentationDuration: basePresentationDuration,
                context: context
            )
        }
        guard base.duration > 0 else {
            context.isLogicallyComplete = true
            return nil
        }
        let rawCycle = max(time / base.duration, 0)
            .truncatingRemainder(dividingBy: 1)
        let cycleIndex = Int(floor(max(time / base.duration, 0)))
        var localProgress = rawCycle
        if autoreverses && !cycleIndex.isMultiple(of: 2) {
            localProgress = 1 - localProgress
        }
        var output = value
        output.scale(by: base.value(at: min(max(localProgress, 0), 1)))
        return output
    }

    private func baseHasResidualPresentation(basePresentationDuration: TimeInterval) -> Bool {
        basePresentationDuration > base.duration
    }

    private func residualRepeatValue<Value>(
        value: Value,
        time: TimeInterval,
        basePresentationDuration: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard base.duration > 0 else { return nil }
        let clampedTime = max(time, 0)
        let totalPresentationDuration = basePresentationDuration * TimeInterval(resolvedRepeatCount)
        guard clampedTime < totalPresentationDuration else {
            return nil
        }

        let rawCycle = clampedTime / basePresentationDuration
        let cycleIndex = min(Int(floor(rawCycle)), resolvedRepeatCount - 1)
        let cycleStart = TimeInterval(cycleIndex) * basePresentationDuration
        let cycleTime = clampedTime - cycleStart
        let isReversedCycle = autoreverses && !cycleIndex.isMultiple(of: 2)
        let localTime = isReversedCycle
            ? max(basePresentationDuration - cycleTime, 0)
            : cycleTime

        var localContext = AnimationContext(
            state: AnimationState<Value>(),
            environment: context.environment
        )
        return base.animate(
            value: value,
            time: localTime,
            context: &localContext
        ) ?? value
    }
}

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

public struct AnimationContext<Value> where Value: VectorArithmetic {
    public var state: AnimationState<Value>
    public var isLogicallyComplete: Bool
    private var resolvedEnvironment: EnvironmentValues

    public var environment: EnvironmentValues {
        resolvedEnvironment
    }

    init(
        state: AnimationState<Value> = AnimationState(),
        isLogicallyComplete: Bool = false,
        environment: EnvironmentValues = EnvironmentValues()
    ) {
        self.state = state
        self.isLogicallyComplete = isLogicallyComplete
        self.resolvedEnvironment = environment
    }

    public func withState<T>(_ state: AnimationState<T>) -> AnimationContext<T> where T: VectorArithmetic {
        AnimationContext<T>(
            state: state,
            isLogicallyComplete: isLogicallyComplete,
            environment: resolvedEnvironment
        )
    }
}

@available(*, unavailable)
extension AnimationContext: Sendable {
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

@usableFromInline
final class CustomAnimationBox<Base: CustomAnimation>: AnimationBoxBase, @unchecked Sendable {
    let base: Base

    init(base: Base) {
        self.base = base
    }

    override var customAnimationBase: any CustomAnimation {
        base
    }

    override var duration: TimeInterval {
        .infinity
    }

    override var preservesRetargetedCompletionDeadlines: Bool {
        true
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        base.animate(value: value, time: time, context: &context)
    }

    override func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        base.velocity(value: value, time: time, context: context)
    }

    override func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        base.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }
}

@usableFromInline
struct FluidSpringAnimationState<Value: VectorArithmetic> {
    var time: TimeInterval
    var position: Value
    var velocity: Value
    var acceleration: Value
    var responseBlendStartTime: TimeInterval
    var responseBlendDelta: TimeInterval
    var isInitialized: Bool

    init(
        time: TimeInterval = 0,
        position: Value = .zero,
        velocity: Value = .zero,
        acceleration: Value = .zero,
        responseBlendStartTime: TimeInterval = 0,
        responseBlendDelta: TimeInterval = 0,
        isInitialized: Bool = false
    ) {
        self.time = time
        self.position = position
        self.velocity = velocity
        self.acceleration = acceleration
        self.responseBlendStartTime = responseBlendStartTime
        self.responseBlendDelta = responseBlendDelta
        self.isInitialized = isInitialized
    }
}

@usableFromInline
enum FluidSpringAnimationStateKey<Value: VectorArithmetic>: AnimationStateKey {
    @usableFromInline
    static var defaultValue: FluidSpringAnimationState<Value> {
        FluidSpringAnimationState()
    }
}

@usableFromInline
func fluidSpringStiffness(response: TimeInterval) -> Double {
    guard response > 0 else { return 45_000 }
    let frequency = 2 * Double.pi / response
    return min(frequency * frequency, 45_000)
}

@usableFromInline
func blendedFluidSpringResponse<Value: VectorArithmetic>(
    response: TimeInterval,
    blendDuration: TimeInterval,
    time: TimeInterval,
    state: FluidSpringAnimationState<Value>
) -> TimeInterval {
    guard blendDuration > 0, state.responseBlendDelta != 0 else {
        return response
    }
    let rawProgress = (time - state.responseBlendStartTime) / blendDuration
    let progress = min(max(rawProgress, 0), 1)
    let smoothstep = progress * progress * (3 - 2 * progress)
    return response + state.responseBlendDelta * (1 - smoothstep)
}

@usableFromInline
func integratedFluidSpringValue<Value: VectorArithmetic>(
    target: Value,
    dampingFraction: Double,
    stiffness: Double,
    time: TimeInterval,
    state: inout FluidSpringAnimationState<Value>
) -> Value {
    let step = 1.0 / 300.0
    let halfStep = 1.0 / 600.0
    let clampedTime = max(time, 0)

    if !state.isInitialized {
        state = FluidSpringAnimationState(isInitialized: true)
    } else if clampedTime - state.time > 1 {
        state.time = max(0, clampedTime - (1.0 / 60.0))
    }

    let dampingCoefficient = -dampingFraction * 2 * sqrt(stiffness)
    while state.time < clampedTime {
        var midpointVelocity = state.acceleration
        midpointVelocity.scale(by: halfStep)
        midpointVelocity += state.velocity

        var positionStep = midpointVelocity
        positionStep.scale(by: step)
        state.position += positionStep

        var springForce = target - state.position
        springForce.scale(by: stiffness)

        var dampingForce = midpointVelocity
        dampingForce.scale(by: dampingCoefficient)

        state.acceleration = springForce + dampingForce

        var velocityStep = state.acceleration
        velocityStep.scale(by: halfStep)
        state.velocity = midpointVelocity + velocityStep

        state.time += step
    }

    return state.position
}

@usableFromInline
func isFluidSpringSettled<Value: VectorArithmetic>(
    target: Value,
    state: FluidSpringAnimationState<Value>
) -> Bool {
    let velocitySquared = state.velocity.magnitudeSquared
    let accelerationSquared = state.acceleration.magnitudeSquared
    guard max(velocitySquared, accelerationSquared) <= 0.0036 else {
        return false
    }

    var tolerance = target
    tolerance.scale(by: 0.01)
    var error = target
    error -= state.position
    return error.magnitudeSquared <= tolerance.magnitudeSquared
}

@usableFromInline
func fluidSpringSettlingDuration<Value: VectorArithmetic>(
    response: TimeInterval,
    dampingFraction: Double,
    target: Value
) -> TimeInterval {
    let duration = max(0, response)
    guard duration > 0 else { return 0 }

    let step = 1.0 / 300.0
    let limit = max(duration * 12, 10)
    let stiffness = fluidSpringStiffness(response: response)
    var state = FluidSpringAnimationState<Value>()
    var time: TimeInterval = 0
    while time <= limit {
        _ = integratedFluidSpringValue(
            target: target,
            dampingFraction: dampingFraction,
            stiffness: stiffness,
            time: time,
            state: &state
        )
        if isFluidSpringSettled(target: target, state: state) {
            return max(duration, time)
        }
        time += step
    }
    return limit
}

@usableFromInline
final class FluidSpringAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let response: TimeInterval
    let dampingFraction: Double
    let blendDuration: TimeInterval
    let presentationDurationEstimate: TimeInterval

    init(response: TimeInterval, dampingFraction: Double, blendDuration: TimeInterval) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
        self.presentationDurationEstimate = fluidSpringSettlingDuration(
            response: response,
            dampingFraction: dampingFraction,
            target: Double(1)
        )
    }

    override var duration: TimeInterval {
        max(0, response)
    }

    override var presentationDuration: TimeInterval {
        max(duration, presentationDurationEstimate)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        max(
            duration,
            fluidSpringSettlingDuration(
                response: response,
                dampingFraction: dampingFraction,
                target: value
            )
        )
    }

    override func value(at progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard clamped < 1, duration > 0 else { return 1 }
        var state = FluidSpringAnimationState<Double>()
        return integratedFluidSpringValue(
            target: 1.0,
            dampingFraction: dampingFraction,
            stiffness: fluidSpringStiffness(response: response),
            time: clamped * duration,
            state: &state
        )
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard duration > 0 else {
            context.isLogicallyComplete = true
            return nil
        }
        if time >= duration {
            context.isLogicallyComplete = true
        }
        var state = context.state[FluidSpringAnimationStateKey<Value>.self]
        let effectiveResponse = blendedFluidSpringResponse(
            response: response,
            blendDuration: blendDuration,
            time: time,
            state: state
        )
        let output = integratedFluidSpringValue(
            target: value,
            dampingFraction: dampingFraction,
            stiffness: fluidSpringStiffness(response: effectiveResponse),
            time: time,
            state: &state
        )
        context.state[FluidSpringAnimationStateKey<Value>.self] = state
        guard !isFluidSpringSettled(target: value, state: state) else {
            return nil
        }
        return output
    }

    override func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard duration > 0 else { return nil }
        let spring = Spring(response: max(response, 0.001), dampingRatio: dampingFraction)
        return spring.velocity(target: value, initialVelocity: .zero, time: time)
    }

    override func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous.box.animate(value: value, time: time, context: &context)

        var state = context.state[FluidSpringAnimationStateKey<Value>.self]
        state.time = max(state.time, time)

        if let previousSpring = previous.box as? FluidSpringAnimationBox,
           previousSpring.response != response {
            state.responseBlendStartTime = time
            state.responseBlendDelta = previousSpring.response - response
        } else {
            state.responseBlendStartTime = time
            state.responseBlendDelta = 0
        }

        context.state[FluidSpringAnimationStateKey<Value>.self] = state
        return true
    }
}

@usableFromInline
final class SpringAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let mass: Double
    let stiffness: Double
    let damping: Double
    let initialVelocity: Double

    init(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        self.initialVelocity = initialVelocity
    }

    override var duration: TimeInterval {
        max(0.001, 2 * .pi / sqrt(max(stiffness, 0.001)))
    }

    override var presentationDuration: TimeInterval {
        max(
            duration,
            spring.settlingDuration(
                target: 1.0,
                initialVelocity: initialVelocity,
                epsilon: 0.007
            )
        )
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        var velocity = value
        velocity.scale(by: initialVelocity)
        return max(
            duration,
            spring.settlingDuration(
                target: value,
                initialVelocity: velocity,
                epsilon: 0.007
            )
        )
    }

    override func value(at progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard clamped < 1, duration > 0 else { return 1 }
        return spring.value(target: 1.0, initialVelocity: initialVelocity, time: clamped * duration)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard duration > 0 else {
            context.isLogicallyComplete = true
            return nil
        }
        if time >= duration {
            context.isLogicallyComplete = true
        }
        guard time < presentationDuration(for: value) else {
            return nil
        }
        var velocity = value
        velocity.scale(by: initialVelocity)
        return spring.value(target: value, initialVelocity: velocity, time: time)
    }

    override func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        var velocity = value
        velocity.scale(by: initialVelocity)
        return spring.velocity(target: value, initialVelocity: velocity, time: time)
    }

    private var spring: Spring {
        Spring(
            mass: mass,
            stiffness: stiffness,
            damping: damping
        )
    }
}

public struct Spring: Hashable, Sendable {
    var angularFrequency: Double
    var decayConstant: Double
    var _mass: Double

    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        let response = max(duration, 0.001)
        let dampingRatio = Self.dampingRatio(bounce: bounce)
        self.init(response: response, dampingRatio: dampingRatio)
    }

    public init(response: Double, dampingRatio: Double) {
        let naturalFrequency = 2 * Double.pi / max(response, 0.001)
        let ratio = max(dampingRatio, 0)
        self.angularFrequency = Self.angularFrequency(
            naturalFrequency: naturalFrequency,
            dampingRatio: ratio
        )
        self.decayConstant = ratio * naturalFrequency
        self._mass = 1.0
    }

    public init(
        mass: Double = 1.0,
        stiffness: Double,
        damping: Double,
        allowOverDamping: Bool = false
    ) {
        let resolvedMass = max(mass, 0.001)
        let resolvedStiffness = max(stiffness, 0.001)
        let naturalFrequency = sqrt(resolvedStiffness / resolvedMass)
        var ratio = damping / (2 * sqrt(resolvedStiffness * resolvedMass))
        if !allowOverDamping {
            ratio = min(ratio, 1)
        }
        ratio = max(ratio, 0)
        self.angularFrequency = Self.angularFrequency(
            naturalFrequency: naturalFrequency,
            dampingRatio: ratio
        )
        self.decayConstant = ratio * naturalFrequency
        self._mass = resolvedMass
    }

    public init(
        settlingDuration: TimeInterval,
        dampingRatio: Double,
        epsilon: Double = 0.001
    ) {
        let ratio = max(dampingRatio, 0.001)
        let duration = max(settlingDuration, 0.001)
        let decay = -log(max(epsilon, .leastNonzeroMagnitude)) / duration
        let naturalFrequency = decay / ratio
        self.angularFrequency = Self.angularFrequency(
            naturalFrequency: naturalFrequency,
            dampingRatio: ratio
        )
        self.decayConstant = decay
        self._mass = 1.0
    }

    public var duration: TimeInterval {
        response
    }

    public var bounce: Double {
        let ratio = dampingRatio
        if ratio <= 1 {
            return 1 - ratio
        }
        return 1 / ratio - 1
    }

    public var response: Double {
        2 * Double.pi / max(naturalFrequency, 0.001)
    }

    public var dampingRatio: Double {
        decayConstant / max(naturalFrequency, 0.001)
    }

    public var mass: Double {
        _mass
    }

    public var stiffness: Double {
        _mass * (decayConstant * decayConstant + angularFrequency * angularFrequency)
    }

    public var damping: Double {
        2 * _mass * decayConstant
    }

    public var settlingDuration: TimeInterval {
        settlingDuration(target: Double(1), initialVelocity: Double.zero, epsilon: 0.001)
    }

    private var naturalFrequency: Double {
        if angularFrequency < 0 {
            return sqrt(max(decayConstant * decayConstant - angularFrequency * angularFrequency, 0.001))
        }
        return sqrt(max(decayConstant * decayConstant + angularFrequency * angularFrequency, 0.001))
    }

    private static func angularFrequency(naturalFrequency: Double, dampingRatio: Double) -> Double {
        if dampingRatio > 1 {
            return -naturalFrequency * sqrt(max(dampingRatio * dampingRatio - 1, 0))
        }
        return naturalFrequency * sqrt(max(1 - dampingRatio * dampingRatio, 0))
    }

    private static func dampingRatio(bounce: Double) -> Double {
        if bounce >= 0 {
            return max(1 - bounce, 0)
        }
        return 1 / max(1 + bounce, 0.001)
    }
}

extension Spring {
    public static var smooth: Spring {
        smooth()
    }

    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: extraBounce)
    }

    public static var snappy: Spring {
        snappy()
    }

    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    public static var bouncy: Spring {
        bouncy()
    }

    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

extension Spring {
    public func value<V>(
        target: V,
        initialVelocity: V = .zero,
        time: TimeInterval
    ) -> V where V: VectorArithmetic {
        solve(target: target, initialVelocity: initialVelocity, time: time).value
    }

    public func velocity<V>(
        target: V,
        initialVelocity: V = .zero,
        time: TimeInterval
    ) -> V where V: VectorArithmetic {
        solve(target: target, initialVelocity: initialVelocity, time: time).velocity
    }

    public func update<V>(
        value: inout V,
        velocity: inout V,
        target: V,
        deltaTime: TimeInterval
    ) where V: VectorArithmetic {
        var delta = target
        delta -= value
        let valueDelta = self.value(
            target: delta,
            initialVelocity: velocity,
            time: deltaTime
        )
        let newVelocity = self.velocity(
            target: delta,
            initialVelocity: velocity,
            time: deltaTime
        )
        var newValue = value
        newValue += valueDelta
        value = newValue
        velocity = newVelocity
    }

    public func force<V>(
        target: V,
        position: V,
        velocity: V
    ) -> V where V: VectorArithmetic {
        var displacement = target
        displacement -= position
        displacement.scale(by: stiffness)
        var dampingForce = velocity
        dampingForce.scale(by: damping)
        displacement -= dampingForce
        return displacement
    }

    public func settlingDuration<V>(
        target: V,
        initialVelocity: V = .zero,
        epsilon: Double
    ) -> TimeInterval where V: VectorArithmetic {
        let threshold = epsilon * epsilon
        var lastOutside: TimeInterval = 0
        let step = max(response / 120, 1.0 / 120.0)
        let limit = max(response * 12, 10)
        var time: TimeInterval = 0
        while time <= limit {
            let value = self.value(target: target, initialVelocity: initialVelocity, time: time)
            let velocity = self.velocity(target: target, initialVelocity: initialVelocity, time: time)
            var error = target
            error -= value
            if error.magnitudeSquared > threshold || velocity.magnitudeSquared > threshold {
                lastOutside = time
            }
            time += step
        }
        return lastOutside + step
    }

    public func value<V>(
        fromValue: V,
        toValue: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> V where V: Animatable {
        var delta = toValue.animatableData
        delta -= fromValue.animatableData
        let animated = value(
            target: delta,
            initialVelocity: initialVelocity.animatableData,
            time: time
        )
        var output = toValue
        var data = fromValue.animatableData
        data += animated
        output.animatableData = data
        return output
    }

    public func velocity<V>(
        fromValue: V,
        toValue: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> V where V: Animatable {
        var delta = toValue.animatableData
        delta -= fromValue.animatableData
        let animated = velocity(
            target: delta,
            initialVelocity: initialVelocity.animatableData,
            time: time
        )
        var output = initialVelocity
        output.animatableData = animated
        return output
    }

    public func force<V>(
        fromValue: V,
        toValue: V,
        position: V,
        velocity: V
    ) -> V where V: Animatable {
        var delta = toValue.animatableData
        delta -= fromValue.animatableData
        var positionDelta = position.animatableData
        positionDelta -= fromValue.animatableData
        let forceData = force(
            target: delta,
            position: positionDelta,
            velocity: velocity.animatableData
        )
        var output = velocity
        output.animatableData = forceData
        return output
    }

    public func settlingDuration<V>(
        fromValue: V,
        toValue: V,
        initialVelocity: V,
        epsilon: Double
    ) -> TimeInterval where V: Animatable {
        var delta = toValue.animatableData
        delta -= fromValue.animatableData
        return settlingDuration(
            target: delta,
            initialVelocity: initialVelocity.animatableData,
            epsilon: epsilon
        )
    }

    private func solve<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> (value: V, velocity: V) where V: VectorArithmetic {
        let t = max(time, 0)
        if angularFrequency < 0 {
            return solveOverdamped(target: target, initialVelocity: initialVelocity, time: t)
        }
        if abs(angularFrequency) < 0.000001 {
            return solveCritical(target: target, initialVelocity: initialVelocity, time: t)
        }
        return solveUnderdamped(target: target, initialVelocity: initialVelocity, time: t)
    }

    private func solveUnderdamped<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> (value: V, velocity: V) where V: VectorArithmetic {
        let decay = exp(-decayConstant * time)
        let cosTerm = cos(angularFrequency * time)
        let sinTerm = sin(angularFrequency * time)
        var a = target
        a.scale(by: -1)
        var b = initialVelocity
        var decayA = a
        decayA.scale(by: decayConstant)
        b += decayA
        b.scale(by: 1 / angularFrequency)

        var y = a
        y.scale(by: cosTerm)
        var sinB = b
        sinB.scale(by: sinTerm)
        y += sinB
        y.scale(by: decay)

        var value = target
        value += y

        var velocity = y
        velocity.scale(by: -decayConstant)
        var oscillation = a
        oscillation.scale(by: -angularFrequency * sinTerm)
        var cosB = b
        cosB.scale(by: angularFrequency * cosTerm)
        oscillation += cosB
        oscillation.scale(by: decay)
        velocity += oscillation

        return (value, velocity)
    }

    private func solveCritical<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> (value: V, velocity: V) where V: VectorArithmetic {
        let decay = exp(-decayConstant * time)
        var a = target
        a.scale(by: -1)
        var b = initialVelocity
        var decayA = a
        decayA.scale(by: decayConstant)
        b += decayA

        var y = b
        y.scale(by: time)
        y += a
        y.scale(by: decay)

        var value = target
        value += y

        var velocity = b
        var inner = b
        inner.scale(by: time)
        inner += a
        inner.scale(by: decayConstant)
        velocity -= inner
        velocity.scale(by: decay)
        return (value, velocity)
    }

    private func solveOverdamped<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> (value: V, velocity: V) where V: VectorArithmetic {
        let frequency = abs(angularFrequency)
        let root1 = -decayConstant + frequency
        let root2 = -decayConstant - frequency
        var y0 = target
        y0.scale(by: -1)
        var c1 = initialVelocity
        var root2Y0 = y0
        root2Y0.scale(by: root2)
        c1 -= root2Y0
        c1.scale(by: 1 / (root1 - root2))
        var c2 = y0
        c2 -= c1

        let e1 = exp(root1 * time)
        let e2 = exp(root2 * time)
        var y = c1
        y.scale(by: e1)
        var y2 = c2
        y2.scale(by: e2)
        y += y2

        var value = target
        value += y

        var velocity = c1
        velocity.scale(by: root1 * e1)
        var velocity2 = c2
        velocity2.scale(by: root2 * e2)
        velocity += velocity2
        return (value, velocity)
    }
}

public struct Animation: Equatable, Sendable {
    var box: AnimationBoxBase

    @usableFromInline
    init(box: AnimationBoxBase) {
        self.box = box
    }

    public init<A>(_ base: A) where A: CustomAnimation {
        self.init(box: CustomAnimationBox(base: base))
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.box === rhs.box
    }
}

extension Animation: Hashable {
    public func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        box.animate(value: value, time: time, context: &context)
    }

    public func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        box.velocity(value: value, time: time, context: context)
    }

    public func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        box.shouldMerge(
            previous: previous,
            value: value,
            time: time,
            context: &context
        )
    }

    public var base: any CustomAnimation {
        box.customAnimationBase
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(box))
    }
}

public struct AnimationCompletionCriteria: Hashable, Sendable {
    private let storage: UInt8

    private init(storage: UInt8) {
        self.storage = storage
    }

    public static let logicallyComplete = AnimationCompletionCriteria(storage: 0)
    public static let removed = AnimationCompletionCriteria(storage: 1)
}

final class AnimationCompletionObserver: @unchecked Sendable {
    private struct Entry {
        var criteria: AnimationCompletionCriteria
        var completion: () -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var activeAnimations: [AnimationCompletionCriteria: Int] = [:]
    private var bodyFinished = false
    private var registeredAnimation = false
    private var completedCriteria = Set<AnimationCompletionCriteria>()

    // Completion observers are shared by every animatable node touched by one
    // transaction. Criteria have separate token counts so logical completion can
    // finish before removal/presentation completion.
    init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completedCriteria.contains(criteria) else { return }
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func criteriaForNewAnimation() -> [AnimationCompletionCriteria] {
        lock.lock()
        defer { lock.unlock() }
        return orderedCriteria()
            .filter { !completedCriteria.contains($0) }
    }

    func animationDidStart(criteria: AnimationCompletionCriteria) -> AnimationCompletionToken? {
        lock.lock()
        defer { lock.unlock() }
        guard entries.contains(where: { $0.criteria == criteria }),
              !completedCriteria.contains(criteria) else {
            return nil
        }
        registeredAnimation = true
        activeAnimations[criteria, default: 0] += 1
        return AnimationCompletionToken(observer: self, criteria: criteria)
    }

    func bodyDidFinish() -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        bodyFinished = true
        return completionsIfReady(allowNoRegisteredAnimation: false)
    }

    fileprivate func animationDidFinish(criteria: AnimationCompletionCriteria) -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        guard activeAnimations[criteria, default: 0] > 0 else { return [] }
        activeAnimations[criteria, default: 0] -= 1
        return completionsIfReady(allowNoRegisteredAnimation: false)
    }

    func noRegisteredAnimationFallbackDidFire() -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        return completionsIfReady(allowNoRegisteredAnimation: true)
    }

    private func completionsIfReady(allowNoRegisteredAnimation: Bool) -> [() -> Void] {
        guard bodyFinished,
              (registeredAnimation || allowNoRegisteredAnimation),
              !orderedCriteria().isEmpty else {
            return []
        }
        var completions: [() -> Void] = []
        for criteria in orderedCriteria() where !completedCriteria.contains(criteria) {
            guard activeAnimations[criteria, default: 0] == 0 else {
                continue
            }
            completedCriteria.insert(criteria)
            completions.append(
                contentsOf: entries
                    .filter { $0.criteria == criteria }
                    .map(\.completion)
            )
        }
        return completions
    }

    private func orderedCriteria() -> [AnimationCompletionCriteria] {
        var criteria: [AnimationCompletionCriteria] = []
        if entries.contains(where: { $0.criteria == .removed }) {
            criteria.append(.removed)
        }
        for entry in entries where entry.criteria != .removed && !criteria.contains(entry.criteria) {
            criteria.append(entry.criteria)
        }
        return criteria
    }
}

final class AnimationCompletionToken: @unchecked Sendable {
    private let observer: AnimationCompletionObserver
    let criteria: AnimationCompletionCriteria
    private var finished = false

    init(observer: AnimationCompletionObserver, criteria: AnimationCompletionCriteria) {
        self.observer = observer
        self.criteria = criteria
    }

    func finish() -> [() -> Void] {
        guard !finished else { return [] }
        finished = true
        return observer.animationDidFinish(criteria: criteria)
    }
}

func enqueueAnimationCompletionActions(_ actions: [() -> Void]) {
    guard !actions.isEmpty else { return }
    let wrapped = actions.map { action in
        {
            AttributeGraph.withoutTracking(action)
        }
    }
    // Completion actions may trigger arbitrary view mutations. Queue them until
    // the graph leaves the current evaluation/draw pass when possible.
    if let graph = AttributeGraph.current {
        graph.actionOutbox.append(contentsOf: wrapped)
    } else {
        wrapped.forEach { $0() }
    }
}

private struct AnimationCompletionObserverBox: @unchecked Sendable {
    var observer: AnimationCompletionObserver
}

func enqueueNoRegisteredAnimationFallback(_ observer: AnimationCompletionObserver?) {
    guard let observer else { return }
    let box = AnimationCompletionObserverBox(observer: observer)
    DispatchQueue.main.async {
        enqueueAnimationCompletionActions(
            box.observer.noRegisteredAnimationFallbackDidFire()
        )
    }
}

func finalizeAnimationCompletionObserver(_ observer: AnimationCompletionObserver?) {
    enqueueAnimationCompletionActions(observer?.bodyDidFinish() ?? [])
    enqueueNoRegisteredAnimationFallback(observer)
}

extension Animation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "Animation"
    }
    public var debugDescription: String {
        "Animation"
    }
    public var customMirror: Mirror {
        Mirror(self, children: ["base": box])
    }
}

extension Animation {
    public static let `default`: Animation = Animation(box: DefaultAnimationBox())
}

extension Animation {
    public static func easeInOut(duration: TimeInterval) -> Animation {
        timingCurve(0.42, 0.0, 0.58, 1.0, duration: duration)
    }
    public static var easeInOut: Animation {
        timingCurve(0.42, 0.0, 0.58, 1.0)
    }
    public static func easeIn(duration: TimeInterval) -> Animation {
        timingCurve(0.42, 0.0, 1.0, 1.0, duration: duration)
    }
    public static var easeIn: Animation {
        timingCurve(0.42, 0.0, 1.0, 1.0)
    }
    public static func easeOut(duration: TimeInterval) -> Animation {
        timingCurve(0.0, 0.0, 0.58, 1.0, duration: duration)
    }
    public static var easeOut: Animation {
        timingCurve(0.0, 0.0, 0.58, 1.0)
    }
    public static func linear(duration: TimeInterval) -> Animation {
        timingCurve(0.0, 0.0, 1.0, 1.0, duration: duration)
    }
    public static var linear: Animation {
        timingCurve(0.0, 0.0, 1.0, 1.0)
    }
    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double, duration: TimeInterval = 0.35) -> Animation {
        let curve = UnitCurve(c1x: p1x, c1y: p1y, c2x: p2x, c2y: p2y)
        return Animation(box: BezierAnimationBox(curve: curve, duration: max(0, duration)))
    }

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        timingCurve(curve.c1x, curve.c1y, curve.c2x, curve.c2y, duration: duration)
    }

    public func delay(_ delay: TimeInterval) -> Animation {
        Animation(box: DelayAnimationBox(base: box, delay: delay))
    }

    public func speed(_ speed: Double) -> Animation {
        Animation(box: SpeedAnimationBox(base: box, speed: speed))
    }

    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        Animation(box: RepeatAnimationBox(base: box, repeatCount: repeatCount, autoreverses: autoreverses))
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation(box: RepeatAnimationBox(base: box, repeatCount: nil, autoreverses: autoreverses))
    }
}

extension Animation {
    public static func spring(duration: TimeInterval = 0.5,
                              bounce: Double = 0.0,
                              blendDuration: Double = 0) -> Animation {
        spring(
            response: duration,
            dampingFraction: springDampingFraction(bounce: bounce),
            blendDuration: blendDuration
        )
    }

    public static func spring(response: Double = 0.5,
                              dampingFraction: Double = 0.825,
                              blendDuration: TimeInterval = 0) -> Animation {
        Animation(
            box: FluidSpringAnimationBox(
                response: response,
                dampingFraction: dampingFraction,
                blendDuration: blendDuration
            )
        )
    }

    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0.0) -> Animation {
        self.spring(
            response: spring.response,
            dampingFraction: spring.dampingRatio,
            blendDuration: blendDuration
        )
    }

    public static var spring: Animation {
        spring(duration: 0.5, bounce: 0.0, blendDuration: 0)
    }

    public static func interactiveSpring(response: Double = 0.15,
                                         dampingFraction: Double = 0.86,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        Animation(
            box: FluidSpringAnimationBox(
                response: response,
                dampingFraction: dampingFraction,
                blendDuration: blendDuration
            )
        )
    }

    public static var interactiveSpring: Animation {
        interactiveSpring(duration: 0.15, extraBounce: 0.0, blendDuration: 0.25)
    }

    public static func interactiveSpring(duration: TimeInterval = 0.15,
                                         extraBounce: Double = 0.0,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        spring(
            duration: duration,
            bounce: 0.15 + extraBounce,
            blendDuration: blendDuration
        )
    }

    public static var smooth: Animation {
        smooth()
    }

    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }

    public static var snappy: Animation {
        snappy()
    }

    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    public static var bouncy: Animation {
        bouncy()
    }

    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }

    public static func interpolatingSpring(mass: Double = 1.0,
                                           stiffness: Double,
                                           damping: Double,
                                           initialVelocity: Double = 0.0) -> Animation {
        Animation(
            box: SpringAnimationBox(
                mass: mass,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: initialVelocity
            )
        )
    }

    public static func interpolatingSpring(duration: TimeInterval = 0.5,
                                           bounce: Double = 0.0,
                                           initialVelocity: Double = 0.0) -> Animation {
        let stiffness = pow(2 * .pi / max(duration, 0.001), 2)
        let damping = 2 * sqrt(stiffness) * springDampingFraction(bounce: bounce)
        return interpolatingSpring(
            mass: 1.0,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    public static var interpolatingSpring: Animation {
        interpolatingSpring()
    }

    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation {
        interpolatingSpring(
            mass: 1.0,
            stiffness: spring.stiffness / max(spring.mass, 0.001),
            damping: spring.damping / max(spring.mass, 0.001),
            initialVelocity: initialVelocity
        )
    }

    private static func springDampingFraction(bounce: Double) -> Double {
        min(max(1 - bounce, 0.0), 1.0)
    }
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withTransaction(Transaction(animation: animation), body)
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping () -> Void
) rethrows -> Result {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: completionCriteria, completion)
    return try withTransaction(transaction, body)
}

private struct AnimationTransactionKey: TransactionKey {
    typealias Value = Animation?
    static var defaultValue: Animation? { nil }
}

private struct DisablesAnimationsTransactionKey: TransactionKey {
    typealias Value = Bool
    static var defaultValue: Bool { false }
}

private struct AnimationCompletionObserverTransactionKey: TransactionKey {
    typealias Value = AnimationCompletionObserver?
    static var defaultValue: AnimationCompletionObserver? { nil }

    static func _valuesEqual(_ lhs: AnimationCompletionObserver?, _ rhs: AnimationCompletionObserver?) -> Bool {
        lhs === rhs
    }
}

extension Transaction {
    public init(animation: Animation?) {
        plist = PropertyList()
        self.animation = animation
    }

    public var animation: Animation? {
        get { self[AnimationTransactionKey.self] }
        set { self[AnimationTransactionKey.self] = newValue }
    }

    var hasExplicitAnimationValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<AnimationTransactionKey>.self) != nil
    }

    public var disablesAnimations: Bool {
        get { self[DisablesAnimationsTransactionKey.self] }
        set { self[DisablesAnimationsTransactionKey.self] = newValue }
    }

    var hasExplicitDisablesAnimationsValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<DisablesAnimationsTransactionKey>.self) != nil
    }

    var animationCompletionObserver: AnimationCompletionObserver? {
        get { self[AnimationCompletionObserverTransactionKey.self] }
        set { self[AnimationCompletionObserverTransactionKey.self] = newValue }
    }

    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping () -> Void
    ) {
        if let observer = animationCompletionObserver {
            observer.add(criteria: criteria, completion: completion)
        } else {
            animationCompletionObserver = AnimationCompletionObserver(
                criteria: criteria,
                completion: completion
            )
        }
    }
}


public struct UnitCurve: Sendable, Hashable {
    let c1x, c1y, c2x, c2y: Double

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(c1x: Double(startControlPoint.x),
                  c1y: Double(startControlPoint.y),
                  c2x: Double(endControlPoint.x),
                  c2y: Double(endControlPoint.y))
    }

    public func value(at progress: Double) -> Double {
        let timingFunction = TimingFunction(controlPoints: c1x, c1y, c2x, c2y)
        return timingFunction.solve(x: progress)
    }

    public func velocity(at progress: Double) -> Double {
        let timingFunction = TimingFunction(controlPoints: c1x, c1y, c2x, c2y)
        return timingFunction.derivative(x: progress)
    }

    public var inverse: UnitCurve {
        // Swap x and y coordinates to get inverse function
        UnitCurve(c1x: c1y, c1y: c1x, c2x: c2y, c2y: c2x)
    }
}

extension UnitCurve {
    /// Linear timing curve (no easing)
    public static let linear = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )

    /// Ease-in timing curve (slow start)
    public static let easeIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )

    /// Ease-out timing curve (slow end)
    public static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )

    /// Ease-in-out timing curve (slow start and end)
    public static let easeInOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )
}

struct TimingFunction {
    private let ax, bx, cx, ay, by, cy: Double

    /// Initializer for custom control points (P1 and P2).
    ///
    /// Standard Presets (c1x, c1y, c2x, c2y):
    /// - Linear:      (0.00, 0.00, 1.00, 1.00)
    /// - Ease-In:     (0.42, 0.00, 1.00, 1.00)
    /// - Ease-Out:    (0.00, 0.00, 0.58, 1.00)
    /// - Ease-In-Out: (0.42, 0.00, 0.58, 1.00)
    ///
    /// Material Design / Modern UI:
    /// - FastOutSlowIn: (0.40, 0.00, 0.20, 1.00) // Standard Easing
    init(controlPoints c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double) {
        cx = 3.0 * c1x
        bx = 3.0 * (c2x - c1x) - cx
        ax = 1.0 - cx - bx
        cy = 3.0 * c1y
        by = 3.0 * (c2y - c1y) - cy
        ay = 1.0 - cy - by
    }

    /// Transforms time ratio (0-1) to eased progress weight (0-1).
    /// - Parameters:
    ///   - x: The current time ratio (0.0 to 1.0).
    ///   - epsilon: The required precision. Defaults to 1e-6 for UI tasks.
    func solve(x: Double, epsilon: Double = 1e-6) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return sampleY(solveCurveX(x, epsilon: epsilon))
    }

    /// Computes the derivative (velocity) at a given time ratio.
    /// - Parameters:
    ///   - x: The current time ratio (0.0 to 1.0).
    ///   - epsilon: The required precision. Defaults to 1e-6 for UI tasks.
    /// - Returns: The rate of change (dy/dx) at the given time.
    func derivative(x: Double, epsilon: Double = 1e-6) -> Double {
        if x <= 0 || x >= 1 { return 0 }

        let t = solveCurveX(x, epsilon: epsilon)
        let dx = sampleDerivativeX(t)
        let dy = sampleDerivativeY(t)

        return dx != 0 ? dy / dx : 0
    }

    private func sampleX(_ t: Double) -> Double {
        return ((ax * t + bx) * t + cx) * t
    }

    private func sampleY(_ t: Double) -> Double {
        return ((ay * t + by) * t + cy) * t
    }

    private func sampleDerivativeX(_ t: Double) -> Double {
        return (3.0 * ax * t + 2.0 * bx) * t + cx
    }

    private func sampleDerivativeY(_ t: Double) -> Double {
        return (3.0 * ay * t + 2.0 * by) * t + cy
    }

    private func solveCurveX(_ x: Double, epsilon: Double) -> Double {
        var t = x
        // 1. Newton's Method for fast convergence
        for _ in 0..<8 {
            let x2 = sampleX(t) - x
            if abs(x2) < epsilon { return t }
            let d2 = sampleDerivativeX(t)
            if abs(d2) < 1e-6 { break }
            t -= x2 / d2
        }

        // 2. Bisection Fallback for guaranteed reliability
        var low: Double = 0, high: Double = 1
        t = x
        while low < high {
            let x2 = sampleX(t)
            if abs(x2 - x) < epsilon { return t }
            if x > x2 { low = t } else { high = t }
            t = (high - low) * 0.5 + low
        }
        return t
    }
}
