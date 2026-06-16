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
    var customAnimationBase: any CustomAnimation { makeBaseValue() }
    var function: Animation.Function {
        if let base = customAnimationBase as? any InternalCustomAnimation {
            return base.function
        }
        return .custom(self)
    }
    var isImmediatelyComplete: Bool { duration <= 0 }

    func makeBaseValue() -> any CustomAnimation {
        self
    }

    func makeDelayedBase(delay: TimeInterval) -> any CustomAnimation {
        guard let base = customAnimationBase as? any InternalCustomAnimation else {
            return self
        }
        return base.modified(DelayAnimation(delay: delay))
    }

    func makeSpeedBase(speed: Double) -> any CustomAnimation {
        guard let base = customAnimationBase as? any InternalCustomAnimation else {
            return self
        }
        return base.modified(SpeedAnimation(speed: speed))
    }

    func makeRepeatBase(repeatCount: Int?, autoreverses: Bool) -> any CustomAnimation {
        guard let base = customAnimationBase as? any InternalCustomAnimation else {
            return self
        }
        return base.modified(RepeatAnimation(repeatCount: repeatCount, autoreverses: autoreverses))
    }

    func makeLogicalCompletionBase(duration: TimeInterval) -> any CustomAnimation {
        guard let base = customAnimationBase as? any InternalCustomAnimation else {
            return self
        }
        return base.modified(LogicalCompletionModifier(duration: duration))
    }

    @usableFromInline
    var description: String {
        String(describing: type(of: self))
    }

    @usableFromInline
    var debugDescription: String {
        description
    }

    @usableFromInline
    static func == (lhs: AnimationBoxBase, rhs: AnimationBoxBase) -> Bool {
        lhs.isEqual(to: rhs)
    }

    @usableFromInline
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: self)))
    }

    @usableFromInline
    func isEqual(to other: AnimationBoxBase) -> Bool {
        self === other
    }

    func value(at progress: Double) -> Double {
        progress
    }

    func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        presentationDuration
    }

    func noRegisteredCompletionDelay() -> TimeInterval? {
        if isImmediatelyComplete {
            return 0
        }
        let delay = max(duration, presentationDuration)
        return delay.isFinite ? delay : nil
    }

    func noRegisteredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        noRegisteredCompletionDelay()
    }

    func registeredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        nil
    }

    var defaultDisplayFrameInterval: TimeInterval {
        1.0 / 60.0
    }

    @usableFromInline
    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard !time.isNaN else { return nil }
        guard !isImmediatelyComplete else {
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

    override var description: String {
        "DefaultAnimation()"
    }

    override func makeBaseValue() -> any CustomAnimation {
        DefaultAnimation()
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        other is DefaultAnimationBox
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
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
    let curve: UnitCurve.CubicSolver
    let storedDuration: TimeInterval

    init(curve: UnitCurve.CubicSolver, duration: TimeInterval) {
        self.curve = curve
        self.storedDuration = duration
    }

    override var duration: TimeInterval {
        storedDuration
    }

    override var description: String {
        "BezierAnimation(duration: \(storedDuration), curve: \(curve))"
    }

    override func makeBaseValue() -> any CustomAnimation {
        BezierAnimation(duration: storedDuration, curve: curve)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? BezierAnimationBox else { return false }
        return curve == other.curve && storedDuration == other.storedDuration
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(curve)
        hasher.combine(storedDuration)
    }

    override func value(at progress: Double) -> Double {
        curve.solve(x: progress)
    }
}

@usableFromInline
final class UnitCurveAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let curve: UnitCurve
    let storedDuration: TimeInterval

    init(curve: UnitCurve, duration: TimeInterval) {
        self.curve = curve
        self.storedDuration = duration
    }

    override var duration: TimeInterval {
        storedDuration
    }

    override var description: String {
        "UnitCurveAnimation(duration: \(storedDuration), curve: \(curve))"
    }

    override func makeBaseValue() -> any CustomAnimation {
        UnitCurveAnimation(duration: storedDuration, curve: curve)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? UnitCurveAnimationBox else { return false }
        return curve == other.curve && storedDuration == other.storedDuration
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(curve)
        hasher.combine(storedDuration)
    }

    override func value(at progress: Double) -> Double {
        curve.value(at: progress)
    }

    override func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard !isImmediatelyComplete else {
            return nil
        }
        let progress = min(max(time / storedDuration, 0), 1)
        var output = value
        output.scale(by: curve.velocity(at: progress) / storedDuration)
        return output
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

    override var preservesRetargetedCompletionDeadlines: Bool {
        base.preservesRetargetedCompletionDeadlines
    }

    override var description: String {
        "DelayAnimation(base: \(base), delay: \(delay))"
    }

    override var customAnimationBase: any CustomAnimation {
        base.makeDelayedBase(delay: delay)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? DelayAnimationBox else { return false }
        return base == other.base && delay == other.delay
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(base)
        hasher.combine(delay)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        max(0, base.presentationDuration(for: value) + delay)
    }

    override func noRegisteredCompletionDelay() -> TimeInterval? {
        guard let baseDelay = base.noRegisteredCompletionDelay() else { return nil }
        return max(0, baseDelay + delay)
    }

    override func noRegisteredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard let baseDelay = base.noRegisteredCompletionDelay(for: criteria) else { return nil }
        var fallbackDelay = max(0, baseDelay + delay)
        if criteria == .removed,
           base is SpringAnimationBox,
           base.presentationDuration > base.duration {
            fallbackDelay += defaultDisplayFrameInterval
        }
        return fallbackDelay
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
        let output = base.animate(value: value, time: max(localTime, 0), context: &context)
        if output == nil, base.preservesRetargetedCompletionDeadlines {
            return nil
        }
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

    override var preservesRetargetedCompletionDeadlines: Bool {
        base.preservesRetargetedCompletionDeadlines
    }

    override var description: String {
        "SpeedAnimation(base: \(base), speed: \(speed))"
    }

    override var customAnimationBase: any CustomAnimation {
        base.makeSpeedBase(speed: speed)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? SpeedAnimationBox else { return false }
        return base == other.base && speed == other.speed
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(base)
        hasher.combine(speed)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        guard speed > 0 else { return .infinity }
        return scaledPresentationDuration(
            basePresentationDuration: base.presentationDuration(for: value)
        )
    }

    override func noRegisteredCompletionDelay() -> TimeInterval? {
        guard speed > 0, let baseDelay = base.noRegisteredCompletionDelay() else {
            return nil
        }
        return baseDelay / speed
    }

    override func noRegisteredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard speed > 0, let baseDelay = base.noRegisteredCompletionDelay() else {
            return nil
        }
        return baseDelay / speed
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
        let output = base.animate(value: value, time: time * speed, context: &context)
        if output == nil, base.preservesRetargetedCompletionDeadlines {
            return nil
        }
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

    override var preservesRetargetedCompletionDeadlines: Bool {
        base.preservesRetargetedCompletionDeadlines
    }

    override var description: String {
        "RepeatAnimation(base: \(base), repeatCount: \(String(describing: repeatCount)), " +
            "autoreverses: \(autoreverses))"
    }

    override var customAnimationBase: any CustomAnimation {
        base.makeRepeatBase(repeatCount: repeatCount, autoreverses: autoreverses)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? RepeatAnimationBox else { return false }
        return base == other.base &&
            repeatCount == other.repeatCount &&
            autoreverses == other.autoreverses
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(base)
        hasher.combine(repeatCount)
        hasher.combine(autoreverses)
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

    override func noRegisteredCompletionDelay() -> TimeInterval? {
        guard repeatCount != nil, let baseDelay = base.noRegisteredCompletionDelay() else {
            return nil
        }
        return baseDelay * TimeInterval(resolvedRepeatCount)
    }

    override func noRegisteredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard repeatCount != nil, let baseDelay = base.noRegisteredCompletionDelay(for: criteria) else {
            return nil
        }
        let delay = baseDelay * TimeInterval(resolvedRepeatCount)
        if criteria == .logicallyComplete,
           base is SpringAnimationBox,
           baseHasResidualPresentation(basePresentationDuration: base.presentationDuration) {
            return max(0, delay - defaultDisplayFrameInterval)
        }
        return delay
    }

    override func registeredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard criteria == .logicallyComplete,
              repeatCount == nil,
              base is DefaultAnimationBox ||
              base is FluidSpringAnimationBox ||
              base is SpringAnimationBox else {
            return nil
        }
        return base.isImmediatelyComplete ? 0 : base.duration
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
        guard base.duration.isFinite else {
            return animateNonFiniteBase(value: value, time: time, context: &context)
        }
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

    private func animateNonFiniteBase<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        var repeatState = context.state[RepeatState<Value>.self]
        let localTime = time - repeatState.startTime
        let isReversedCycle = autoreverses && !repeatState.iteration.isMultiple(of: 2)

        guard let output = base.animate(value: value, time: localTime, context: &context) else {
            repeatState.iteration += 1
            repeatState.startTime = time
            context.state = AnimationState<Value>()
            context.state[RepeatState<Value>.self] = repeatState
            if let repeatCount, repeatState.iteration >= repeatCount {
                return nil
            }
            return value
        }

        if isReversedCycle {
            var reversed = value
            reversed -= output
            return reversed
        }
        return output
    }
}

@usableFromInline
final class LogicalCompletionAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let logicalDuration: TimeInterval

    init(base: AnimationBoxBase, duration: TimeInterval) {
        self.base = base
        self.logicalDuration = duration
    }

    override var duration: TimeInterval {
        base.duration
    }

    override var presentationDuration: TimeInterval {
        base.presentationDuration
    }

    override var preservesRetargetedCompletionDeadlines: Bool {
        base.preservesRetargetedCompletionDeadlines
    }

    override var description: String {
        String(describing: customAnimationBase)
    }

    override var debugDescription: String {
        String(reflecting: customAnimationBase)
    }

    override var customAnimationBase: any CustomAnimation {
        base.makeLogicalCompletionBase(duration: logicalDuration)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? LogicalCompletionAnimationBox else { return false }
        return base == other.base && logicalDuration == other.logicalDuration
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(base)
        hasher.combine(logicalDuration)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        base.presentationDuration(for: value)
    }

    override func noRegisteredCompletionDelay() -> TimeInterval? {
        base.noRegisteredCompletionDelay()
    }

    override func noRegisteredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        if criteria == .logicallyComplete {
            return max(0, logicalDuration)
        }
        return base.noRegisteredCompletionDelay(for: criteria)
    }

    override func registeredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        if criteria == .logicallyComplete {
            return max(0, logicalDuration)
        }
        return base.registeredCompletionDelay(for: criteria)
    }

    override func value(at progress: Double) -> Double {
        base.value(at: progress)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        let wasLogicallyComplete = context.isLogicallyComplete
        let output = base.animate(value: value, time: time, context: &context)
        if !wasLogicallyComplete {
            context.isLogicallyComplete = time >= logicalDuration
        }
        return output
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

    var iteration: Int = 0
    var startTime: TimeInterval = 0

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
        if (projectedVelocity?.magnitudeSquared ?? 0) > 0 || activeUntil > time {
            return value
        }

        context.isLogicallyComplete = true
        return nil
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
            context.isLogicallyComplete = true
            return nil
        }

        var output = Value.zero
        var hasActiveOutput = false
        var lastChildIsLogicallyComplete = false
        var nextEntries = combinedState.entries

        for index in entries.indices {
            guard var childState = nextEntries[index].state else {
                if index == entries.indices.last {
                    combinedState.entries = nextEntries
                    context.state.combinedState = combinedState
                    context.isLogicallyComplete = true
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
                output = nextEntries[index].value
                if index == entries.indices.last {
                    combinedState.entries = nextEntries
                    context.state.combinedState = combinedState
                    context.isLogicallyComplete = true
                    return nil
                }
                continue
            }

            output += childOutput
            hasActiveOutput = true
            childState = childContext.state
            nextEntries[index].state = childState
            if index == entries.indices.last {
                lastChildIsLogicallyComplete = childContext.isLogicallyComplete
            }
        }

        combinedState.entries = nextEntries
        context.state.combinedState = combinedState
        context.isLogicallyComplete = lastChildIsLogicallyComplete
        return hasActiveOutput ? output : nil
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
    var combinedState = state.combinedState
    var replacementValue = value
    replacementValue += newValue

    if animation.box is CustomAnimationBox<DefaultCombiningAnimation> {
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: replacementValue,
                state: AnimationState()
            )
        )
    } else {
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: value,
                state: state
            )
        )
        combinedState.entries.append(
            CombinedAnimationState<Value>.Entry(
                value: replacementValue,
                state: AnimationState()
            )
        )
    }

    state.combinedState = combinedState
    animation = Animation(
        DefaultCombiningAnimation(
            first: animation,
            firstElapsed: elapsed,
            second: newAnimation
        )
    )
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
            environment: resolvedEnvironment
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

extension ViewFrame: ExtendedAnimatable {
    typealias AnimatableData = AnimatablePair<CGPoint.AnimatableData, ViewSize.AnimatableData>

    var animatableData: AnimatableData {
        get { AnimatableData(origin.animatableData, size.animatableData) }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second
        }
    }

    static func shouldFinishEarly(in context: AnimationSettlingContext<AnimatableData>) -> Bool {
        let pixelLength = context.environment.animationPixelLength
        let doublePixelLength = pixelLength * 2
        return componentSettled(
            delta: context.delta.first.first,
            velocity: context.velocity.first.first,
            threshold: pixelLength
        ) && componentSettled(
            delta: context.delta.first.second,
            velocity: context.velocity.first.second,
            threshold: pixelLength
        ) && componentSettled(
            delta: context.delta.second.first,
            velocity: context.velocity.second.first,
            threshold: doublePixelLength
        ) && componentSettled(
            delta: context.delta.second.second,
            velocity: context.velocity.second.second,
            threshold: doublePixelLength
        )
    }

    private static func componentSettled(
        delta: CGFloat,
        velocity: CGFloat,
        threshold: CGFloat
    ) -> Bool {
        let thresholdSquared = threshold * threshold
        return delta * delta + velocity * velocity < thresholdSquared
    }
}

extension EnvironmentValues {
    fileprivate var animationPixelLength: CGFloat {
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

struct UnitCurveAnimation: InternalCustomAnimation {
    var duration: TimeInterval
    var curve: UnitCurve

    var function: Animation.Function {
        curve.animationFunction(duration: duration)
    }

    var animationBox: AnimationBoxBase {
        UnitCurveAnimationBox(curve: curve, duration: duration)
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
final class CustomAnimationBox<Base: CustomAnimation>: AnimationBoxBase, @unchecked Sendable {
    let base: Base
    private let noRegisteredFallbackSampleInterval: TimeInterval = 0.1
    private let noRegisteredFallbackSampleLimit: TimeInterval = 10

    init(base: Base) {
        self.base = base
    }

    override var customAnimationBase: any CustomAnimation {
        base
    }

    override func makeDelayedBase(delay: TimeInterval) -> any CustomAnimation {
        CustomAnimationModifiedContent(base: base, modifier: DelayAnimation(delay: delay))
    }

    override func makeSpeedBase(speed: Double) -> any CustomAnimation {
        CustomAnimationModifiedContent(base: base, modifier: SpeedAnimation(speed: speed))
    }

    override func makeRepeatBase(repeatCount: Int?, autoreverses: Bool) -> any CustomAnimation {
        CustomAnimationModifiedContent(
            base: base,
            modifier: RepeatAnimation(repeatCount: repeatCount, autoreverses: autoreverses)
        )
    }

    override func makeLogicalCompletionBase(duration: TimeInterval) -> any CustomAnimation {
        CustomAnimationModifiedContent(
            base: base,
            modifier: LogicalCompletionModifier(duration: duration)
        )
    }

    override var description: String {
        String(describing: base)
    }

    override var debugDescription: String {
        String(reflecting: base)
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? CustomAnimationBox<Base> else { return false }
        return base == other.base
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(base)
    }

    override var duration: TimeInterval {
        .infinity
    }

    override var preservesRetargetedCompletionDeadlines: Bool {
        true
    }

    override func noRegisteredCompletionDelay() -> TimeInterval? {
        var context = AnimationContext<Double>()
        var time: TimeInterval = 0
        while time <= noRegisteredFallbackSampleLimit {
            if base.animate(value: 1.0, time: time, context: &context) == nil {
                return time
            }
            time += noRegisteredFallbackSampleInterval
        }
        return nil
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

    override var description: String {
        "FluidSpringAnimation(response: \(response), dampingFraction: \(dampingFraction), " +
            "blendDuration: \(blendDuration))"
    }

    override func makeBaseValue() -> any CustomAnimation {
        FluidSpringAnimation(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? FluidSpringAnimationBox else { return false }
        return response == other.response &&
            dampingFraction == other.dampingFraction &&
            blendDuration == other.blendDuration
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(response)
        hasher.combine(dampingFraction)
        hasher.combine(blendDuration)
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
        var state = SpringState<Double>()
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
        var state = context.state[SpringState<Value>.self]
        let effectiveResponse = blendedFluidSpringResponse(
            response: response,
            blendDuration: blendDuration,
            time: time,
            state: state
        )
        let stiffness = fluidSpringStiffness(response: effectiveResponse)
        let output = integratedFluidSpringValue(
            target: value,
            dampingFraction: dampingFraction,
            stiffness: stiffness,
            time: time,
            state: &state
        )
        context.state[SpringState<Value>.self] = state
        if context.shouldFinishEarly(
            data: fluidSpringSettlingData(
                target: value,
                output: output,
                state: state,
                stiffness: stiffness,
                dampingFraction: dampingFraction
            )
        ) {
            return nil
        }
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
        context.state[SpringState<Value>.self].velocity
    }

    override func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        let previousVelocity = previous.box.velocity(
            value: value,
            time: time,
            context: context
        )
        let previousOutput = previous.box.animate(
            value: value,
            time: time,
            context: &context
        )

        var state = context.state[SpringState<Value>.self]
        if !state.isInitialized {
            state.position = previousOutput ?? value
            state.velocity = previousVelocity ?? .zero
            state.isInitialized = true
        }
        state.time = max(state.time, time)

        if let previousSpring = previous.box as? FluidSpringAnimationBox,
           previousSpring.response != response {
            state.responseBlendStartTime = time
            state.responseBlendDelta = previousSpring.response - response
        } else {
            state.responseBlendStartTime = time
            state.responseBlendDelta = 0
        }

        context.state[SpringState<Value>.self] = state
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
        guard !isImmediatelyComplete else {
            return 0
        }
        return max(
            duration,
            spring.settlingDuration(
                target: 1.0,
                initialVelocity: initialVelocity,
                epsilon: 0.007
            )
        )
    }

    override var isImmediatelyComplete: Bool {
        // Infinite stiffness represents a zero-period spring; duration remains
        // clamped only to keep spring math numerically guarded.
        stiffness == .infinity
    }

    override var description: String {
        "SpringAnimation(mass: \(mass), stiffness: \(stiffness), damping: \(damping), " +
            "initialVelocity: \(initialVelocity))"
    }

    override func makeBaseValue() -> any CustomAnimation {
        SpringAnimation(
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: _Velocity(valuePerSecond: initialVelocity)
        )
    }

    override func isEqual(to other: AnimationBoxBase) -> Bool {
        guard let other = other as? SpringAnimationBox else { return false }
        return mass == other.mass &&
            stiffness == other.stiffness &&
            damping == other.damping &&
            initialVelocity == other.initialVelocity
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(mass)
        hasher.combine(stiffness)
        hasher.combine(damping)
        hasher.combine(initialVelocity)
    }

    override func presentationDuration<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        guard !isImmediatelyComplete else {
            return 0
        }
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
        guard clamped < 1, !isImmediatelyComplete else { return 1 }
        return spring.value(target: 1.0, initialVelocity: initialVelocity, time: clamped * duration)
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard !isImmediatelyComplete else {
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
        velocity += target
        return (value, velocity)
    }
}

public struct Animation: Equatable, Sendable {
    indirect enum Function {
        case linear(TimeInterval)
        case circularEaseIn(TimeInterval)
        case circularEaseOut(TimeInterval)
        case circularEaseInOut(TimeInterval)
        case bezier(TimeInterval, CGPoint, CGPoint)
        case spring(TimeInterval, Double, Double, Double, Double)
        case customFunction((Double, inout AnimationContext<Double>) -> Double?)
        case delay(TimeInterval, Function)
        case speed(Double, Function)
        case `repeat`(Double, Bool, Function)

        static func custom<Base>(_ base: Base) -> Function where Base: CustomAnimation {
            .customFunction { time, context in
                base.animate(value: 1, time: time, context: &context)
            }
        }

        var bezierForm: (duration: TimeInterval, cp1: CGPoint, cp2: CGPoint)? {
            if case let .bezier(duration, cp1, cp2) = self {
                return (duration, cp1, cp2)
            }
            return nil
        }
    }

    var box: AnimationBoxBase

    @usableFromInline
    init(box: AnimationBoxBase) {
        self.box = box
    }

    public init<A>(_ base: A) where A: CustomAnimation {
        self.init(box: CustomAnimationBox(base: base))
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.box == rhs.box
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

    var function: Function {
        box.function
    }

    public func hash(into hasher: inout Hasher) {
        box.hash(into: &hasher)
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
        var order: Int
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var activeAnimations: [AnimationCompletionCriteria: Int] = [:]
    private var bodyFinished = false
    private var registeredAnimation = false
    private var completedCriteria = Set<AnimationCompletionCriteria>()
    private var nextEntryOrder = 0

    // Completion observers are shared by every animatable node touched by one
    // transaction. Criteria have separate token counts so logical completion can
    // finish before removal/presentation completion.
    init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        entries.append(Entry(criteria: criteria, completion: completion, order: nextEntryOrder))
        nextEntryOrder += 1
    }

    func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completedCriteria.contains(criteria) else { return }
        entries.append(Entry(criteria: criteria, completion: completion, order: nextEntryOrder))
        nextEntryOrder += 1
    }

    func criteriaForNewAnimation() -> [AnimationCompletionCriteria] {
        lock.lock()
        defer { lock.unlock() }
        return orderedCriteria()
            .filter { !completedCriteria.contains($0) }
    }

    func firstCriteriaForNewAnimation() -> AnimationCompletionCriteria? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { !completedCriteria.contains($0.criteria) }?.criteria
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

    func noRegisteredAnimationFallbackDidFire(usesAnimatedOrdering: Bool) -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        guard !registeredAnimation else {
            return completionsIfReady(allowNoRegisteredAnimation: false)
        }
        if usesAnimatedOrdering {
            return completionsIfReady(allowNoRegisteredAnimation: true)
        }
        return noRegisteredCompletionsIfReady()
    }

    func noRegisteredAnimationFallbackDidFire(criteria: AnimationCompletionCriteria) -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        guard bodyFinished,
              !registeredAnimation,
              !completedCriteria.contains(criteria),
              entries.contains(where: { $0.criteria == criteria }) else {
            return []
        }
        completedCriteria.insert(criteria)
        return entries
            .filter { $0.criteria == criteria }
            .map(\.completion)
    }

    private func noRegisteredCompletionsIfReady() -> [() -> Void] {
        guard bodyFinished else { return [] }
        let pendingEntries = entries.filter { !completedCriteria.contains($0.criteria) }
        guard let firstCriteria = pendingEntries.first?.criteria else { return [] }
        let hasMultipleCriteria = pendingEntries.contains { $0.criteria != firstCriteria }
        let primary = pendingEntries
            .filter { $0.criteria == firstCriteria }
            .sorted {
                hasMultipleCriteria ? $0.order > $1.order : $0.order < $1.order
            }
        let remaining = pendingEntries
            .filter { $0.criteria != firstCriteria }
            .sorted { $0.order < $1.order }
        for entry in pendingEntries {
            completedCriteria.insert(entry.criteria)
        }
        return (primary + remaining).map(\.completion)
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

func enqueueNoRegisteredAnimationFallback(
    _ observer: AnimationCompletionObserver?,
    animation: Animation? = nil
) {
    guard let observer else { return }
    let box = AnimationCompletionObserverBox(observer: observer)
    if let animation {
        if box.observer.firstCriteriaForNewAnimation() == .removed,
           let fallbackDelay = animation.box.noRegisteredCompletionDelay() {
            let fire: @Sendable () -> Void = {
                enqueueAnimationCompletionActions(
                    box.observer.noRegisteredAnimationFallbackDidFire(
                        usesAnimatedOrdering: true
                    )
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fire)
            return
        }
        for criteria in box.observer.criteriaForNewAnimation() {
            guard let fallbackDelay = animation.box.noRegisteredCompletionDelay(for: criteria) else {
                continue
            }
            let fire: @Sendable () -> Void = {
                enqueueAnimationCompletionActions(
                    box.observer.noRegisteredAnimationFallbackDidFire(criteria: criteria)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fire)
        }
    } else {
        let fire: @Sendable () -> Void = {
            enqueueAnimationCompletionActions(
                box.observer.noRegisteredAnimationFallbackDidFire(
                    usesAnimatedOrdering: false
                )
            )
        }
        DispatchQueue.main.async(execute: fire)
    }
}

func finalizeAnimationCompletionObserver(
    _ observer: AnimationCompletionObserver?,
    animation: Animation? = nil,
    bodyDidMutate: Bool = true,
    immediateNoMutationCompletion: Bool = false
) {
    enqueueAnimationCompletionActions(observer?.bodyDidFinish() ?? [])
    guard bodyDidMutate else {
        if immediateNoMutationCompletion {
            enqueueAnimationCompletionActions(
                observer?.noRegisteredAnimationFallbackDidFire(
                    usesAnimatedOrdering: false
                ) ?? []
            )
        } else {
            enqueueNoRegisteredAnimationFallback(observer, animation: nil)
        }
        return
    }
    enqueueNoRegisteredAnimationFallback(observer, animation: animation)
}

extension Animation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        box.description
    }
    public var debugDescription: String {
        "AnyAnimator(\(box.debugDescription))"
    }
    public var customMirror: Mirror {
        Mirror(self, children: ["base": box.customAnimationBase])
    }
}

extension Animation {
    public static let `default`: Animation = Animation(box: DefaultAnimationBox())
    static let velocityTracking: Animation = Animation(VelocityTrackingAnimation())
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
        let curve = UnitCurve.CubicSolver(
            startControlPoint: UnitPoint(x: p1x, y: p1y),
            endControlPoint: UnitPoint(x: p2x, y: p2y)
        )
        return Animation(box: BezierAnimationBox(curve: curve, duration: duration))
    }

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        if let bezier = curve.cubicSolverForAnimation {
            return Animation(box: BezierAnimationBox(curve: bezier, duration: duration))
        }
        return Animation(box: UnitCurveAnimationBox(curve: curve, duration: duration))
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

    public func logicallyComplete(after duration: TimeInterval) -> Animation {
        Animation(box: LogicalCompletionAnimationBox(base: box, duration: duration))
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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
        let stiffness = pow(2 * .pi / max(duration, 0.0), 2)
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
        if bounce >= 0 {
            return max(1 - bounce, 0.0)
        }
        return 1 / max(1 + bounce, 0.001)
    }
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withTransaction(
        Transaction(animation: animation),
        immediateNoMutationCompletion: true,
        body
    )
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping () -> Void
) rethrows -> Result {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: completionCriteria, completion)
    return try withTransaction(
        transaction,
        immediateNoMutationCompletion: true,
        body
    )
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
    struct CubicSolver: Sendable, Hashable {
        let ax, bx, cx, ay, by, cy: Double

        init(startControlPoint: UnitPoint, endControlPoint: UnitPoint) {
            let c1x = Double(startControlPoint.x)
            let c1y = Double(startControlPoint.y)
            let c2x = Double(endControlPoint.x)
            let c2y = Double(endControlPoint.y)
            cx = 3.0 * c1x
            bx = 3.0 * (c2x - c1x) - cx
            ax = 1.0 - cx - bx
            cy = 3.0 * c1y
            by = 3.0 * (c2y - c1y) - cy
            ay = 1.0 - cy - by
        }

        var controlPointsForAnimation: (startControlPoint: CGPoint, endControlPoint: CGPoint) {
            let first = CGPoint(x: cx / 3.0, y: cy / 3.0)
            let second = CGPoint(
                x: bx / 3.0 + 2.0 * first.x,
                y: by / 3.0 + 2.0 * first.y
            )
            return (first, second)
        }

        func solve(x: Double, epsilon: Double = 1e-6) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            return sampleY(solveCurveX(x, epsilon: epsilon))
        }

        func derivative(x: Double, epsilon: Double = 1e-6) -> Double {
            if x <= 0 { return derivative(at: 0) }
            if x >= 1 { return derivative(at: 1) }
            return derivative(at: solveCurveX(x, epsilon: epsilon))
        }

        private func derivative(at t: Double) -> Double {
            let dx = sampleDerivativeX(t)
            let dy = sampleDerivativeY(t)

            if abs(dx) > 1e-12 {
                return dy / dx
            }
            if abs(dy) <= 1e-12 {
                return t <= 0 ? 1 : 0
            }
            return dy > 0 ? .infinity : -.infinity
        }

        private func sampleX(_ t: Double) -> Double {
            ((ax * t + bx) * t + cx) * t
        }

        private func sampleY(_ t: Double) -> Double {
            ((ay * t + by) * t + cy) * t
        }

        private func sampleDerivativeX(_ t: Double) -> Double {
            (3.0 * ax * t + 2.0 * bx) * t + cx
        }

        private func sampleDerivativeY(_ t: Double) -> Double {
            (3.0 * ay * t + 2.0 * by) * t + cy
        }

        private func solveCurveX(_ x: Double, epsilon: Double) -> Double {
            var t = x
            for _ in 0..<8 {
                let x2 = sampleX(t) - x
                if abs(x2) < epsilon { return t }
                let d2 = sampleDerivativeX(t)
                if abs(d2) < 1e-6 { break }
                t -= x2 / d2
            }

            var low: Double = 0
            var high: Double = 1
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

    private enum Function: Sendable, Hashable {
        case linear
        case bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint)
        case circularEaseIn
        case circularEaseOut
        case circularEaseInOut
    }

    private let function: Function

    private init(function: Function) {
        self.function = function
    }

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(function: .bezier(
            startControlPoint: startControlPoint,
            endControlPoint: endControlPoint
        ))
    }

    public func value(at progress: Double) -> Double {
        switch function {
        case .linear:
            return progress
        case let .bezier(startControlPoint, endControlPoint):
            return CubicSolver(
                startControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).solve(x: progress)
        case .circularEaseIn:
            return 1 - sqrt(1 - progress * progress)
        case .circularEaseOut:
            let remaining = 1 - progress
            return sqrt(1 - remaining * remaining)
        case .circularEaseInOut:
            if progress <= 0.5 {
                let scaled = 2 * progress
                return (1 - sqrt(1 - scaled * scaled)) / 2
            }
            let scaled = 2 - 2 * progress
            return (1 + sqrt(1 - scaled * scaled)) / 2
        }
    }

    public func velocity(at progress: Double) -> Double {
        switch function {
        case .linear:
            return 1
        case let .bezier(startControlPoint, endControlPoint):
            return CubicSolver(
                startControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).derivative(x: progress)
        case .circularEaseIn:
            return Self.circularVelocity(numerator: progress, denominator: 1 - progress * progress)
        case .circularEaseOut:
            let remaining = 1 - progress
            return Self.circularVelocity(numerator: remaining, denominator: 1 - remaining * remaining)
        case .circularEaseInOut:
            if progress <= 0.5 {
                let scaled = 2 * progress
                return Self.circularVelocity(numerator: scaled, denominator: 1 - scaled * scaled)
            }
            let scaled = 2 - 2 * progress
            return Self.circularVelocity(numerator: scaled, denominator: 1 - scaled * scaled)
        }
    }

    public var inverse: UnitCurve {
        switch function {
        case .linear:
            return .linear
        case let .bezier(startControlPoint, endControlPoint):
            return UnitCurve.bezier(
                startControlPoint: UnitPoint(x: startControlPoint.y, y: startControlPoint.x),
                endControlPoint: UnitPoint(x: endControlPoint.y, y: endControlPoint.x)
            )
        case .circularEaseIn:
            return .circularEaseOut
        case .circularEaseOut:
            return .circularEaseIn
        case .circularEaseInOut:
            return .circularEaseInOut
        }
    }

    fileprivate var bezierControlPointsForAnimation: (startControlPoint: UnitPoint, endControlPoint: UnitPoint)? {
        switch function {
        case .linear:
            return (UnitPoint(x: 0, y: 0), UnitPoint(x: 1, y: 1))
        case let .bezier(startControlPoint, endControlPoint):
            return (startControlPoint, endControlPoint)
        case .circularEaseIn, .circularEaseOut, .circularEaseInOut:
            return nil
        }
    }

    fileprivate var cubicSolverForAnimation: CubicSolver? {
        guard let controlPoints = bezierControlPointsForAnimation else {
            return nil
        }
        return CubicSolver(
            startControlPoint: controlPoints.startControlPoint,
            endControlPoint: controlPoints.endControlPoint
        )
    }

    fileprivate func animationFunction(duration: TimeInterval) -> Animation.Function {
        switch function {
        case .linear:
            return .linear(duration)
        case let .bezier(startControlPoint, endControlPoint):
            return .bezier(
                duration,
                CGPoint(x: startControlPoint.x, y: startControlPoint.y),
                CGPoint(x: endControlPoint.x, y: endControlPoint.y)
            )
        case .circularEaseIn:
            return .circularEaseIn(duration)
        case .circularEaseOut:
            return .circularEaseOut(duration)
        case .circularEaseInOut:
            return .circularEaseInOut(duration)
        }
    }

    private static func circularVelocity(numerator: Double, denominator: Double) -> Double {
        abs(numerator) / sqrt(denominator)
    }
}

extension UnitCurve {
    public static let linear = UnitCurve(function: .linear)

    public static let easeIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )

    public static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )

    public static let easeInOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )

    public static let circularEaseIn = UnitCurve(function: .circularEaseIn)
    public static let circularEaseOut = UnitCurve(function: .circularEaseOut)
    public static let circularEaseInOut = UnitCurve(function: .circularEaseInOut)
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

    init(controlPoints startControlPoint: UnitPoint, _ endControlPoint: UnitPoint) {
        self.init(
            controlPoints: Double(startControlPoint.x),
            Double(startControlPoint.y),
            Double(endControlPoint.x),
            Double(endControlPoint.y)
        )
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
        if x <= 0 { return derivative(at: 0) }
        if x >= 1 { return derivative(at: 1) }

        let t = solveCurveX(x, epsilon: epsilon)
        return derivative(at: t)
    }

    private func derivative(at t: Double) -> Double {
        let dx = sampleDerivativeX(t)
        let dy = sampleDerivativeY(t)

        if abs(dx) > 1e-12 {
            return dy / dx
        }
        if abs(dy) <= 1e-12 {
            return t <= 0 ? 1 : 0
        }
        return dy > 0 ? .infinity : -.infinity
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
