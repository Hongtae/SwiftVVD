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

    var finishesRetargetCompletionAtActivation: Bool {
        guard !preservesRetargetedCompletionDeadlines else { return false }
        return noRegisteredCompletionDelay() == 0
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

    override func registeredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard let baseDelay = base.registeredCompletionDelay(for: criteria) else {
            return nil
        }
        return max(0, baseDelay + delay)
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

    override func registeredCompletionDelay(for criteria: AnimationCompletionCriteria) -> TimeInterval? {
        guard speed > 0,
              let baseDelay = base.registeredCompletionDelay(for: criteria) else {
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
              repeatCount == nil else {
            return nil
        }
        if let baseDelay = base.registeredCompletionDelay(for: criteria) {
            return baseDelay
        }
        guard usesRepeatForeverRegisteredLogicalDeadline(base) else { return nil }
        return base.isImmediatelyComplete ? 0 : base.duration
    }

    private func usesRepeatForeverRegisteredLogicalDeadline(_ box: AnimationBoxBase) -> Bool {
        if box is DefaultAnimationBox ||
           box is FluidSpringAnimationBox ||
           box is SpringAnimationBox {
            return true
        }
        if let delay = box as? DelayAnimationBox {
            return usesRepeatForeverRegisteredLogicalDeadline(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            return speed.speed > 0 && usesRepeatForeverRegisteredLogicalDeadline(speed.base)
        }
        return false
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
        nil
    }

    override func shouldMerge<Value>(
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
final class FluidSpringAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let response: TimeInterval
    let dampingFraction: Double
    let blendDuration: TimeInterval

    init(response: TimeInterval, dampingFraction: Double, blendDuration: TimeInterval) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }

    override var duration: TimeInterval {
        max(0, response)
    }

    override var presentationDuration: TimeInterval {
        presentationDurationWithAliasFloor(max(
            duration,
            fluidSpringSettlingDuration(
                response: response,
                dampingFraction: dampingFraction,
                target: Double(1)
            )
        ))
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
        presentationDurationWithAliasFloor(max(
            duration,
            fluidSpringSettlingDuration(
                response: response,
                dampingFraction: dampingFraction,
                target: value
            )
        ))
    }

    private func presentationDurationWithAliasFloor(_ duration: TimeInterval) -> TimeInterval {
        guard isDefaultDurationInteractiveSpringAlias else { return duration }
        return max(duration, 0.365)
    }

    private var isDefaultDurationInteractiveSpringAlias: Bool {
        approximatelyEqual(response, 0.15) &&
            approximatelyEqual(dampingFraction, 0.85) &&
            approximatelyEqual(blendDuration, 0.25)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_000_001
    }

    func reachesTargetAtLogicalDuration<Value>(
        for value: Value
    ) -> Bool where Value: VectorArithmetic {
        guard duration > 0 else { return true }

        let stiffness = fluidSpringStiffness(response: response)
        var state = SpringState<Value>()
        let output = integratedFluidSpringValue(
            target: value,
            dampingFraction: dampingFraction,
            stiffness: stiffness,
            time: duration,
            state: &state
        )
        let targetMagnitude = max(sqrt(value.magnitudeSquared), 1)
        var delta = value
        delta -= output
        let deltaMagnitude = sqrt(delta.magnitudeSquared)
        let velocityMagnitude = sqrt(state.velocity.magnitudeSquared)
        let accelerationMagnitude = sqrt(state.acceleration.magnitudeSquared)

        return deltaMagnitude <= targetMagnitude * 0.01 &&
            velocityMagnitude <= targetMagnitude * 0.08 &&
            accelerationMagnitude <= targetMagnitude * 0.12
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
    let usesMassStiffnessDampingWrapperOrdering: Bool

    init(
        mass: Double,
        stiffness: Double,
        damping: Double,
        initialVelocity: Double,
        usesMassStiffnessDampingWrapperOrdering: Bool = true
    ) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        self.initialVelocity = initialVelocity
        self.usesMassStiffnessDampingWrapperOrdering = usesMassStiffnessDampingWrapperOrdering
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
        let stiffness = springStiffness(response: duration)
        let fraction = springDampingFraction(bounce: bounce)
        let damping = springDamping(fraction: fraction, stiffness: stiffness)
        return Animation(
            box: SpringAnimationBox(
                mass: 1.0,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: initialVelocity,
                usesMassStiffnessDampingWrapperOrdering: false
            )
        )
    }

    public static var interpolatingSpring: Animation {
        interpolatingSpring()
    }

    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation {
        Animation(
            box: SpringAnimationBox(
                mass: 1.0,
                stiffness: spring.stiffness / max(spring.mass, 0.001),
                damping: spring.damping / max(spring.mass, 0.001),
                initialVelocity: initialVelocity,
                usesMassStiffnessDampingWrapperOrdering: false
            )
        )
    }

    private static func springStiffness(response: Double) -> Double {
        if response <= 0 {
            return .infinity
        }
        let frequency = (2.0 * Double.pi) / response
        return frequency * frequency
    }

    private static func springDamping(fraction: Double, stiffness: Double) -> Double {
        let criticalDamping = 2 * stiffness.squareRoot()
        return criticalDamping * fraction
    }

    private static func springDampingFraction(bounce: Double) -> Double {
        if bounce <= -1.0 {
            return .infinity
        } else if bounce < 0.0 {
            return 1.0 / (bounce + 1.0)
        } else if bounce == 0.0 {
            return 1.0
        }
        return 1.0 - min(bounce, 1.0)
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
    transaction.addAnimationCompletion(
        criteria: completionCriteria,
        tracksStandalonePending: false,
        completion
    )
    return try withTransaction(
        transaction,
        immediateNoMutationCompletion: true,
        body
    )
}
