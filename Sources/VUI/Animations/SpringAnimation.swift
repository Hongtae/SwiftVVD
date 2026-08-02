//
//  File: SpringAnimation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct FluidSpringAnimation: InternalCustomAnimation {
    var response: TimeInterval
    var dampingFraction: Double
    var blendDuration: TimeInterval

    var function: Animation.Function {
        let stiffness = fluidSpringStiffness(response: response)
        let damping = 2 * dampingFraction * sqrt(stiffness)
        let duration = Spring(mass: 1, stiffness: stiffness, damping: damping)
            .settlingDuration(target: Double(1), initialVelocity: Double.zero, epsilon: 0.001)
        return .spring(duration, 1, stiffness, damping, 0)
    }

    var animationBox: AnimationBoxBase {
        FluidSpringAnimationBox(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }
}

struct SpringAnimation: InternalCustomAnimation {
    var mass: Double
    var stiffness: Double
    var damping: Double
    var initialVelocity: _Velocity<Double>

    var function: Animation.Function {
        let duration = Spring(mass: mass, stiffness: stiffness, damping: damping)
            .settlingDuration(
                target: Double(1),
                initialVelocity: initialVelocity.valuePerSecond,
                epsilon: 0.001
            )
        return .spring(duration, mass, stiffness, damping, initialVelocity.valuePerSecond)
    }

    var animationBox: AnimationBoxBase {
        SpringAnimationBox(
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity.valuePerSecond
        )
    }
}

@usableFromInline
struct SpringState<AnimatableValue: VectorArithmetic>: AnimationStateKey {
    @usableFromInline
    typealias Value = SpringState<AnimatableValue>

    var time: TimeInterval
    var position: AnimatableValue
    var velocity: AnimatableValue
    var acceleration: AnimatableValue
    var responseBlendStartTime: TimeInterval
    var responseBlendDelta: TimeInterval
    var isInitialized: Bool

    init(
        time: TimeInterval = 0,
        position: AnimatableValue = .zero,
        velocity: AnimatableValue = .zero,
        acceleration: AnimatableValue = .zero,
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

    @usableFromInline
    static var defaultValue: SpringState<AnimatableValue> {
        SpringState()
    }
}

@usableFromInline
func fluidSpringStiffness(response: TimeInterval) -> Double {
    guard response > 0 else { return 45_000 }
    let frequency = 2 * Double.pi / response
    return min(frequency * frequency, 45_000)
}

func fluidSpringFinishingVelocityScale(
    stiffness: Double,
    dampingFraction: Double
) -> Double {
    2 * dampingFraction * sqrt(stiffness) / stiffness
}

func fluidSpringSettlingData<Value: VectorArithmetic>(
    target: Value,
    output: Value,
    state: SpringState<Value>,
    stiffness: Double,
    dampingFraction: Double
) -> AnimationSettlingContext<Value>.Data {
    var velocity = state.velocity
    velocity.scale(by: fluidSpringFinishingVelocityScale(
        stiffness: stiffness,
        dampingFraction: dampingFraction
    ))
    return AnimationSettlingContext<Value>.Data(
        delta: target - output,
        velocity: velocity
    )
}

@usableFromInline
func blendedFluidSpringResponse<Value: VectorArithmetic>(
    response: TimeInterval,
    blendDuration: TimeInterval,
    time: TimeInterval,
    state: SpringState<Value>
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
    state: inout SpringState<Value>
) -> Value {
    let step = 1.0 / 300.0
    let halfStep = 1.0 / 600.0
    let clampedTime = max(time, 0)

    if !state.isInitialized {
        state = SpringState(isInitialized: true)
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
    state: SpringState<Value>
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
    var state = SpringState<Value>()
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

public struct Spring: Hashable, Sendable {
    var angularFrequency: Double
    var decayConstant: Double
    var _mass: Double

    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        let dampingRatio = Self.dampingRatio(bounce: bounce)
        self.init(response: duration, dampingRatio: dampingRatio)
    }

    public init(response: Double, dampingRatio: Double) {
        let naturalFrequency = 2 * Double.pi / response
        let ratio = dampingRatio
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
        if stiffness == 0 {
            self.angularFrequency = 0
            self.decayConstant = 0
        } else {
            var decay = damping / (2 * mass)
            let frequencySquared = stiffness / mass
            var angularSquared = frequencySquared - decay * decay
            if !allowOverDamping,
               frequencySquared > 0,
               angularSquared < 0 {
                decay = sqrt(frequencySquared)
                angularSquared = 0
            }
            if angularSquared < 0 {
                if frequencySquared < 0 {
                    self.angularFrequency = sqrt(-angularSquared)
                } else {
                    self.angularFrequency = -sqrt(-angularSquared)
                }
            } else {
                self.angularFrequency = sqrt(angularSquared)
            }
            self.decayConstant = decay
        }
        self._mass = mass
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
        if angularFrequency < 0 {
            return 1 / ratio - 1
        }
        return 1 - ratio
    }

    public var response: Double {
        2 * Double.pi / naturalFrequency
    }

    public var dampingRatio: Double {
        decayConstant / naturalFrequency
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
            return sqrt(decayConstant * decayConstant - angularFrequency * angularFrequency)
        }
        return sqrt(decayConstant * decayConstant + angularFrequency * angularFrequency)
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

    func _keyframeValue<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> V where V: VectorArithmetic {
        solve(
            target: target,
            initialVelocity: initialVelocity,
            time: time,
            clampsNegativeTime: false
        ).value
    }

    public func velocity<V>(
        target: V,
        initialVelocity: V = .zero,
        time: TimeInterval
    ) -> V where V: VectorArithmetic {
        solve(target: target, initialVelocity: initialVelocity, time: time).velocity
    }

    func _keyframeVelocity<V>(
        target: V,
        initialVelocity: V,
        time: TimeInterval
    ) -> V where V: VectorArithmetic {
        solve(
            target: target,
            initialVelocity: initialVelocity,
            time: time,
            clampsNegativeTime: false
        ).velocity
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
        time: TimeInterval,
        clampsNegativeTime: Bool = true
    ) -> (value: V, velocity: V) where V: VectorArithmetic {
        let t = clampsNegativeTime ? max(time, 0) : time
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
        velocity += target
        return (value, velocity)
    }
}
