//
//  File: Animatable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    public func scaled(by rhs: Double) -> Self {
        var result = self
        result.scale(by: rhs)
        return result
    }

    public mutating func interpolate(towards other: Self, amount: Double) {
        var result = other
        result -= self
        result.scale(by: amount)
        result += self
        self = result
    }

    public func interpolated(towards other: Self, amount: Double) -> Self {
        var result = self
        result.interpolate(towards: other, amount: amount)
        return result
    }
}

public struct AnimatableValues<each Value>: VectorArithmetic where repeat each Value: VectorArithmetic {
    public var value: (repeat each Value)

    @inlinable public init(_ value: repeat each Value) {
        self.value = (repeat each value)
    }

    public init(_ _valueType: repeat (each Value).Type) {
        self.value = (repeat (each _valueType).zero)
    }

    public static var zero: AnimatableValues<repeat each Value> {
        AnimatableValues(repeat (each Value).zero)
    }

    public static func += (
        lhs: inout AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) {
        lhs = AnimatableValues(repeat each lhs.value + each rhs.value)
    }

    public static func -= (
        lhs: inout AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) {
        lhs = AnimatableValues(repeat each lhs.value - each rhs.value)
    }

    public static func + (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> AnimatableValues<repeat each Value> {
        AnimatableValues(repeat each lhs.value + each rhs.value)
    }

    public static func - (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> AnimatableValues<repeat each Value> {
        AnimatableValues(repeat each lhs.value - each rhs.value)
    }

    public mutating func scale(by rhs: Double) {
        value = (repeat (each value).scaled(by: rhs))
    }

    public var magnitudeSquared: Double {
        var result = 0.0
        for value in repeat each value {
            result += value.magnitudeSquared
        }
        return result
    }

    public static func == (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> Bool {
        for (lhsValue, rhsValue) in repeat (each lhs.value, each rhs.value) {
            if lhsValue != rhsValue {
                return false
            }
        }
        return true
    }
}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: Self.AnimatableData { get set }

    static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}

extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        @inlinable get { return EmptyAnimatableData() }
        @inlinable set {}
    }
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
    }
}

extension Animatable {
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.Type where T: VectorArithmetic {
        T.self
    }

    @_disfavoredOverload
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.AnimatableData.Type where T: Animatable {
        T.AnimatableData.self
    }

    @_disfavoredOverload
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.Type {
        T.self
    }

    @inline(__always)
    public subscript<T>(_animatableValue keyPath: WritableKeyPath<Self, T>) -> T where T: VectorArithmetic {
        get { self[keyPath: keyPath] }
        set { self[keyPath: keyPath] = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue keyPath: WritableKeyPath<Self, T>) -> T.AnimatableData where T: Animatable {
        get { self[keyPath: keyPath].animatableData }
        set { self[keyPath: keyPath].animatableData = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue _: WritableKeyPath<Self, T>) -> EmptyAnimatableData {
        get { .zero }
        nonmutating set {}
    }

    @inline(__always)
    public subscript<T>(_animatableValue keyPath: ReferenceWritableKeyPath<Self, T>) -> T where T: VectorArithmetic {
        get { self[keyPath: keyPath] }
        nonmutating set { self[keyPath: keyPath] = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue keyPath: ReferenceWritableKeyPath<Self, T>) -> T.AnimatableData where T: Animatable {
        get { self[keyPath: keyPath].animatableData }
        nonmutating set { self[keyPath: keyPath].animatableData = newValue }
    }
}

public func _animatableMacroKind() -> AnimatableValues<> {
    let result: AnimatableValues<> = .zero
    return result
}

extension Animatable {
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeAnimatable called outside an active AttributeGraph context.")
        }
        let attr: Attribute<Self> = graph.makeStatefulRule(
            AnimatableAttribute(
                source: value._attribute,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                environment: inputs.cachedEnvironment.value.environment
            )
        )
        value = _GraphValue(_attribute: attr)
    }
}

private func isSourceDefinedCustomAnimationBox(_ box: AnimationBoxBase) -> Bool {
    !box.duration.isFinite && box.preservesRetargetedCompletionDeadlines
}

private func isVelocityTrackingAnimationBox(_ box: AnimationBoxBase) -> Bool {
    box is CustomAnimationBox<VelocityTrackingAnimation>
}

private func isDefaultCombiningAnimationBox(_ box: AnimationBoxBase) -> Bool {
    box is CustomAnimationBox<DefaultCombiningAnimation>
}

private func isSourceCustomReplacementAnimationBox(_ box: AnimationBoxBase) -> Bool {
    isSourceDefinedCustomAnimationBox(box) &&
        !isDefaultCombiningAnimationBox(box) &&
        !isVelocityTrackingAnimationBox(box)
}

private func resolvedAnimationEnvironment(
    _ environment: Attribute<EnvironmentValues>?
) -> EnvironmentValues {
    environment?.value ?? EnvironmentValues()
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.reversed() {
            remove(at: offset)
        }
    }
}

private final class AnimatorState<AnimatedValue: Animatable> {
    enum Phase {
        case pending
        case first
        case second
        case running
    }

    struct Fork {
        var animation: Animation
        var state: AnimationState<AnimatedValue.AnimatableData>
        var interval: AnimatedValue.AnimatableData
        var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
        var listeners: [AnimationListener] = []

        mutating func update(
            time: Time,
            environment: Attribute<EnvironmentValues>?
        ) -> Bool {
            var context = makeAnimationContext(
                state: state,
                isLogicallyComplete: false,
                environment: resolvedAnimationEnvironment(environment),
                finishingDefinition: finishingDefinition
            )
            let animatedDelta = animation.box.animate(
                value: interval,
                time: time.seconds,
                context: &context
            )

            state = context.state
            return animatedDelta == nil || context.isLogicallyComplete
        }
    }

    struct PresentationLayer {
        var animation: Animation
        var startValue: AnimatedValue
        var targetValue: AnimatedValue
        var startTime: Time
        var state: AnimationState<AnimatedValue.AnimatableData>
        var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
        var contextIsLogicallyComplete: Bool = false
        var generation: UInt64
        var isFinished: Bool = false

        mutating func update(
            time: Time,
            environment: Attribute<EnvironmentValues>?,
            baseValue: AnimatedValue
        ) -> AnimatedValue {
            guard !isFinished else {
                return targetValue
            }

            let elapsed = max(time.seconds - startTime.seconds, 0)
            var context = makeAnimationContext(
                state: state,
                isLogicallyComplete: contextIsLogicallyComplete,
                environment: resolvedAnimationEnvironment(environment),
                finishingDefinition: finishingDefinition
            )
            let animatedDelta = animation.box.animate(
                value: AnimatorState.animatableDelta(from: baseValue, to: targetValue),
                time: elapsed,
                context: &context
            )

            state = context.state
            contextIsLogicallyComplete = context.isLogicallyComplete
            guard let animatedDelta else {
                isFinished = true
                return targetValue
            }

            return AnimatorState.applying(
                delta: animatedDelta,
                to: baseValue,
                target: targetValue
            )
        }
    }

    private var animation: Animation?
    private var interval: AnimatedValue.AnimatableData = .zero
    private var beginTime: Time = .zero
    private var quantizedFrameInterval: TimeInterval = 0
    private var nextTime: Time = .zero
    private var previousAnimationValue: AnimatedValue.AnimatableData = .zero
    private var reason: UInt32?
    private var state = AnimationState<AnimatedValue.AnimatableData>()
    private var mergeState = AnimationState<AnimatedValue.AnimatableData>()
    private var phase: Phase = .pending
    private var listeners: [AnimationListener] = []
    private var logicalListeners: [AnimationListener] = []
    private var isLogicallyComplete = false
    private var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    private var updatesMergeStateWithAnimation = true
    private var forks: [Fork] = []
    private var baseLayers: [PresentationLayer] = []
    private var completedBaseLayerValue: AnimatedValue?

    init() {}

    init(
        animation: Animation,
        interval: AnimatedValue.AnimatableData,
        at time: Time,
        in transaction: Transaction
    ) {
        self.animation = animation
        self.interval = interval
        self.beginTime = time
        self.nextTime = time
        self.finishingDefinition = Self.defaultFinishingDefinition
        reason = transaction.animationReason
        updateFrameInterval(from: transaction)
    }

    struct UpdateResult {
        var continues: Bool
        var time: Time
        var isLogicallyComplete: Bool
        var logicalListeners: [Listener] = []
        var removedListeners: [Listener] = []
        var discardedBaseLayerGenerations: Set<UInt64> = []
    }

    struct ListenerRegistration {
        var records: [Listener] = []
        var immediateActions: [() -> Void] = []
    }

    struct CombineResult {
        var merged: Bool
        var layerStackConversion: LayerStackConversion?
        var presentationLayer: PresentationLayer?
        var finishesRetargetCompletionAtActivation: Bool = false
    }

    struct LayerStackConversion {
        var animation: Animation
        var state: AnimationState<AnimatedValue.AnimatableData>
        var start: AnimatedValue
        var startTime: Time
    }

    struct RetargetPresentationSeed {
        var startValue: AnimatedValue
        var targetValue: AnimatedValue
        var startTime: Time
        var generation: UInt64
    }

    struct RetargetStateSnapshot {
        var animation: Animation?
        var state: AnimationState<AnimatedValue.AnimatableData>
        var mergeState: AnimationState<AnimatedValue.AnimatableData>
        var beginTime: Time
        var isLogicallyComplete: Bool
        var updatesMergeStateWithAnimation: Bool
        var baseLayers: [PresentationLayer]
        var baseLayerStartValue: AnimatedValue?
    }

    struct InterpolationStateSnapshot {
        var animation: Animation?
        var state: AnimationState<AnimatedValue.AnimatableData>
        var beginTime: Time
        var isLogicallyComplete: Bool
        var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    }

    struct Listener {
        struct Identity: Hashable {
            var listenerID: ObjectIdentifier
            var criteria: AnimationCompletionCriteria
        }

        var listener: AnimationListener
        var criteria: AnimationCompletionCriteria

        var identity: Identity {
            Identity(
                listenerID: ObjectIdentifier(listener),
                criteria: criteria
            )
        }

        func finish() -> [() -> Void] {
            listener.animationWasRemoved()
        }
    }

    func activate(
        animation: Animation,
        interval: AnimatedValue.AnimatableData,
        beginTime: Time,
        sampleTime: Time,
        transaction: Transaction,
        state: AnimationState<AnimatedValue.AnimatableData>,
        mergeState: AnimationState<AnimatedValue.AnimatableData>,
        isLogicallyComplete: Bool,
        updatesMergeStateWithAnimation: Bool
    ) {
        if self.animation == nil {
            phase = .pending
            previousAnimationValue = .zero
        }
        self.animation = animation
        self.interval = interval
        self.beginTime = beginTime
        self.nextTime = sampleTime
        self.state = state
        self.mergeState = mergeState
        self.isLogicallyComplete = isLogicallyComplete
        self.finishingDefinition = Self.defaultFinishingDefinition
        self.updatesMergeStateWithAnimation = updatesMergeStateWithAnimation
        reason = transaction.animationReason
        updateFrameInterval(from: transaction)
    }

    func updateInterval(_ interval: AnimatedValue.AnimatableData) {
        self.interval = interval
    }

    func resetForReplacement() {
        state = AnimationState()
        mergeState = AnimationState()
        isLogicallyComplete = false
    }

    func resetForFreshActivation() {
        resetForReplacement()
        animation = nil
    }

    func retargetStateSnapshot() -> RetargetStateSnapshot {
        RetargetStateSnapshot(
            animation: animation,
            state: state,
            mergeState: mergeState,
            beginTime: beginTime,
            isLogicallyComplete: isLogicallyComplete,
            updatesMergeStateWithAnimation: updatesMergeStateWithAnimation,
            baseLayers: baseLayers,
            baseLayerStartValue: baseLayerStartValue
        )
    }

    func interpolationStateSnapshot(
        defaultFinishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    ) -> InterpolationStateSnapshot {
        InterpolationStateSnapshot(
            animation: animation,
            state: state,
            beginTime: beginTime,
            isLogicallyComplete: isLogicallyComplete,
            finishingDefinition: finishingDefinition ?? defaultFinishingDefinition
        )
    }

    func baseLayerGenerations() -> Set<UInt64> {
        Set(baseLayers.map(\.generation))
    }

    func appendBaseLayer(_ layer: PresentationLayer) {
        baseLayers.append(layer)
    }

    func combine(
        newAnimation: Animation,
        newInterval: AnimatedValue.AnimatableData,
        layerStack: [PresentationLayer]? = nil,
        layerStackBase: AnimatedValue? = nil,
        replacementTarget: AnimatedValue? = nil,
        presentationSeed: RetargetPresentationSeed? = nil,
        at time: Time,
        in transaction: Transaction,
        environment: Attribute<EnvironmentValues>?
    ) -> CombineResult {
        let finishesAtActivation = newAnimation.box.finishesRetargetCompletionAtActivation
        guard let previousAnimation = animation else {
            resetForReplacement()
            refreshScheduling(at: time, from: transaction)
            return CombineResult(
                merged: false,
                layerStackConversion: nil,
                presentationLayer: nil
            )
        }
        if phase == .pending {
            animation = newAnimation
            interval = newInterval
            refreshScheduling(at: time, from: transaction)
            return CombineResult(
                merged: false,
                layerStackConversion: nil,
                presentationLayer: nil,
                finishesRetargetCompletionAtActivation: finishesAtActivation
            )
        }
        let elapsed = max(time.seconds - beginTime.seconds, 0)
        var context = makeAnimationContext(
            state: mergeState,
            isLogicallyComplete: false,
            environment: resolvedAnimationEnvironment(environment),
            finishingDefinition: finishingDefinition
        )
        forkListeners(
            animation: previousAnimation,
            state: state,
            interval: interval
        )
        let presentationLayer = makeRetargetPresentationLayer(
            previousAnimation,
            seed: presentationSeed,
            replacementAnimation: newAnimation
        )
        let shouldMerge = newAnimation.box.shouldMerge(
            previous: previousAnimation,
            value: interval,
            time: elapsed,
            context: &context
        )
        if shouldMerge {
            state = context.state
            mergeState = context.state
            isLogicallyComplete = context.isLogicallyComplete
            animation = newAnimation
            interval += newInterval
        } else {
            if let layerStack,
               let replacementTarget,
               let presentationLayer,
               let conversion = combineLayerStack(
                   layerStack + [presentationLayer],
                   base: layerStackBase,
                   appending: newAnimation,
                   target: replacementTarget,
                   at: time
               ) {
                animation = conversion.animation
                state = conversion.state
                mergeState = AnimationState()
                isLogicallyComplete = false
                interval = Self.animatableDelta(
                    from: conversion.start,
                    to: replacementTarget
                )
                beginTime = conversion.startTime
                refreshScheduling(at: time, from: transaction)
                return CombineResult(
                    merged: false,
                    layerStackConversion: conversion,
                    presentationLayer: presentationLayer,
                    finishesRetargetCompletionAtActivation: finishesAtActivation
                )
            } else {
                combineCurrentAnimation(
                    previousAnimation,
                    newAnimation: newAnimation,
                    newInterval: newInterval,
                    elapsed: elapsed
                )
            }
        }
        refreshScheduling(at: time, from: transaction)
        return CombineResult(
            merged: shouldMerge,
            layerStackConversion: nil,
            presentationLayer: presentationLayer,
            finishesRetargetCompletionAtActivation: finishesAtActivation
        )
    }

    func update(
        _ value: inout AnimatedValue.AnimatableData,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> Bool {
        guard let sample = sampleAnimationValue(
            value: &value,
            at: time,
            environment: environment
        ) else {
            return false
        }
        if sample.didRunAnimation {
            updateListeners(
                isLogicallyComplete: sample.isLogicallyComplete,
                time: sample.elapsed,
                environment: environment
            )
        }
        return sample.output != nil
    }

    func updateForCompletionRecords(
        value: inout AnimatedValue.AnimatableData,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> UpdateResult? {
        guard let sample = sampleAnimationValue(
            value: &value,
            at: time,
            environment: environment
        ) else {
            return nil
        }
        let logicalListeners = sample.didRunAnimation
            ? updateListenersForCompletionRecords(
                isLogicallyComplete: sample.isLogicallyComplete,
                time: sample.elapsed,
                environment: environment
            )
            : []
        let removedListeners: [Listener]
        let discardedBaseLayerGenerations: Set<UInt64>
        if sample.output == nil {
            discardedBaseLayerGenerations = baseLayerGenerations()
            removedListeners = removedListenersForCompletionRecords()
        } else {
            discardedBaseLayerGenerations = []
            removedListeners = []
        }
        return UpdateResult(
            continues: sample.output != nil,
            time: time,
            isLogicallyComplete: sample.isLogicallyComplete,
            logicalListeners: logicalListeners,
            removedListeners: removedListeners,
            discardedBaseLayerGenerations: discardedBaseLayerGenerations
        )
    }

    private func sampleAnimationValue(
        value: inout AnimatedValue.AnimatableData,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> (
        output: AnimatedValue.AnimatableData?,
        elapsed: Time,
        isLogicallyComplete: Bool,
        didRunAnimation: Bool
    )? {
        guard let animation else {
            return nil
        }
        let targetData = value

        if shouldUsePreviousAnimationValue(at: time) {
            let output = restorePreviousAnimationValue(value: &value)
            return (
                output: output,
                elapsed: time,
                isLogicallyComplete: isLogicallyComplete,
                didRunAnimation: false
            )
        }

        switch phase {
        case .pending:
            beginTime = time
            phase = .first
        case .first:
            phase = .second
            let elapsedFromPreviousBegin = nextTime.seconds - beginTime.seconds
            nextTime = Time(seconds: time.seconds + elapsedFromPreviousBegin)
            beginTime = time
            let output = restorePreviousAnimationValue(value: &value)
            return (
                output: output,
                elapsed: time,
                isLogicallyComplete: isLogicallyComplete,
                didRunAnimation: false
            )
        case .second:
            let frameInterval = max(quantizedFrameInterval, 1.0 / 60.0)
            let minimumElapsed = frameInterval * 2.0
            let elapsed = time.seconds - beginTime.seconds
            if minimumElapsed < elapsed {
                beginTime = Time(seconds: time.seconds - minimumElapsed)
            }
            phase = .running
        case .running:
            break
        }

        let elapsed = max(time.seconds - beginTime.seconds, 0)
        var context = makeAnimationContext(
            state: state,
            isLogicallyComplete: isLogicallyComplete,
            environment: resolvedAnimationEnvironment(environment),
            finishingDefinition: finishingDefinition
        )
        let output = animation.box.animate(
            value: interval,
            time: elapsed,
            context: &context
        )
        state = context.state
        isLogicallyComplete = context.isLogicallyComplete
        if let output {
            value = resolvedData(
                targetData: targetData,
                animationValue: output
            )
            recordSampledAnimationValue(value, at: time)
            if updatesMergeStateWithAnimation {
                mergeState = context.state
            }
        }
        return (
            output: output,
            elapsed: Time(seconds: elapsed),
            isLogicallyComplete: context.isLogicallyComplete,
            didRunAnimation: true
        )
    }

    func update(
        value: inout AnimatedValue,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> Bool {
        let targetValue = value
        var targetData = value.animatableData
        if let baseStackValue = sampleBaseStackValue(
            at: time,
            environment: environment
        ) {
            targetData = baseStackValue.animatableData
            targetData += interval
        }

        let continues = update(
            &targetData,
            at: time,
            environment: environment
        )

        if continues {
            value.animatableData = targetData
        } else {
            value = targetValue
        }
        return continues
    }

    func updateForCompletionRecords(
        value: inout AnimatedValue,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> UpdateResult? {
        let targetValue = value
        var targetData = value.animatableData
        if let baseStackValue = sampleBaseStackValue(
            at: time,
            environment: environment
        ) {
            targetData = baseStackValue.animatableData
            targetData += interval
        }

        guard let update = updateForCompletionRecords(
            value: &targetData,
            at: time,
            environment: environment
        ) else {
            return nil
        }

        if update.continues {
            value.animatableData = targetData
        } else {
            value = targetValue
        }
        return update
    }

    func sampleBaseStackValue(
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> AnimatedValue? {
        guard !baseLayers.isEmpty || completedBaseLayerValue != nil else {
            return nil
        }

        var baseValue = completedBaseLayerValue ?? baseLayers[0].startValue
        for index in baseLayers.indices {
            var layer = baseLayers[index]
            let result = layer.update(
                time: time,
                environment: environment,
                baseValue: baseValue
            )
            baseValue = result
            baseLayers[index] = layer
        }

        pruneFinishedBaseLayerPrefix()

        return baseValue
    }

    func recordSampledAnimationValue(
        _ value: AnimatedValue.AnimatableData,
        at time: Time
    ) {
        previousAnimationValue = value
        if quantizedFrameInterval > 0 {
            let frame = (time.seconds / quantizedFrameInterval).rounded(.toNearestOrAwayFromZero)
            nextTime = Time(seconds: (frame + 1.0) * quantizedFrameInterval)
        } else {
            nextTime = time
        }
    }

    func nextUpdate() {
        guard animation != nil else { return }
        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError("AnimatorState.nextUpdate requires an active ViewGraph host.")
        }
        viewGraph.nextUpdate.views.at(nextTime)
        viewGraph.nextUpdate.views.interval(quantizedFrameInterval, reason: reason)
    }

    private func shouldUsePreviousAnimationValue(at time: Time) -> Bool {
        guard quantizedFrameInterval > 0 else { return false }
        return time.seconds <= nextTime.seconds - (quantizedFrameInterval * 0.5)
    }

    private func restorePreviousAnimationValue(
        value: inout AnimatedValue.AnimatableData
    ) -> AnimatedValue.AnimatableData {
        let output = previousAnimationValue
        value = resolvedData(
            targetData: value,
            animationValue: output
        )
        return output
    }

    private func resolvedData(
        targetData: AnimatedValue.AnimatableData,
        animationValue: AnimatedValue.AnimatableData
    ) -> AnimatedValue.AnimatableData {
        var data = targetData
        data -= interval
        data += animationValue
        return data
    }

    func addListeners(
        transaction: Transaction
    ) {
        let registration = registerListeners(transaction: transaction)
        enqueueAnimationCompletionActions(registration.immediateActions)
    }

    func addListenersForCompletionRecords(
        transaction: Transaction
    ) -> ListenerRegistration {
        registerListeners(transaction: transaction)
    }

    private func registerListeners(
        transaction: Transaction
    ) -> ListenerRegistration {
        guard transaction.animationListener != nil ||
              transaction.animationLogicalListener != nil else {
            return ListenerRegistration()
        }

        var registeredListeners: [Listener] = []
        var immediateActions: [() -> Void] = []
        if let animationListener = transaction.animationListener {
            let registration = registerListener(
                animationListener,
                isLogical: false
            )
            registeredListeners.append(contentsOf: registration.records)
            immediateActions.append(contentsOf: registration.immediateActions)
        }
        if let animationLogicalListener = transaction.animationLogicalListener {
            let registration = registerListener(
                animationLogicalListener,
                isLogical: true
            )
            registeredListeners.append(contentsOf: registration.records)
            immediateActions.append(contentsOf: registration.immediateActions)
        }

        // Existing VUI completion ordering prepends newly registered records one
        // at a time. Return the reversed batch so inserting at the front keeps
        // the same newest-first record order while registration moves into
        // AnimatorState.
        return ListenerRegistration(
            records: registeredListeners.reversed(),
            immediateActions: immediateActions
        )
    }

    private func registerListener(
        _ animationListener: AnimationListener,
        isLogical: Bool
    ) -> ListenerRegistration {
        let criteria: AnimationCompletionCriteria = isLogical
            ? .logicallyComplete
            : .removed
        animationListener.animationWasAdded()
        let record = Listener(
            listener: animationListener,
            criteria: criteria
        )
        if isLogical {
            if !isLogicallyComplete {
                logicalListeners.append(animationListener)
                return ListenerRegistration(records: [record])
            }
            return ListenerRegistration(
                immediateActions: record.finish()
            )
        }

        listeners.append(animationListener)
        return ListenerRegistration(
            records: [record]
        )
    }

    private func updateListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?
    ) {
        let completed = updateListenersForCompletionRecords(
            isLogicallyComplete: isLogicallyComplete,
            time: time,
            environment: environment
        )
        enqueueAnimationCompletionActions(completed.flatMap { $0.finish() })
    }

    private func updateListenersForCompletionRecords(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> [Listener] {
        var completed: [Listener] = []
        guard isLogicallyComplete, !logicalListeners.isEmpty else {
            updateForkListeners(
                time: time,
                environment: environment,
                into: &completed
            )
            return completed
        }
        completed.append(contentsOf: logicalListeners.map {
            Listener(listener: $0, criteria: .logicallyComplete)
        })
        logicalListeners.removeAll()
        updateForkListeners(
            time: time,
            environment: environment,
            into: &completed
        )
        return completed
    }

    private func updateForkListeners(
        time: Time,
        environment: Attribute<EnvironmentValues>?,
        into completed: inout [Listener]
    ) {
        guard !forks.isEmpty else { return }
        var completedForkOffsets = IndexSet()
        for index in forks.indices {
            if forks[index].update(time: time, environment: environment) {
                completed.append(contentsOf: forks[index].listeners.map {
                    Listener(listener: $0, criteria: .logicallyComplete)
                })
                completedForkOffsets.insert(index)
            }
        }
        forks.remove(atOffsets: completedForkOffsets)
    }

    func removeListeners() {
        let actions = finishRemovedListenersBeforeClearingStorage()
        enqueueAnimationCompletionActions(actions)
    }

    private func removedListenersForCompletionRecords() -> [Listener] {
        var removed = listeners.map {
            Listener(listener: $0, criteria: .removed)
        }
        removed.append(contentsOf: logicalListeners.map {
            Listener(listener: $0, criteria: .logicallyComplete)
        })
        for fork in forks {
            removed.append(
                contentsOf: fork.listeners.map {
                    Listener(listener: $0, criteria: .logicallyComplete)
                }
            )
        }
        listeners.removeAll()
        logicalListeners.removeAll()
        forks.removeAll()
        return removed
    }

    func clearListenersForCompletionRecords() {
        listeners.removeAll()
        logicalListeners.removeAll()
        forks.removeAll()
    }

    private func finishRemovedListenersBeforeClearingStorage() -> [() -> Void] {
        var actions: [() -> Void] = []
        actions.append(contentsOf: listeners.flatMap {
            Listener(listener: $0, criteria: .removed).finish()
        })
        listeners.removeAll()
        actions.append(contentsOf: logicalListeners.flatMap {
            Listener(listener: $0, criteria: .logicallyComplete).finish()
        })
        logicalListeners.removeAll()
        for fork in forks {
            actions.append(contentsOf: fork.listeners.flatMap {
                Listener(listener: $0, criteria: .logicallyComplete).finish()
            })
        }
        forks.removeAll()
        return actions
    }

    func forkListeners(
        animation: Animation,
        state: AnimationState<AnimatedValue.AnimatableData>,
        interval: AnimatedValue.AnimatableData
    ) {
        guard !isLogicallyComplete, !logicalListeners.isEmpty else {
            return
        }
        forks.append(
            Fork(
                animation: animation,
                state: state,
                interval: interval,
                finishingDefinition: finishingDefinition,
                listeners: logicalListeners
            )
        )
        logicalListeners.removeAll()
    }

    private func makeRetargetPresentationLayer(
        _ previousAnimation: Animation,
        seed: RetargetPresentationSeed?,
        replacementAnimation: Animation
    ) -> PresentationLayer? {
        guard let seed,
              !replacementAnimation.box.finishesRetargetCompletionAtActivation else {
            return nil
        }
        return PresentationLayer(
            animation: previousAnimation,
            startValue: seed.startValue,
            targetValue: seed.targetValue,
            startTime: seed.startTime,
            state: state,
            finishingDefinition: finishingDefinition,
            contextIsLogicallyComplete: isLogicallyComplete,
            generation: seed.generation
        )
    }

    func removeBaseLayers() {
        baseLayers.removeAll()
        completedBaseLayerValue = nil
    }

    private var baseLayerStartValue: AnimatedValue? {
        completedBaseLayerValue ?? baseLayers.first?.startValue
    }

    private func pruneFinishedBaseLayerPrefix() {
        var removeCount = 0
        for layer in baseLayers {
            guard layer.isFinished else {
                break
            }
            completedBaseLayerValue = layer.targetValue
            removeCount += 1
        }
        if removeCount > 0 {
            baseLayers.removeFirst(removeCount)
        }
    }

    private func updateFrameInterval(from transaction: Transaction) {
        guard let interval = transaction.animationFrameInterval,
              interval > 0 else {
            quantizedFrameInterval = 0
            return
        }
        quantizedFrameInterval = floor((interval * 120.0) + 0.01) / 120.0
    }

    private func refreshScheduling(at time: Time, from transaction: Transaction) {
        nextTime = time
        updateFrameInterval(from: transaction)
        reason = transaction.animationReason
    }

    private func combineCurrentAnimation(
        _ previousAnimation: Animation,
        newAnimation: Animation,
        newInterval: AnimatedValue.AnimatableData,
        elapsed: TimeInterval
    ) {
        var combinedAnimation = previousAnimation
        var combinedState = state
        combineAnimation(
            into: &combinedAnimation,
            state: &combinedState,
            value: interval,
            elapsed: elapsed,
            newAnimation: newAnimation,
            newValue: newInterval
        )
        animation = combinedAnimation
        state = combinedState
        mergeState = AnimationState()
        isLogicallyComplete = false
        interval += newInterval
    }

    private func combineLayerStack(
        _ layers: [PresentationLayer],
        base baseValue: AnimatedValue?,
        appending replacementAnimation: Animation,
        target replacementTarget: AnimatedValue,
        at time: Time
    ) -> LayerStackConversion? {
        guard let firstLayer = layers.first,
              let lastLayer = layers.last else {
            return nil
        }

        var entries: [DefaultCombiningAnimation.Entry] = []
        var stateEntries: [CombinedAnimationState<AnimatedValue.AnimatableData>.Entry] = []
        entries.reserveCapacity(layers.count)
        stateEntries.reserveCapacity(layers.count)

        let startValue = baseValue ?? firstLayer.startValue

        for layer in layers {
            entries.append(
                DefaultCombiningAnimation.Entry(
                    animation: layer.animation,
                    elapsed: max(layer.startTime.seconds - firstLayer.startTime.seconds, 0)
                )
            )
            stateEntries.append(
                CombinedAnimationState.Entry(
                    value: Self.animatableDelta(
                        from: startValue,
                        to: layer.targetValue
                    ),
                    state: layer.state
                )
            )
        }

        var combinedAnimation = Animation(DefaultCombiningAnimation(entries: entries))
        var combinedState = AnimationState<AnimatedValue.AnimatableData>()
        combinedState.combinedState = CombinedAnimationState(entries: stateEntries)
        combineAnimation(
            into: &combinedAnimation,
            state: &combinedState,
            value: Self.animatableDelta(from: startValue, to: lastLayer.targetValue),
            elapsed: max(time.seconds - firstLayer.startTime.seconds, 0),
            newAnimation: replacementAnimation,
            newValue: Self.animatableDelta(from: lastLayer.targetValue, to: replacementTarget)
        )

        return LayerStackConversion(
            animation: combinedAnimation,
            state: combinedState,
            start: startValue,
            startTime: firstLayer.startTime
        )
    }

    private static func animatableDelta(
        from start: AnimatedValue,
        to target: AnimatedValue
    ) -> AnimatedValue.AnimatableData {
        var data = target.animatableData
        data -= start.animatableData
        return data
    }

    private static func applying(
        delta: AnimatedValue.AnimatableData,
        to start: AnimatedValue,
        target: AnimatedValue
    ) -> AnimatedValue {
        var data = start.animatableData
        data += delta

        var output = target
        output.animatableData = data
        return output
    }

    private static var defaultFinishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)? {
        AnimatedValue.self as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type
    }
}

private struct AnimatableAttribute<AnimatedValue: Animatable>: StatefulRule {
    typealias Value = AnimatedValue

    var _source: Attribute<AnimatedValue>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<AnimatedValue>

    var startValue: AnimatedValue?
    var targetValue: AnimatedValue?
    private var samplingLayers: [SideEffectSamplingLayer] = []
    private var customReplacementCompletionGroup: CustomReplacementCompletionGroup?
    private var combinedResidualCompletionGroup: CombinedResidualCompletionGroup?
    private var combinedFiniteCompletionGroup: CombinedFiniteCompletionGroup?
    private var velocityTrackingImmediateCompletionGroup: CustomReplacementCompletionGroup?
    private var contextLogicalCompletionSuppressedGenerations: Set<UInt64> = []
    private var deadlineOwnedLogicalCompletionGenerations: Set<UInt64> = []
    private var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 1
    // Each entry represents one transaction completion listener waiting on
    // this animatable node. Retargeting extends older entries to the
    // replacement animation deadline while the newest listener is inserted
    // first.
    private var completionRecords: [CompletionRecord] = []

    private typealias AnimationLayer = AnimatorState<AnimatedValue>.PresentationLayer
    private typealias StateListener = AnimatorState<AnimatedValue>.Listener

    private struct CompletionRecord {
        var listener: StateListener
        var deadline: Time
        var generation: UInt64
        var orderGeneration: UInt64

        var criteria: AnimationCompletionCriteria {
            listener.criteria
        }

        var identity: StateListener.Identity {
            listener.identity
        }

        func finish() -> [() -> Void] {
            listener.finish()
        }
    }

    private mutating func clearAnimationRuntimeState(
        clearingGeneration: Bool = true
    ) {
        helper.clearAnimatorStateForCompletionRecords()
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
        deadlineOwnedLogicalCompletionGenerations.removeAll()
        if clearingGeneration {
            currentGeneration = nil
        }
    }

    private struct SideEffectSamplingLayer {
        var layers: [AnimationLayer]
    }

    private struct SideEffectSamplingResult {
        var isComplete: Bool
        var didFinishCurrentAnimation: Bool
    }

    private struct CustomReplacementCompletionGroup {
        var replacementGeneration: UInt64
        var oldGenerations: Set<UInt64>
        var prefersReplacementLogicalBeforeRemoved: Bool = false
    }

    private struct CombinedResidualCompletionGroup {
        var replacementGeneration: UInt64
        var oldGenerations: [UInt64]
        var prefersOldLogicalBeforeRemoved: Bool
        var prefersReplacementLogicalBeforeRemoved: Bool
        var prefersReplacementLogicalBeforeSourceLogical: Bool
    }

    private struct CombinedFiniteCompletionGroup {
        var replacementGeneration: UInt64
        var oldGenerations: Set<UInt64>
    }

    init(
        source: Attribute<AnimatedValue>,
        phase: Attribute<Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        environment: Attribute<EnvironmentValues>
    ) {
        self._source = source
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("AnimatableAttribute.updateValue called outside an active AttributeGraph context.")
        }

        var updateValue = (value: _source.value, changed: false)
        let sourceID = _source.identifier
        let updateInputs = helper.beginUpdate(
            value: &updateValue,
            defaultAnimation: nil,
            transaction: {
                graph.transaction(for: sourceID)
            }
        )
        let target = updateInputs.target
        if updateInputs.didReset {
            resetAnimationStateForPhaseChange()
            finishValue(with: target)
            return
        }
        let previousOutput: AnimatedValue? = AttributeGraph.currentStatefulOutput()

        guard let previousOutput else {
            finishValue(with: target)
            return
        }

        if let animationBranch = updateInputs.targetAnimationBranch {
            switch animationBranch {
            case .noAnimation:
                guard let fallbackValue = continueAnimationAfterNoAnimationRetarget(
                    to: target,
                    currentOutput: previousOutput
                ) else {
                    finishValue(with: target)
                    return
                }
                return sampleCurrentAnimationValue(
                    value: &updateValue,
                    fallbackValue: fallbackValue
                )

            case let .animated(animation, effectiveTransaction, now):
                updateAnimatedTargetChange(
                    target: target,
                    currentOutput: previousOutput,
                    animation: animation,
                    transaction: effectiveTransaction,
                    time: now
                )
            }
        }

        guard helper.isAnimating else {
            return
        }
        sampleCurrentAnimationValue(
            value: &updateValue,
            fallbackValue: previousOutput
        )
    }

    private mutating func updateAnimatedTargetChange(
        target: AnimatedValue,
        currentOutput: AnimatedValue,
        animation: Animation,
        transaction effectiveTransaction: Transaction,
        time now: Time
    ) {
        let start = currentOutput
        guard start.animatableData != target.animatableData else {
            finishValue(with: target)
            return
        }
        let retargetState = helper.retargetStateSnapshot()
        let previousStart = startValue
        let previousStartTime = retargetState.beginTime
        let previousAnimation = retargetState.animation
        let previousGeneration = currentGeneration
        let replacementGeneration = nextGeneration
        nextGeneration += 1
        let previousPresentationSeed: AnimatorState<AnimatedValue>.RetargetPresentationSeed?
        if previousAnimation != nil,
           let previousStart,
           let previousTarget = targetValue,
           let previousGeneration {
            previousPresentationSeed = AnimatorState.RetargetPresentationSeed(
                startValue: previousStart,
                targetValue: previousTarget,
                startTime: previousStartTime,
                generation: previousGeneration
            )
        } else {
            previousPresentationSeed = nil
        }
        let mergedStart = retargetState.baseLayerStartValue ?? previousStart ?? start
        let mergedStartTime = retargetState.baseLayers.first?.startTime ?? previousStartTime
        let animatorStateNewInterval = targetValue.map {
            animatableDelta(from: $0, to: target)
        }
        let animatorStateLayerStack = !retargetState.baseLayers.isEmpty &&
            previousPresentationSeed != nil
            ? retargetState.baseLayers
            : nil
        let animatorStateLayerStackBase = retargetState.baseLayerStartValue
        let skipsVelocityTrackingPreviousMerge = shouldBypassVelocityTrackingPreviousMerge(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        )
        let combineResult: AnimatorState<AnimatedValue>.CombineResult
        if previousAnimation != nil,
           !skipsVelocityTrackingPreviousMerge,
           previousStart != nil,
           let animatorStateNewInterval {
            combineResult = helper.combine(
                newAnimation: animation,
                newInterval: animatorStateNewInterval,
                layerStack: animatorStateLayerStack,
                layerStackBase: animatorStateLayerStackBase,
                replacementTarget: target,
                presentationSeed: previousPresentationSeed,
                at: now,
                in: effectiveTransaction,
                environment: _environment
            )
        } else {
            if skipsVelocityTrackingPreviousMerge {
                helper.resetForFreshActivation()
            } else {
                helper.resetForReplacement()
            }
            combineResult = AnimatorState<AnimatedValue>.CombineResult(
                merged: false,
                layerStackConversion: nil,
                presentationLayer: nil
            )
        }
        let merged = combineResult.merged
        let previousLayer = combineResult.presentationLayer
        let activeRetargetState = helper.retargetStateSnapshot()
        let previousSamplingLayers = previousLayer.map { retargetState.baseLayers + [$0] } ?? []
        var activeAnimation = animation
        var activeStart = merged ? mergedStart : start
        var activeStartTime = merged ? mergedStartTime : now
        let usesCombinedAnimation = previousLayer != nil &&
            shouldUseCombinedAnimationForFalseRetarget(
                merged: merged,
                previousAnimation: previousAnimation,
                hasBaseLayers: !retargetState.baseLayers.isEmpty,
                hasLayerStackConversion: combineResult.layerStackConversion != nil
            )
        if usesCombinedAnimation,
           let previousAnimation,
           let previousStart {
            if let converted = combineResult.layerStackConversion {
                activeAnimation = converted.animation
                activeStart = converted.start
                activeStartTime = converted.startTime
            } else {
                activeAnimation = activeRetargetState.animation ?? previousAnimation
                activeStart = previousStart
                activeStartTime = previousStartTime
            }
        }
        if !previousSamplingLayers.isEmpty {
            samplingLayers.append(SideEffectSamplingLayer(layers: previousSamplingLayers))
        }
        if usesCombinedAnimation {
            helper.removeBaseLayers()
        } else if !merged,
           let previousLayer {
            helper.appendBaseLayer(previousLayer)
        } else {
            helper.removeBaseLayers()
        }
        let activeAnimationState = activeRetargetState.state
        let activeMergeState = activeRetargetState.mergeState
        var activeContextIsLogicallyComplete = activeRetargetState.isLogicallyComplete
        let activeUpdatesMergeStateWithAnimation =
            previousAnimation == nil || merged || skipsVelocityTrackingPreviousMerge
        let completionStart = now
        let deadlineStartValue = merged ? mergedStart : start
        let deadlineInterval = animatableDelta(from: deadlineStartValue, to: target)
        let presentationDuration = animation.box.presentationDuration(for: deadlineInterval)
        let deadline = completionStart + animation.box.duration
        velocityTrackingImmediateCompletionGroup = nil
        var holdsCombinedResidualReplacementLogicalUntilPresentation = false
        if !combineResult.finishesRetargetCompletionAtActivation,
           shouldFinishCombinedCompletionRecordsWithVelocityTrackingReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), customReplacementCompletionGroup != nil {
            let oldGenerations = customReplacementOldGenerations(
                from: previousSamplingLayers,
                previousGeneration: previousGeneration
            )
            velocityTrackingImmediateCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: oldGenerations
            )
            self.customReplacementCompletionGroup = nil
        } else if shouldFinishCombinedCompletionRecordsWithImmediateReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), customReplacementCompletionGroup != nil {
            customReplacementCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: customReplacementOldGenerations(
                    from: previousSamplingLayers,
                    previousGeneration: previousGeneration
                )
            )
        } else if shouldGroupCompletionRecordsForCustomToCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            customReplacementCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: customReplacementOldGenerations(
                    from: previousSamplingLayers,
                    previousGeneration: previousGeneration
                ),
                prefersReplacementLogicalBeforeRemoved: shouldFinishSourceCustomReplacementLogicalBeforeRemoved(
                    replacementAnimation: animation
                )
            )
        } else if shouldMoveCombinedCompletionRecordsToResidualReplacementFinalization(
            previousAnimation: previousAnimation,
            replacementAnimation: animation,
            presentationDuration: presentationDuration
        ), let customReplacementCompletionGroup {
            let oldGenerations = customReplacementCompletionGroup.oldGenerations
                .union([customReplacementCompletionGroup.replacementGeneration])
                .sorted()
            combinedResidualCompletionGroup = CombinedResidualCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: oldGenerations,
                prefersOldLogicalBeforeRemoved: shouldFinishCombinedResidualSourceLogicalBeforeRemoved(
                    replacementAnimation: animation
                ),
                prefersReplacementLogicalBeforeRemoved: shouldFinishCombinedResidualReplacementLogicalBeforeRemoved(
                    replacementAnimation: animation
                ),
                prefersReplacementLogicalBeforeSourceLogical: shouldFinishCombinedResidualReplacementLogicalBeforeSourceLogical(
                    replacementAnimation: animation
                )
            )
            for index in completionRecords.indices where oldGenerations.contains(completionRecords[index].orderGeneration) {
                completionRecords[index].deadline = .infinity
            }
            if shouldLetDeadlineOwnCombinedResidualReplacementLogical(
                replacementAnimation: animation,
                previousSamplingLayers: previousSamplingLayers,
                oldGenerations: oldGenerations,
                replacementLogicalDeadline: deadline
            ) {
                deadlineOwnedLogicalCompletionGenerations.insert(replacementGeneration)
                activeContextIsLogicallyComplete = false
            }
            if shouldHoldCombinedResidualReplacementLogicalUntilFinalization(
                replacementAnimation: animation,
                value: deadlineInterval
            ) {
                holdsCombinedResidualReplacementLogicalUntilPresentation = true
                activeContextIsLogicallyComplete = false
                contextLogicalCompletionSuppressedGenerations.insert(replacementGeneration)
            }
        } else if shouldMoveCombinedCompletionRecordsToFiniteReplacementFinalization(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let customReplacementCompletionGroup {
            let oldGenerations = customReplacementCompletionGroup.oldGenerations
                .union([customReplacementCompletionGroup.replacementGeneration])
            combinedFiniteCompletionGroup = CombinedFiniteCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: oldGenerations
            )
            self.customReplacementCompletionGroup = nil
        } else if shouldHoldSourceCustomCompletionRecordsUntilDefaultFinalization(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            contextLogicalCompletionSuppressedGenerations.insert(previousGeneration)
            contextLogicalCompletionSuppressedGenerations.insert(replacementGeneration)
        } else if shouldHoldRemovedCompletionRecordsForInfiniteReplacement(
            replacementAnimation: animation
        ) {
            let holdsPreviousRepeatGroup = shouldHoldFiniteRepeatCompletionRecordsAsGroupForInfiniteReplacement(
                previousAnimation: previousAnimation
            )
            for index in completionRecords.indices {
                let isPreviousGenerationRecord = previousGeneration.map {
                    completionRecords[index].orderGeneration == $0
                } ?? false
                if completionRecords[index].criteria == .removed ||
                   (holdsPreviousRepeatGroup && isPreviousGenerationRecord) {
                    completionRecords[index].deadline = deadline
                    completionRecords[index].generation = replacementGeneration
                }
            }
        } else if shouldMoveResidualWrapperCompletionRecordsToSourceCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = deadline
                }
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveFiniteDelaySpeedCompletionRecordsToSourceCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = deadline
                }
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveDefaultCompletionRecordsToSourceCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            contextLogicalCompletionSuppressedGenerations.insert(replacementGeneration)
            let previousPresentationDeadline = previousCompletionPresentationDeadline(
                previousAnimation: previousAnimation,
                previousStart: previousStart,
                previousTarget: targetValue,
                previousStartTime: previousStartTime,
                previousGeneration: previousGeneration
            )
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = deadline
                } else if completionRecords[index].deadline.seconds < previousPresentationDeadline.seconds {
                    completionRecords[index].deadline = previousPresentationDeadline
                }
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveBuiltInCompletionRecordsToSourceCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveSourceCustomCompletionRecordsToFiniteReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            let completionDeadline = completionStart + max(animation.box.duration, presentationDuration)
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = completionDeadline
                    completionRecords[index].generation = replacementGeneration
                } else if completionRecords[index].deadline.seconds > completionDeadline.seconds {
                    completionRecords[index].deadline = completionDeadline
                }
            }
        } else if merged,
           shouldMoveMergedCompletionRecordsToPresentation(
               previousAnimation: previousAnimation,
               replacementAnimation: animation,
               presentationDuration: presentationDuration
           ) {
            let presentationDeadline = completionStart + presentationDuration
            let movesPreviousRepeatGroup = shouldMoveFiniteRepeatCompletionRecordsAsGroupToPresentation(
                previousAnimation: previousAnimation
            )
            for index in completionRecords.indices {
                let isPreviousGenerationRecord = previousGeneration.map {
                    completionRecords[index].orderGeneration == $0
                } ?? false
                if completionRecords[index].criteria == .removed ||
                   completionRecords[index].deadline.seconds > presentationDeadline.seconds ||
                   (movesPreviousRepeatGroup &&
                    isPreviousGenerationRecord) {
                    completionRecords[index].deadline = presentationDeadline
                }
            }
        } else if shouldMoveResidualCompletionRecordsToPresentation(
            previousAnimation: previousAnimation,
            replacementAnimation: animation,
            presentationDuration: presentationDuration
        ) {
            let presentationDeadline = completionStart + presentationDuration
            let movesPreviousRepeatGroup = shouldMoveFiniteRepeatCompletionRecordsAsGroupToPresentation(
                previousAnimation: previousAnimation
            )
            for index in completionRecords.indices {
                let isPreviousGenerationRecord = previousGeneration.map {
                    completionRecords[index].orderGeneration == $0
                } ?? false
                if completionRecords[index].criteria == .removed ||
                   completionRecords[index].deadline.seconds > presentationDeadline.seconds ||
                   (movesPreviousRepeatGroup &&
                    isPreviousGenerationRecord) {
                    completionRecords[index].deadline = presentationDeadline
                }
            }
        } else if shouldMovePlainFiniteCompletionRecordsToReplacementBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            let removedOrderGenerations = Set(
                completionRecords
                    .filter { $0.criteria == .removed }
                    .map(\.orderGeneration)
            )
            for index in completionRecords.indices {
                if completionRecords[index].criteria == .removed ||
                   (completionRecords[index].deadline.seconds > deadline.seconds &&
                    removedOrderGenerations.contains(completionRecords[index].orderGeneration)) {
                    completionRecords[index].deadline = deadline
                    completionRecords[index].generation = replacementGeneration
                }
            }
        } else if shouldMoveCompletionRecordsToReplacementBoundary(
            merged: merged,
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            // Some merged replacements share one completion group.
            // Interrupted infinite or FluidSpring boxes also finalize at a
            // non-residual replacement boundary in the sampled handoff paths.
            for index in completionRecords.indices {
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldClampCompletionRecordsToEarlierReplacementBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            for index in completionRecords.indices where completionRecords[index].deadline.seconds > deadline.seconds {
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        }
        startValue = activeStart
        targetValue = target
        let activeInterval = animatableDelta(from: activeStart, to: target)
        let presentationDeadline = completionStart + max(animation.box.duration, presentationDuration)
        let holdsNewLogicalUntilPresentation =
            shouldHoldDefaultReplacementCompletionUntilPresentation(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            ) ||
            holdsCombinedResidualReplacementLogicalUntilPresentation ||
            contextLogicalCompletionSuppressedGenerations.contains(replacementGeneration)
        let completesWithoutWaitingForSamplingWindow = isVelocityTrackingAnimation(animation.box)
        let listenerRegistration = helper.activateAndAddListeners(
            animation: activeAnimation,
            interval: activeInterval,
            target: target,
            beginTime: activeStartTime,
            sampleTime: now,
            transaction: effectiveTransaction,
            state: activeAnimationState,
            mergeState: activeMergeState,
            isLogicallyComplete: activeContextIsLogicallyComplete,
            updatesMergeStateWithAnimation: activeUpdatesMergeStateWithAnimation
        )
        let newCompletionRecords = completionRecords(
            from: listenerRegistration.records,
            generation: replacementGeneration,
            orderGeneration: replacementGeneration
        ) { criteria in
            let waitsForPresentation = criteria == .removed || holdsNewLogicalUntilPresentation
            let registeredDeadline = animation.box.registeredCompletionDelay(for: criteria).map {
                completionStart + $0
            }
            return completesWithoutWaitingForSamplingWindow
                ? completionStart
                : registeredDeadline ?? (waitsForPresentation ? presentationDeadline : deadline)
        }
        completionRecords.insert(contentsOf: newCompletionRecords, at: 0)
        enqueueAnimationCompletionActions(listenerRegistration.immediateActions)
        currentGeneration = replacementGeneration
    }

    private func completionRecords(
        from listeners: [StateListener],
        generation: UInt64,
        orderGeneration: UInt64,
        deadline: (AnimationCompletionCriteria) -> Time
    ) -> [CompletionRecord] {
        listeners.map { listener in
            CompletionRecord(
                listener: listener,
                deadline: deadline(listener.criteria),
                generation: generation,
                orderGeneration: orderGeneration
            )
        }
    }

    private mutating func sampleCurrentAnimationValue(
        value updateValue: inout (value: AnimatedValue, changed: Bool),
        fallbackValue: AnimatedValue?
    ) {
        guard helper.isAnimating,
              let targetValue else {
            if let fallbackValue {
                finishValue(with: fallbackValue)
            }
            return
        }
        guard let update = helper.updateForCompletionRecords(
            value: &updateValue,
            environment: _environment,
            sampleCollector: { _, _ in }
        ) else {
            if let fallbackValue {
                finishValue(with: fallbackValue)
            }
            return
        }
        let now = update.time
        guard update.continues else {
            // Terminal samples let completion-record ordering own criteria
            // priority. Drained logical state tokens are still present in the
            // copied records, so finishing them here would reorder the boundary.
            if isCombinedFiniteCompletionGroupReplacement(currentGeneration) {
                AttributeGraph.setStatefulOutput(targetValue)
                let completions = finishCombinedFiniteCompletionGroup()
                enqueueAnimationCompletionActions(completions)
                return
            }
            if isCombinedResidualCompletionGroupReplacement(currentGeneration) {
                finishAnimation(
                    with: targetValue,
                    at: now,
                    discardedBaseLayerGenerations: update.discardedBaseLayerGenerations
                )
                return
            }
            if isCustomReplacementCompletionGroupReplacement(currentGeneration) {
                AttributeGraph.setStatefulOutput(targetValue)
                // The replacement nil boundary owns this handoff; discarded
                // side-effect layers should not be sampled again after it.
                let completions = finishCustomReplacementCompletionGroup(at: now)
                enqueueAnimationCompletionActions(completions)
                return
            }
            let listenerCompletions = finishCompletionRecords(
                matching: update.removedListeners + update.logicalListeners
            )
            enqueueAnimationCompletionActions(listenerCompletions)
            let completions = finishDueCompletionRecords(at: now)
            enqueueAnimationCompletionActions(completions)
            finishAnimation(
                with: targetValue,
                at: now,
                discardedBaseLayerGenerations: update.discardedBaseLayerGenerations
            )
            return
        }
        let output = updateValue.value
        if isCombinedFiniteCompletionGroupPresentationDue(at: now) {
            AttributeGraph.setStatefulOutput(targetValue)
            let completions = finishCombinedFiniteCompletionGroup()
            enqueueAnimationCompletionActions(completions)
            return
        }
        if sampleSideEffectLayers(at: now) {
            return
        }
        AttributeGraph.setStatefulOutput(output)
        if let velocityTrackingImmediateCompletionGroup {
            self.velocityTrackingImmediateCompletionGroup = nil
            samplingLayers.removeAll()
            let completions = finishCustomReplacementCompletionRecords(
                velocityTrackingImmediateCompletionGroup
            )
            enqueueAnimationCompletionActions(completions)
        }
        if update.isLogicallyComplete,
           let currentGeneration,
           !contextLogicalCompletionSuppressedGenerations.contains(currentGeneration),
           !deadlineOwnedLogicalCompletionGenerations.contains(currentGeneration) {
            let priorLogicalCompletions =
                finishCombinedResidualDueSourceLogicalBeforeReplacementLogicalIfNeeded(
                    for: currentGeneration,
                    at: now
                )
            let prefersSourceLogicalBeforeReplacement =
                prefersCombinedResidualSourceLogicalBeforeReplacementLogical(
                    for: currentGeneration
                )
            let logicalListeners = update.logicalListeners
            var completions = logicalListeners.isEmpty
                ? finishCompletionRecords(
                    for: currentGeneration,
                    matching: {
                        $0.criteria != .removed &&
                        $0.orderGeneration == currentGeneration
                    }
                )
                : finishCompletionRecords(
                    matching: logicalListeners,
                    preferLogicalBeforeRemoved: prefersSourceLogicalBeforeReplacement
                )
            completions.insert(contentsOf: priorLogicalCompletions, at: 0)
            enqueueAnimationCompletionActions(completions)
        }
        if isCombinedResidualCompletionGroupPresentationDue(at: now) {
            finishAnimation(with: targetValue, at: now)
            return
        }
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    mutating func destroy() {
        // Node removal is the last chance to finish listeners that were waiting
        // on this animatable value but no longer have a live output node.
        clearAnimationRuntimeState()
        let completions = finishAllCompletionRecords()
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func resetAnimationStateForPhaseChange() {
        startValue = nil
        targetValue = nil
        clearAnimationRuntimeState()
        nextGeneration = 1
        let completions = finishAllCompletionRecords()
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func continueAnimationAfterNoAnimationRetarget(
        to target: AnimatedValue,
        currentOutput: AnimatedValue
    ) -> AnimatedValue? {
        guard helper.isAnimating,
              let startValue,
              let previousTarget = targetValue else {
            return nil
        }

        let retargetDelta = animatableDelta(from: previousTarget, to: target)
        self.startValue = applying(delta: retargetDelta, to: startValue, target: target)
        let fallbackOutput = applying(delta: retargetDelta, to: currentOutput, target: target)
        targetValue = target
        if let adjustedStart = self.startValue {
            let interval = animatableDelta(from: adjustedStart, to: target)
            helper.retargetWithoutAnimation(to: target, interval: interval)
        } else {
            helper.commitTarget(target)
        }
        return fallbackOutput
    }

    private mutating func finishValue(with value: AnimatedValue) {
        startValue = nil
        targetValue = value
        helper.commitTarget(value)
        clearAnimationRuntimeState()
        AttributeGraph.setStatefulOutput(value)
        guard !completionRecords.isEmpty else { return }
        let now = helper.currentTime()
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishAnimation(
        with value: AnimatedValue,
        at now: Time,
        finishAllRecords: Bool = false,
        discardedBaseLayerGenerations: Set<UInt64> = []
    ) {
        startValue = nil
        targetValue = value
        helper.commitTarget(value)
        let discardedInfiniteGenerations = discardedInfiniteLayerGenerations()
            .union(discardedBaseLayerGenerations)
        let combinedResidualGroup = combinedResidualCompletionGroup
        let combinedFiniteGroup = combinedFiniteCompletionGroup
        clearAnimationRuntimeState(clearingGeneration: false)
        AttributeGraph.setStatefulOutput(value)
        var completions: [() -> Void]
        if finishAllRecords {
            completions = finishAllCompletionRecords()
        } else if let currentGeneration,
                  let combinedFiniteGroup,
                  combinedFiniteGroup.replacementGeneration == currentGeneration {
            completions = finishCombinedFiniteCompletionRecords(combinedFiniteGroup)
            completions.append(
                contentsOf: finishInfiniteCompletionRecords(
                    for: discardedInfiniteGenerations.subtracting([currentGeneration])
                )
            )
        } else if let currentGeneration,
                  let combinedResidualGroup,
                  combinedResidualGroup.replacementGeneration == currentGeneration {
            completions = finishCombinedResidualCompletionGroup(combinedResidualGroup)
            completions.append(
                contentsOf: finishInfiniteCompletionRecords(
                    for: discardedInfiniteGenerations.subtracting([currentGeneration])
                )
            )
        } else if let currentGeneration {
            completions = finishCompletionRecords(for: currentGeneration)
            completions.append(
                contentsOf: finishInfiniteCompletionRecords(
                    for: discardedInfiniteGenerations.subtracting([currentGeneration])
                )
            )
        } else {
            completions = finishDueCompletionRecords(at: now)
        }
        currentGeneration = nil
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishDueCompletionRecords(at now: Time) -> [() -> Void] {
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if record.deadline < now || record.deadline == now {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(readyRecords)
    }

    private mutating func finishAllCompletionRecords() -> [() -> Void] {
        let records = completionRecords
        completionRecords.removeAll()
        return finishRecords(records)
    }

    private mutating func finishCombinedResidualCompletionGroup(
        _ group: CombinedResidualCompletionGroup
    ) -> [() -> Void] {
        let oldGenerationSet = Set(group.oldGenerations)
        var oldRemovedRecords: [CompletionRecord] = []
        var replacementRemovedRecords: [CompletionRecord] = []
        var replacementOtherRecords: [CompletionRecord] = []
        var oldOtherRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []

        for record in completionRecords {
            if oldGenerationSet.contains(record.orderGeneration) {
                if record.criteria == .removed {
                    oldRemovedRecords.append(record)
                } else {
                    oldOtherRecords.append(record)
                }
            } else if record.generation == group.replacementGeneration {
                if record.criteria == .removed {
                    replacementRemovedRecords.append(record)
                } else {
                    replacementOtherRecords.append(record)
                }
            } else {
                pendingRecords.append(record)
            }
        }

        completionRecords = pendingRecords
        oldRemovedRecords.sort { $0.orderGeneration < $1.orderGeneration }
        oldOtherRecords.sort { $0.orderGeneration < $1.orderGeneration }
        let orderedRecords: [CompletionRecord]
        if group.prefersOldLogicalBeforeRemoved {
            orderedRecords = replacementOtherRecords +
                oldOtherRecords +
                oldRemovedRecords +
                replacementRemovedRecords
        } else if group.prefersReplacementLogicalBeforeRemoved && !replacementOtherRecords.isEmpty {
            orderedRecords = replacementOtherRecords +
                oldRemovedRecords +
                replacementRemovedRecords +
                oldOtherRecords
        } else if replacementOtherRecords.isEmpty {
            // If the replacement logical record drained earlier, residual
            // finalization only owns removed records plus remaining source
            // logical records.
            orderedRecords = oldRemovedRecords +
                replacementRemovedRecords +
                oldOtherRecords
        } else {
            // Same-boundary residual families drain removed records before
            // logical records at finalization.
            orderedRecords = oldRemovedRecords +
                replacementRemovedRecords +
                replacementOtherRecords +
                oldOtherRecords
        }
        return orderedRecords.flatMap { $0.finish() }
    }

    private mutating func finishCombinedFiniteCompletionGroup() -> [() -> Void] {
        guard let group = combinedFiniteCompletionGroup else {
            return []
        }
        let finalValue = targetValue
        startValue = nil
        if let finalValue {
            targetValue = finalValue
            helper.commitTarget(finalValue)
        }
        clearAnimationRuntimeState()

        return finishCombinedFiniteCompletionRecords(group)
    }

    private mutating func finishCombinedFiniteCompletionRecords(
        _ group: CombinedFiniteCompletionGroup
    ) -> [() -> Void] {
        var oldRemovedRecords: [CompletionRecord] = []
        var replacementRemovedRecords: [CompletionRecord] = []
        var replacementOtherRecords: [CompletionRecord] = []
        var oldOtherRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []

        for record in completionRecords {
            if group.oldGenerations.contains(record.orderGeneration) {
                if record.criteria == .removed {
                    oldRemovedRecords.append(record)
                } else {
                    oldOtherRecords.append(record)
                }
            } else if record.generation == group.replacementGeneration {
                if record.criteria == .removed {
                    replacementRemovedRecords.append(record)
                } else {
                    replacementOtherRecords.append(record)
                }
            } else {
                pendingRecords.append(record)
            }
        }

        completionRecords = pendingRecords
        oldRemovedRecords.sort { $0.orderGeneration < $1.orderGeneration }
        oldOtherRecords.sort { $0.orderGeneration < $1.orderGeneration }
        let orderedRecords = oldRemovedRecords +
            replacementRemovedRecords +
            replacementOtherRecords +
            oldOtherRecords
        return orderedRecords.flatMap { $0.finish() }
    }

    private mutating func finishCompletionRecords(
        for generation: UInt64,
        preferLogicalBeforeRemoved: Bool = false
    ) -> [() -> Void] {
        finishCompletionRecords(
            for: generation,
            preferLogicalBeforeRemoved: preferLogicalBeforeRemoved
        ) { _ in true }
    }

    private mutating func finishCompletionRecords(
        for generations: Set<UInt64>,
        matching predicate: (CompletionRecord) -> Bool = { _ in true }
    ) -> [() -> Void] {
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if generations.contains(record.generation), predicate(record) {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(readyRecords)
    }

    private mutating func finishCompletionRecords(
        matching listeners: [StateListener],
        preferLogicalBeforeRemoved: Bool = false
    ) -> [() -> Void] {
        guard !listeners.isEmpty else { return [] }
        let listenerIDs = Set(listeners.map(\.identity))
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if listenerIDs.contains(record.identity) {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(
            readyRecords,
            preferLogicalBeforeRemoved: preferLogicalBeforeRemoved
        )
    }

    private mutating func finishCompletionRecords(
        for generation: UInt64,
        preferLogicalBeforeRemoved: Bool = false,
        matching predicate: (CompletionRecord) -> Bool
    ) -> [() -> Void] {
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if record.generation == generation, predicate(record) {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(
            readyRecords,
            preferLogicalBeforeRemoved: preferLogicalBeforeRemoved
        )
    }

    private mutating func finishInfiniteCompletionRecords(for generations: Set<UInt64>) -> [() -> Void] {
        guard !generations.isEmpty else { return [] }

        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if generations.contains(record.generation), !record.deadline.seconds.isFinite {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(readyRecords)
    }

    private func finishRecords(
        _ records: [CompletionRecord],
        preferLogicalBeforeRemoved: Bool = false
    ) -> [() -> Void] {
        if preferLogicalBeforeRemoved {
            return records
                .sorted {
                    if ($0.criteria == .removed) != ($1.criteria == .removed) {
                        return $0.criteria != .removed
                    }
                    return $0.orderGeneration < $1.orderGeneration
                }
                .flatMap { $0.finish() }
        }
        let indexedRecords = records.enumerated()
        let removedRecords = indexedRecords
            .filter { $0.element.criteria == .removed }
            .sorted {
                if $0.element.orderGeneration != $1.element.orderGeneration {
                    return $0.element.orderGeneration < $1.element.orderGeneration
                }
                return $0.offset < $1.offset
            }
            .map { $0.element }
        let otherRecords = indexedRecords
            .filter { $0.element.criteria != .removed }
            .sorted {
                if $0.element.orderGeneration != $1.element.orderGeneration {
                    return $0.element.orderGeneration > $1.element.orderGeneration
                }
                return $0.offset < $1.offset
            }
            .map { $0.element }
        return (removedRecords + otherRecords).flatMap { $0.finish() }
    }

    private func discardedInfiniteLayerGenerations() -> Set<UInt64> {
        var generations = helper.baseLayerGenerations()
        guard !generations.isEmpty || !samplingLayers.isEmpty else {
            return []
        }

        for samplingLayer in samplingLayers {
            for layer in samplingLayer.layers {
                generations.insert(layer.generation)
            }
        }
        return generations
    }

    private func interpolatedValue(at time: Time) -> AnimatedValue? {
        let defaultFinishingDefinition =
            AnimatedValue.self as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type
        let state = helper.interpolationStateSnapshot(
            defaultFinishingDefinition: defaultFinishingDefinition
        )
        guard let animation = state.animation,
              let startValue,
              let targetValue else {
            return AttributeGraph.currentStatefulOutput()
        }
        let elapsed = max(time.seconds - state.beginTime.seconds, 0)
        var context = makeAnimationContext(
            state: state.state,
            isLogicallyComplete: state.isLogicallyComplete,
            environment: _environment.value,
            finishingDefinition: state.finishingDefinition
        )
        guard let animatedDelta = animation.box.animate(
            value: animatableDelta(from: startValue, to: targetValue),
            time: elapsed,
            context: &context
        ) else {
            return targetValue
        }
        return applying(
            delta: animatedDelta,
            to: startValue,
            target: targetValue
        )
    }

    private mutating func sampleSideEffectLayers(at now: Time) -> Bool {
        guard !samplingLayers.isEmpty else { return false }

        let sampledLayers = samplingLayers
        var remainingLayers: [SideEffectSamplingLayer] = []
        remainingLayers.reserveCapacity(sampledLayers.count)
        for samplingLayer in sampledLayers {
            let result = sampleSideEffectSamplingLayer(samplingLayer, at: now)
            if result.didFinishCurrentAnimation {
                samplingLayers.removeAll()
                return true
            }
            if !result.isComplete {
                remainingLayers.append(samplingLayer)
            }
        }
        samplingLayers = remainingLayers
        return false
    }

    private mutating func sampleSideEffectSamplingLayer(
        _ samplingLayer: SideEffectSamplingLayer,
        at now: Time
    ) -> SideEffectSamplingResult {
        guard !samplingLayer.layers.isEmpty else {
            return SideEffectSamplingResult(isComplete: true, didFinishCurrentAnimation: false)
        }

        var baseValue = samplingLayer.layers[0].startValue
        var didReachLastLayer = false
        for index in samplingLayer.layers.indices {
            let layer = samplingLayer.layers[index]
            let elapsed = max(now.seconds - layer.startTime.seconds, 0)
            var context = makeAnimationContext(
                state: layer.state,
                isLogicallyComplete: layer.contextIsLogicallyComplete,
                environment: _environment.value,
                finishingDefinition: layer.finishingDefinition
            )
            let animatedDelta = layer.animation.box.animate(
                value: animatableDelta(from: baseValue, to: layer.targetValue),
                time: elapsed,
                context: &context
            )
            if context.isLogicallyComplete {
                if !contextLogicalCompletionSuppressedGenerations.contains(layer.generation) {
                    var completions = finishCombinedResidualReplacementLogicalBeforeSourceLogicalIfNeeded(
                        for: layer.generation
                    )
                    completions.append(
                        contentsOf: finishCompletionRecords(for: layer.generation) {
                            $0.criteria != .removed
                        }
                    )
                    enqueueAnimationCompletionActions(completions)
                }
            }
            if let animatedDelta {
                baseValue = applying(
                    delta: animatedDelta,
                    to: baseValue,
                    target: layer.targetValue
                )
            } else {
                baseValue = layer.targetValue
                if index == samplingLayer.layers.indices.last {
                    didReachLastLayer = true
                    if isCurrentCustomReplacementNilBoundary(layer.generation) {
                        let completions = finishCustomReplacementCompletionGroup(at: now)
                        enqueueAnimationCompletionActions(completions)
                        return SideEffectSamplingResult(
                            isComplete: true,
                            didFinishCurrentAnimation: true
                        )
                    }
                }
                if isDeferredCompletionGroupOldGeneration(layer.generation) {
                    var completions = finishCombinedResidualReplacementLogicalBeforeSourceLogicalIfNeeded(
                        for: layer.generation
                    )
                    completions.append(
                        contentsOf: finishCompletionRecords(for: layer.generation) {
                            $0.criteria != .removed
                        }
                    )
                    enqueueAnimationCompletionActions(completions)
                    continue
                }
                let completions = finishCompletionRecords(for: layer.generation)
                enqueueAnimationCompletionActions(completions)
            }
        }
        return SideEffectSamplingResult(
            isComplete: didReachLastLayer,
            didFinishCurrentAnimation: false
        )
    }

    private func isCustomReplacementCompletionGroupReplacement(_ generation: UInt64?) -> Bool {
        guard let generation,
              let group = customReplacementCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
    }

    private func isCurrentCustomReplacementNilBoundary(_ generation: UInt64) -> Bool {
        guard isCustomReplacementCompletionGroupReplacement(generation) else {
            return false
        }
        return isCustomReplacementCompletionGroupReplacement(currentGeneration)
    }

    private func isCombinedFiniteCompletionGroupReplacement(_ generation: UInt64?) -> Bool {
        guard let generation,
              let group = combinedFiniteCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
    }

    private func isCombinedResidualCompletionGroupReplacement(_ generation: UInt64?) -> Bool {
        guard let generation,
              let group = combinedResidualCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
    }

    private func isCombinedFiniteCompletionGroupPresentationDue(at now: Time) -> Bool {
        guard let group = combinedFiniteCompletionGroup else {
            return false
        }
        return completionRecords.contains {
            $0.generation == group.replacementGeneration &&
            $0.criteria == .removed &&
            ($0.deadline < now || $0.deadline == now)
        }
    }

    private func isCombinedResidualCompletionGroupPresentationDue(at now: Time) -> Bool {
        guard let group = combinedResidualCompletionGroup else {
            return false
        }
        return completionRecords.contains {
            $0.generation == group.replacementGeneration &&
            $0.criteria == .removed &&
            ($0.deadline < now || $0.deadline == now)
        }
    }

    private func isCustomReplacementCompletionGroupOldGeneration(_ generation: UInt64) -> Bool {
        customReplacementCompletionGroup?.oldGenerations.contains(generation) ?? false
    }

    private func isDeferredCompletionGroupOldGeneration(_ generation: UInt64) -> Bool {
        isCustomReplacementCompletionGroupOldGeneration(generation) ||
            (combinedFiniteCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (combinedResidualCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (velocityTrackingImmediateCompletionGroup?.oldGenerations.contains(generation) ?? false)
    }

    private mutating func finishCombinedResidualReplacementLogicalBeforeSourceLogicalIfNeeded(
        for generation: UInt64
    ) -> [() -> Void] {
        guard let group = combinedResidualCompletionGroup,
              group.prefersReplacementLogicalBeforeSourceLogical,
              group.oldGenerations.contains(generation) else {
            return []
        }
        return finishCompletionRecords(for: group.replacementGeneration) {
            $0.criteria != .removed &&
                $0.orderGeneration == group.replacementGeneration
        }
    }

    private mutating func finishCombinedResidualDueSourceLogicalBeforeReplacementLogicalIfNeeded(
        for generation: UInt64,
        at now: Time
    ) -> [() -> Void] {
        guard let group = combinedResidualCompletionGroup,
              group.replacementGeneration == generation,
              !group.prefersReplacementLogicalBeforeSourceLogical else {
            return []
        }
        let oldGenerationSet = Set(group.oldGenerations)
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if oldGenerationSet.contains(record.orderGeneration),
               record.criteria != .removed,
               (record.deadline < now || record.deadline == now) {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return finishRecords(readyRecords, preferLogicalBeforeRemoved: true)
    }

    private func prefersCombinedResidualSourceLogicalBeforeReplacementLogical(
        for generation: UInt64
    ) -> Bool {
        guard let group = combinedResidualCompletionGroup,
              group.replacementGeneration == generation else {
            return false
        }
        return !group.prefersReplacementLogicalBeforeSourceLogical
    }

    private mutating func finishCustomReplacementCompletionGroup(at now: Time) -> [() -> Void] {
        guard let group = customReplacementCompletionGroup else {
            return []
        }
        let finalValue = targetValue
        startValue = nil
        if let finalValue {
            targetValue = finalValue
            helper.commitTarget(finalValue)
            AttributeGraph.setStatefulOutput(finalValue)
        }
        clearAnimationRuntimeState()

        return finishCustomReplacementCompletionRecords(group)
    }

    private mutating func finishCustomReplacementCompletionRecords(
        _ group: CustomReplacementCompletionGroup
    ) -> [() -> Void] {
        var oldRemovedRecords: [CompletionRecord] = []
        var replacementRemovedRecords: [CompletionRecord] = []
        var replacementOtherRecords: [CompletionRecord] = []
        var oldOtherRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []

        for record in completionRecords {
            if group.oldGenerations.contains(record.orderGeneration) {
                if record.criteria == .removed {
                    oldRemovedRecords.append(record)
                } else {
                    oldOtherRecords.append(record)
                }
            } else if record.generation == group.replacementGeneration {
                if record.criteria == .removed {
                    replacementRemovedRecords.append(record)
                } else {
                    replacementOtherRecords.append(record)
                }
            } else {
                pendingRecords.append(record)
            }
        }

        completionRecords = pendingRecords
        oldRemovedRecords.sort { $0.orderGeneration < $1.orderGeneration }
        oldOtherRecords.sort { $0.orderGeneration < $1.orderGeneration }
        let pendingOldLogicalGenerations = Set(oldOtherRecords.map(\.orderGeneration))
        let ownsAllOldLogicalRecords = group.oldGenerations.isSubset(
            of: pendingOldLogicalGenerations
        )
        let orderedRecords: [CompletionRecord]
        if group.prefersReplacementLogicalBeforeRemoved &&
            ownsAllOldLogicalRecords &&
            !replacementOtherRecords.isEmpty {
            orderedRecords = replacementOtherRecords +
                oldRemovedRecords +
                replacementRemovedRecords +
                oldOtherRecords
        } else {
            orderedRecords = oldRemovedRecords +
                replacementRemovedRecords +
                replacementOtherRecords +
                oldOtherRecords
        }
        return orderedRecords.flatMap { $0.finish() }
    }

    private func animatableDelta(
        from start: AnimatedValue,
        to target: AnimatedValue
    ) -> AnimatedValue.AnimatableData {
        var data = target.animatableData
        data -= start.animatableData
        return data
    }

    private func applying(
        delta: AnimatedValue.AnimatableData,
        to start: AnimatedValue,
        target: AnimatedValue
    ) -> AnimatedValue {
        var data = start.animatableData
        data += delta

        var output = target
        output.animatableData = data
        return output
    }

    private func shouldMoveMergedCompletionRecordsToPresentation(
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        presentationDuration: TimeInterval
    ) -> Bool {
        guard presentationDuration > replacementAnimation.box.duration else {
            return false
        }
        guard let previousAnimation else { return false }
        if previousAnimation.box is SpringAnimationBox {
            return replacementAnimation.box is DefaultAnimationBox ||
                replacementAnimation.box is FluidSpringAnimationBox
        }
        return !previousAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func shouldHoldRemovedCompletionRecordsForInfiniteReplacement(
        replacementAnimation: Animation
    ) -> Bool {
        !replacementAnimation.box.duration.isFinite &&
            !replacementAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func shouldGroupCompletionRecordsForCustomToCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isSourceDefinedCustomAnimation(previousAnimation.box) &&
            isSourceDefinedCustomAnimation(replacementAnimation.box)
    }

    private func shouldFinishCombinedCompletionRecordsWithVelocityTrackingReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isDefaultCombiningAnimation(previousAnimation.box) &&
            isVelocityTrackingAnimation(replacementAnimation.box)
    }

    private func shouldFinishCombinedCompletionRecordsWithImmediateReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isDefaultCombiningAnimation(previousAnimation.box) &&
            replacementAnimation.box.finishesRetargetCompletionAtActivation
    }

    private func shouldBypassVelocityTrackingPreviousMerge(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isVelocityTrackingAnimation(previousAnimation.box) &&
            isSourceCustomReplacementAnimation(replacementAnimation.box)
    }

    private func shouldUseCombinedAnimationForFalseRetarget(
        merged: Bool,
        previousAnimation: Animation?,
        hasBaseLayers: Bool,
        hasLayerStackConversion: Bool
    ) -> Bool {
        !merged &&
            previousAnimation != nil &&
            (!hasBaseLayers || hasLayerStackConversion)
    }

    private func customReplacementOldGenerations(
        from previousSamplingLayers: [AnimationLayer],
        previousGeneration: UInt64?
    ) -> Set<UInt64> {
        var generations = Set(previousSamplingLayers.map(\.generation))
        if let previousGeneration {
            for record in completionRecords where record.generation == previousGeneration {
                generations.insert(record.orderGeneration)
            }
        }
        if let group = customReplacementCompletionGroup {
            generations.formUnion(group.oldGenerations)
            generations.insert(group.replacementGeneration)
        }
        return generations
    }

    private func shouldHoldSourceCustomCompletionRecordsUntilDefaultFinalization(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isSourceDefinedCustomAnimation(previousAnimation.box) &&
            !isDefaultCombiningAnimation(previousAnimation.box) &&
            replacementAnimation.box is DefaultAnimationBox
    }

    private func shouldHoldDefaultReplacementCompletionUntilPresentation(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        shouldHoldSourceCustomCompletionRecordsUntilDefaultFinalization(
            previousAnimation: previousAnimation,
            replacementAnimation: replacementAnimation
        )
    }

    private func isVelocityTrackingAnimation(_ box: AnimationBoxBase) -> Bool {
        isVelocityTrackingAnimationBox(box)
    }

    private func shouldMoveBuiltInCompletionRecordsToSourceCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return previousAnimation.box.duration.isFinite &&
            !previousAnimation.box.preservesRetargetedCompletionDeadlines &&
            !replacementAnimation.box.duration.isFinite &&
            replacementAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func shouldMoveDefaultCompletionRecordsToSourceCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return previousAnimation.box is DefaultAnimationBox &&
            !replacementAnimation.box.duration.isFinite &&
            replacementAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func previousCompletionPresentationDeadline(
        previousAnimation: Animation?,
        previousStart: AnimatedValue?,
        previousTarget: AnimatedValue?,
        previousStartTime: Time,
        previousGeneration: UInt64
    ) -> Time {
        if let removedDeadline = completionRecords
            .filter({
                $0.orderGeneration == previousGeneration &&
                $0.criteria == .removed
            })
            .map(\.deadline)
            .min(by: { $0.seconds < $1.seconds }) {
            return removedDeadline
        }
        guard let previousAnimation,
              let previousStart,
              let previousTarget else {
            return previousStartTime
        }
        let previousDuration = previousAnimation.box.presentationDuration(
            for: animatableDelta(from: previousStart, to: previousTarget)
        )
        return previousStartTime + previousDuration
    }

    private func shouldMoveSourceCustomCompletionRecordsToFiniteReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return previousAnimation.box.preservesRetargetedCompletionDeadlines &&
            !previousAnimation.box.duration.isFinite &&
            replacementAnimation.box.duration.isFinite
    }

    private func shouldMoveCombinedCompletionRecordsToResidualReplacementFinalization(
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        presentationDuration: TimeInterval
    ) -> Bool {
        guard let previousAnimation else { return false }
        let hasCombinedCustomPrevious =
            isDefaultCombiningAnimation(previousAnimation.box) ||
            (isSourceDefinedCustomAnimation(previousAnimation.box) &&
             replacementAnimation.box is FluidSpringAnimationBox)
        return hasCombinedCustomPrevious &&
            (
                replacementAnimation.box is DefaultAnimationBox ||
                presentationDuration > replacementAnimation.box.duration ||
                replacementAnimation.box.presentationDuration > replacementAnimation.box.duration
            )
    }

    private func shouldHoldCombinedResidualReplacementLogicalUntilFinalization(
        replacementAnimation: Animation,
        value: AnimatedValue.AnimatableData
    ) -> Bool {
        guard let fluidSpring = replacementAnimation.box as? FluidSpringAnimationBox else {
            return false
        }
        return fluidSpring.reachesTargetAtLogicalDuration(for: value)
    }

    private func shouldLetDeadlineOwnCombinedResidualReplacementLogical(
        replacementAnimation: Animation,
        previousSamplingLayers: [AnimationLayer],
        oldGenerations: [UInt64],
        replacementLogicalDeadline: Time
    ) -> Bool {
        if isCombinedResidualReplacementLogicalBeforeSourceWrapper(replacementAnimation.box) {
            return true
        }
        guard replacementAnimation.box is DefaultAnimationBox ||
              replacementAnimation.box is FluidSpringAnimationBox else {
            return false
        }
        let oldGenerationSet = Set(oldGenerations)
        return previousSamplingLayers.contains { layer in
            guard oldGenerationSet.contains(layer.generation) else {
                return false
            }
            if let combinedBox = layer.animation.box as? CustomAnimationBox<DefaultCombiningAnimation> {
                return combinedBox.base.entries.contains { entry in
                    isLayerTerminalDeadline(
                        layer.startTime + entry.elapsed,
                        entry.animation,
                        dueBy: replacementLogicalDeadline
                    )
                }
            }
            return isLayerTerminalDeadline(
                layer.startTime,
                layer.animation,
                dueBy: replacementLogicalDeadline
            )
        }
    }

    private func isNonInteractiveFluidSpringResidualLogicalDeadlineWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let delay = box as? DelayAnimationBox {
            guard delay.delay >= 0 else { return false }
            return isNonInteractiveFluidSpringAlias(delay.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            guard repeatBox.repeatCount != nil else { return false }
            return isNonInteractiveFluidSpringAlias(repeatBox.base)
        }
        return false
    }

    private func isNonInteractiveFluidSpringAlias(_ box: AnimationBoxBase) -> Bool {
        guard let fluidSpring = box as? FluidSpringAnimationBox else {
            return false
        }
        return !isInteractiveFluidSpringAlias(fluidSpring)
    }

    private func isLayerTerminalDeadline(
        _ startTime: Time,
        _ animation: Animation,
        dueBy deadline: Time
    ) -> Bool {
        guard let terminalDelay = animation.box.noRegisteredCompletionDelay() else {
            return false
        }
        let terminalTime = startTime + terminalDelay
        return terminalTime < deadline || terminalTime == deadline
    }

    private func shouldFinishCombinedResidualSourceLogicalBeforeRemoved(
        replacementAnimation: Animation
    ) -> Bool {
        isCombinedResidualOldSourceLogicalBeforeRemovedWrapper(replacementAnimation.box)
    }

    private func shouldFinishCombinedResidualReplacementLogicalBeforeRemoved(
        replacementAnimation: Animation
    ) -> Bool {
        hasSpringAnimationBase(replacementAnimation.box) ||
            shouldFinishDirectFluidSpringReplacementLogicalBeforeRemoved(replacementAnimation.box) ||
            isSpringPropertyFluidSpringAlias(replacementAnimation.box) ||
            hasResidualWrapperPresentation(replacementAnimation.box)
    }

    private func shouldFinishDirectFluidSpringReplacementLogicalBeforeRemoved(
        _ box: AnimationBoxBase
    ) -> Bool {
        guard let fluidSpring = box as? FluidSpringAnimationBox else {
            return false
        }
        return !isSampledDurationBounceFluidSpringSameBoundaryAlias(fluidSpring)
    }

    private func isSampledDurationBounceFluidSpringSameBoundaryAlias(
        _ box: FluidSpringAnimationBox
    ) -> Bool {
        approximatelyEqual(box.response, 0.5) &&
            approximatelyEqual(box.dampingFraction, 0.8) &&
            approximatelyEqual(box.blendDuration, 0)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 1.0e-9
    }

    private func shouldFinishCombinedResidualReplacementLogicalBeforeSourceLogical(
        replacementAnimation: Animation
    ) -> Bool {
        isCombinedResidualReplacementLogicalBeforeSourceWrapper(replacementAnimation.box)
    }

    private func isCombinedResidualOldSourceLogicalBeforeRemovedWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        guard hasResidualWrapperPresentation(box) else {
            return false
        }
        if isFluidSpringNestedSpeedRepeatResidualWrapper(box) {
            return false
        }
        return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(box)
    }

    private func hasCombinedResidualOldSourceLogicalBeforeRemovedBase(
        _ box: AnimationBoxBase
    ) -> Bool {
        if box is DefaultAnimationBox {
            return true
        }
        if let fluidSpring = box as? FluidSpringAnimationBox {
            return !isInteractiveFluidSpringAlias(fluidSpring)
        }
        if let delay = box as? DelayAnimationBox {
            guard delay.delay >= 0 else { return false }
            return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            guard speed.speed > 0 else { return false }
            return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasCombinedResidualOldSourceLogicalBeforeRemovedRepeatBase(repeatBox)
        }
        return false
    }

    private func hasCombinedResidualOldSourceLogicalBeforeRemovedRepeatBase(
        _ repeatBox: RepeatAnimationBox
    ) -> Bool {
        guard let repeatCount = repeatBox.repeatCount else {
            return false
        }
        if repeatBox.base is DefaultAnimationBox {
            return true
        }
        if let fluidSpring = repeatBox.base as? FluidSpringAnimationBox {
            return repeatCount >= 0 && !isInteractiveFluidSpringAlias(fluidSpring)
        }
        return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(repeatBox.base)
    }

    private func isFluidSpringNestedSpeedRepeatResidualWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let repeatBox = box as? RepeatAnimationBox,
           repeatBox.repeatCount != nil,
           let speed = repeatBox.base as? SpeedAnimationBox,
           speed.speed > 0 {
            return isNonInteractiveFluidSpringAlias(speed.base)
        }
        if let speed = box as? SpeedAnimationBox,
           speed.speed > 0,
           let repeatBox = speed.base as? RepeatAnimationBox,
           repeatBox.repeatCount != nil {
            return isNonInteractiveFluidSpringAlias(repeatBox.base)
        }
        return false
    }

    private func isCombinedResidualReplacementLogicalBeforeSourceWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        guard hasResidualWrapperPresentation(box) else {
            return false
        }
        if isNonInteractiveFluidSpringResidualLogicalDeadlineWrapper(box) {
            return true
        }
        if let delay = box as? DelayAnimationBox {
            guard delay.delay == 0 else { return false }
            return hasDefaultAnimationBase(delay.base) ||
                isNonInteractiveFluidSpringAlias(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            guard speed.speed > 0 else { return false }
            return hasDefaultAnimationBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasDefaultAnimationBase(repeatBox.base) ||
                hasCombinedResidualOldSourceLogicalBeforeRemovedRepeatBase(repeatBox)
        }
        return false
    }

    private func hasDefaultAnimationBase(_ box: AnimationBoxBase) -> Bool {
        if box is DefaultAnimationBox {
            return true
        }
        if let delay = box as? DelayAnimationBox {
            return hasDefaultAnimationBase(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            return hasDefaultAnimationBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasDefaultAnimationBase(repeatBox.base)
        }
        return false
    }

    private func isSpringPropertyFluidSpringAlias(_ box: AnimationBoxBase) -> Bool {
        guard let fluidSpring = box as? FluidSpringAnimationBox else {
            return false
        }
        return fluidSpring.response == 0.5 &&
            fluidSpring.dampingFraction == 1 &&
            fluidSpring.blendDuration == 0
    }

    private func isInteractiveFluidSpringAlias(_ box: FluidSpringAnimationBox) -> Bool {
        box.blendDuration > 0
    }

    private func shouldFinishSourceCustomReplacementLogicalBeforeRemoved(
        replacementAnimation: Animation
    ) -> Bool {
        isSourceCustomReplacementWrapper(replacementAnimation.box)
    }

    private func isSourceCustomReplacementWrapper(_ box: AnimationBoxBase) -> Bool {
        if let delay = box as? DelayAnimationBox {
            return hasSourceCustomReplacementBase(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            return hasSourceCustomReplacementBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasSourceCustomReplacementBase(repeatBox.base)
        }
        return false
    }

    private func hasSourceCustomReplacementBase(_ box: AnimationBoxBase) -> Bool {
        if isSourceCustomReplacementAnimation(box) {
            return true
        }
        if let delay = box as? DelayAnimationBox {
            return hasSourceCustomReplacementBase(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            return hasSourceCustomReplacementBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasSourceCustomReplacementBase(repeatBox.base)
        }
        return false
    }

    private func hasSpringAnimationBase(_ box: AnimationBoxBase) -> Bool {
        if box is SpringAnimationBox {
            return true
        }
        if let delay = box as? DelayAnimationBox {
            return hasSpringAnimationBase(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            return hasSpringAnimationBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasSpringAnimationBase(repeatBox.base)
        }
        return false
    }

    private func shouldMoveCombinedCompletionRecordsToFiniteReplacementFinalization(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isDefaultCombiningAnimation(previousAnimation.box) &&
            isFiniteNonResidualAnimation(replacementAnimation.box)
    }

    private func shouldMoveResidualWrapperCompletionRecordsToSourceCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return hasResidualWrapperPresentation(previousAnimation.box) &&
            !replacementAnimation.box.duration.isFinite &&
            replacementAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func shouldMoveFiniteDelaySpeedCompletionRecordsToSourceCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isFiniteNonResidualDelayOrSpeed(previousAnimation.box) &&
            !replacementAnimation.box.duration.isFinite &&
            replacementAnimation.box.preservesRetargetedCompletionDeadlines
    }

    private func shouldMoveResidualCompletionRecordsToPresentation(
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        presentationDuration: TimeInterval
    ) -> Bool {
        guard presentationDuration > replacementAnimation.box.duration else {
            return false
        }
        guard let previousAnimation else { return false }
        if previousAnimation.box is SpringAnimationBox {
            return replacementAnimation.box is SpringAnimationBox
        }
        if previousAnimation.box is DefaultAnimationBox {
            return replacementAnimation.box is SpringAnimationBox
        }
        if previousAnimation.box is FluidSpringAnimationBox {
            return replacementAnimation.box is SpringAnimationBox
        }
        if hasResidualWrapperPresentation(replacementAnimation.box) {
            return previousAnimation.box is SpringAnimationBox ||
                previousAnimation.box is DefaultAnimationBox ||
                previousAnimation.box is FluidSpringAnimationBox ||
                hasResidualWrapperPresentation(previousAnimation.box) ||
                isFiniteNonResidualAnimation(previousAnimation.box)
        }
        if !previousAnimation.box.duration.isFinite &&
           !previousAnimation.box.preservesRetargetedCompletionDeadlines {
            return true
        }
        if hasResidualWrapperPresentation(previousAnimation.box) {
            return true
        }
        if isFiniteNonResidualAnimation(previousAnimation.box) {
            return true
        }
        return false
    }

    private func shouldMovePlainFiniteCompletionRecordsToReplacementBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isPlainFiniteNonResidualAnimation(previousAnimation.box) &&
            isPlainFiniteNonResidualAnimation(replacementAnimation.box)
    }

    private func shouldMoveCompletionRecordsToReplacementBoundary(
        merged: Bool,
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        if merged {
            return !(previousAnimation.box is SpringAnimationBox)
        }
        guard !previousAnimation.box.preservesRetargetedCompletionDeadlines else {
            return false
        }
        if !previousAnimation.box.duration.isFinite {
            return true
        }
        if isFiniteNonResidualAnimation(replacementAnimation.box) {
            if isFiniteNonResidualWrapper(previousAnimation.box) {
                return true
            }
            if isFiniteNonResidualWrapper(replacementAnimation.box),
               isFiniteNonResidualAnimation(previousAnimation.box) {
                return true
            }
        }
        if previousAnimation.box is FluidSpringAnimationBox,
           replacementAnimation.box.presentationDuration == replacementAnimation.box.duration {
            return true
        }
        return false
    }

    private func shouldClampCompletionRecordsToEarlierReplacementBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        guard replacementAnimation.box.presentationDuration == replacementAnimation.box.duration else {
            return false
        }
        return previousAnimation.box is SpringAnimationBox ||
            previousAnimation.box is DefaultAnimationBox ||
            hasResidualWrapperPresentation(previousAnimation.box)
    }

    private func hasResidualWrapperPresentation(_ box: AnimationBoxBase) -> Bool {
        guard box is DelayAnimationBox ||
              box is SpeedAnimationBox ||
              box is RepeatAnimationBox else {
            return false
        }
        return box.presentationDuration > box.duration
    }

    private func isFiniteNonResidualWrapper(_ box: AnimationBoxBase) -> Bool {
        guard box is DelayAnimationBox ||
              box is SpeedAnimationBox ||
              box is RepeatAnimationBox else {
            return false
        }
        return box.duration.isFinite &&
            box.presentationDuration == box.duration
    }

    private func isFiniteNonResidualDelayOrSpeed(_ box: AnimationBoxBase) -> Bool {
        guard box is DelayAnimationBox || box is SpeedAnimationBox else {
            return false
        }
        return box.duration.isFinite &&
            box.presentationDuration == box.duration
    }

    private func shouldMoveFiniteRepeatCompletionRecordsAsGroupToPresentation(
        previousAnimation: Animation?
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isFiniteNonResidualRepeat(previousAnimation.box)
    }

    private func shouldHoldFiniteRepeatCompletionRecordsAsGroupForInfiniteReplacement(
        previousAnimation: Animation?
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isFiniteNonResidualRepeat(previousAnimation.box)
    }

    private func isFiniteNonResidualRepeat(_ box: AnimationBoxBase) -> Bool {
        guard box is RepeatAnimationBox else {
            return false
        }
        return box.duration.isFinite &&
            box.presentationDuration == box.duration
    }

    private func isFiniteNonResidualAnimation(_ box: AnimationBoxBase) -> Bool {
        box.duration.isFinite &&
            !box.preservesRetargetedCompletionDeadlines &&
            box.presentationDuration == box.duration
    }

    private func isPlainFiniteNonResidualAnimation(_ box: AnimationBoxBase) -> Bool {
        isFiniteNonResidualAnimation(box) && !isFiniteNonResidualWrapper(box)
    }

    private func isSourceDefinedCustomAnimation(_ box: AnimationBoxBase) -> Bool {
        isSourceDefinedCustomAnimationBox(box)
    }

    private func isSourceCustomReplacementAnimation(_ box: AnimationBoxBase) -> Bool {
        isSourceCustomReplacementAnimationBox(box)
    }

    private func isDefaultCombiningAnimation(_ box: AnimationBoxBase) -> Bool {
        isDefaultCombiningAnimationBox(box)
    }

}

struct AnimatedFrameAttributes {
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var frame: Attribute<ViewFrame>
}

private struct FrameVelocityFilter {
    var currentVelocity: Double?
    var previous: (time: Time, data: ViewFrame.AnimatableData)?

    mutating func addSample(
        _ data: ViewFrame.AnimatableData,
        time: Time
    ) {
        defer {
            previous = (time, data)
        }

        guard let previous, previous.time < time else {
            return
        }

        let elapsed = time.seconds - previous.time.seconds
        guard elapsed > 0 else { return }

        let observed = maxAbsVelocity(
            from: previous.data,
            to: data,
            elapsed: elapsed
        )
        if let currentVelocity {
            self.currentVelocity = currentVelocity + ((observed - currentVelocity) * 0.35)
        } else {
            self.currentVelocity = observed
        }
    }

    mutating func reset() {
        currentVelocity = nil
        previous = nil
    }

    private func maxAbsVelocity(
        from previous: ViewFrame.AnimatableData,
        to current: ViewFrame.AnimatableData,
        elapsed: Double
    ) -> Double {
        let reciprocal = 1.0 / elapsed
        let components = [
            Double(current.first.first - previous.first.first),
            Double(current.first.second - previous.first.second),
            Double(current.second.first - previous.second.first),
            Double(current.second.second - previous.second.second),
        ]
        return components.reduce(0) { partial, component in
            max(partial, abs(component * reciprocal))
        }
    }
}

private struct AnimatableFrameAttribute: StatefulRule {
    typealias Value = ViewFrame

    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _pixelLength: Attribute<CGFloat>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<ViewFrame>
    var animationsDisabled: Bool

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool
    ) {
        self._position = position
        self._size = size
        self._pixelLength = pixelLength
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
        self.animationsDisabled = animationsDisabled
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("AnimatableFrameAttribute.updateValue called outside an active AttributeGraph context.")
        }

        let target = roundedFrame(
            position: _position.value,
            size: _size.value,
            pixelLength: _pixelLength.value
        )
        var value = (value: target, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil
        ) {
            graph.transaction(for: _position.identifier) ??
                graph.transaction(for: _size.identifier)
        }

        let previousOutput: ViewFrame? = AttributeGraph.currentStatefulOutput()

        if update.didReset || animationsDisabled || previousOutput == nil {
            finishValue(update.target)
            return
        }

        if let targetAnimationBranch = update.targetAnimationBranch {
            switch targetAnimationBranch {
            case .animated(let animation, let transaction, let time):
                let registration = helper.activateStandaloneAnimation(
                    animation: animation,
                    start: previousOutput ?? update.target,
                    target: update.target,
                    transaction: transaction,
                    time: time
                )
                enqueueAnimationCompletionActions(registration.immediateActions)
                value.value = update.target
            case .noAnimation:
                finishValue(update.target)
                return
            }
        }

        guard helper.isAnimating else { return }
        helper.update(
            value: &value,
            environment: _environment
        )
        AttributeGraph.setStatefulOutput(value.value)
    }

    mutating func destroy() {
        helper.clearAnimatorState()
    }

    private func roundedFrame(
        position: CGPoint,
        size: ViewSize,
        pixelLength: CGFloat
    ) -> ViewFrame {
        var frame = ViewFrame(origin: position, size: size)
        if pixelLength > 0, pixelLength.isFinite {
            frame.round(toMultipleOf: pixelLength)
        }
        return frame
    }

    private mutating func finishValue(_ value: ViewFrame) {
        helper.clearAnimatorState()
        helper.commitTarget(value)
        AttributeGraph.setStatefulOutput(value)
    }
}

private struct AnimatableFrameAttributeVFD: StatefulRule {
    typealias Value = ViewFrame

    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _pixelLength: Attribute<CGFloat>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<ViewFrame>
    var velocityFilter = FrameVelocityFilter()
    var animationsDisabled: Bool

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool
    ) {
        self._position = position
        self._size = size
        self._pixelLength = pixelLength
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
        self.animationsDisabled = animationsDisabled
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("AnimatableFrameAttributeVFD.updateValue called outside an active AttributeGraph context.")
        }

        let target = roundedFrame(
            position: _position.value,
            size: _size.value,
            pixelLength: _pixelLength.value
        )
        var value = (value: target, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil
        ) {
            graph.transaction(for: _position.identifier) ??
                graph.transaction(for: _size.identifier)
        }

        let previousOutput: ViewFrame? = AttributeGraph.currentStatefulOutput()

        if update.didReset || animationsDisabled || previousOutput == nil {
            finishValue(update.target)
            return
        }

        if let targetAnimationBranch = update.targetAnimationBranch {
            switch targetAnimationBranch {
            case .animated(let animation, let transaction, let time):
                let registration = helper.activateStandaloneAnimation(
                    animation: animation,
                    start: previousOutput ?? update.target,
                    target: update.target,
                    transaction: transaction,
                    time: time
                )
                enqueueAnimationCompletionActions(registration.immediateActions)
                value.value = update.target
            case .noAnimation:
                finishValue(update.target)
                return
            }
        }

        guard helper.isAnimating else { return }
        helper.update(
            value: &value,
            environment: _environment,
            sampleCollector: { data, time in
                velocityFilter.addSample(data, time: time)
            }
        )
        AttributeGraph.setStatefulOutput(value.value)

        if helper.isAnimating {
            scheduleMaxVelocity()
        } else {
            velocityFilter.reset()
        }
    }

    mutating func destroy() {
        helper.clearAnimatorState()
    }

    private func roundedFrame(
        position: CGPoint,
        size: ViewSize,
        pixelLength: CGFloat
    ) -> ViewFrame {
        var frame = ViewFrame(origin: position, size: size)
        if pixelLength > 0, pixelLength.isFinite {
            frame.round(toMultipleOf: pixelLength)
        }
        return frame
    }

    private mutating func finishValue(_ value: ViewFrame) {
        helper.clearAnimatorState()
        helper.commitTarget(value)
        velocityFilter.reset()
        AttributeGraph.setStatefulOutput(value)
    }

    private mutating func scheduleMaxVelocity() {
        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError("AnimatableFrameAttributeVFD.updateValue requires an active ViewGraph host.")
        }
        viewGraph.nextUpdate.views.maxVelocity(velocityFilter.currentVelocity ?? 0)
    }

}

func makeAnimatableFrameAttributes(
    in inputs: inout _GraphInputs,
    position: Attribute<CGPoint>,
    size: Attribute<ViewSize>,
    supportsVFD: Bool? = nil,
    animationsDisabled: Bool? = nil
) -> AnimatedFrameAttributes {
    guard let graph = AttributeGraph.current else {
        fatalError("makeAnimatableFrameAttributes called outside an active AttributeGraph context.")
    }

    let environment = inputs.cachedEnvironment.value.environment
    let pixelLength: Attribute<CGFloat> = graph.makeRule {
        environment.value.animationPixelLength
    }
    let disabled = animationsDisabled ?? inputs.transaction.value.disablesAnimations
    let usesVFD = supportsVFD ?? inputs.options.contains(.supportsVariableFrameDuration)
    let frame: Attribute<ViewFrame>
    if usesVFD {
        frame = graph.makeStatefulRule(
            AnimatableFrameAttributeVFD(
                position: position,
                size: size,
                pixelLength: pixelLength,
                environment: environment,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                animationsDisabled: disabled
            )
        )
    } else {
        frame = graph.makeStatefulRule(
            AnimatableFrameAttribute(
                position: position,
                size: size,
                pixelLength: pixelLength,
                environment: environment,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                animationsDisabled: disabled
            )
        )
    }
    let animatedPosition: Attribute<CGPoint> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.origin
    )
    let animatedSize: Attribute<ViewSize> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.size
    )

    var cachedEnvironment = inputs.cachedEnvironment.value
    cachedEnvironment.animatedFrame = CachedEnvironment.AnimatedFrame(
        position: position,
        size: size,
        pixelLength: pixelLength,
        time: inputs.time,
        transaction: inputs.transaction,
        viewPhase: inputs.phase,
        animatedFrame: frame,
        _animatedPosition: animatedPosition,
        _animatedSize: animatedSize,
        _animatedCGSize: nil
    )
    inputs.cachedEnvironment = MutableBox(cachedEnvironment)

    return AnimatedFrameAttributes(
        position: animatedPosition,
        size: animatedSize,
        frame: frame
    )
}

private struct AnimatableAttributeHelper<AnimatedValue: Animatable> {
    struct UpdateInputs {
        var didReset: Bool
        var target: AnimatedValue
        var targetAnimationBranch: TargetAnimationBranch?
    }

    enum TargetAnimationBranch {
        case noAnimation
        case animated(animation: Animation, transaction: Transaction, time: Time)
    }

    private var _phase: Attribute<Phase>
    private var _time: Attribute<Time>
    private var _transaction: Attribute<Transaction>
    private var previousModelData: AnimatedValue.AnimatableData?
    private var animatorState: AnimatorState<AnimatedValue>?
    private var resetSeed: UInt32 = 0

    init(
        _phase: Attribute<Phase>,
        _time: Attribute<Time>,
        _transaction: Attribute<Transaction>
    ) {
        self._phase = _phase
        self._time = _time
        self._transaction = _transaction
    }

    private mutating func checkReset() -> Bool {
        let currentResetSeed = _phase.value.resetSeed
        guard currentResetSeed != resetSeed else { return false }
        reset(to: currentResetSeed)
        return true
    }

    private mutating func checkResetForCompletionRecords() -> Bool {
        let currentResetSeed = _phase.value.resetSeed
        guard currentResetSeed != resetSeed else { return false }
        resetForCompletionRecords(to: currentResetSeed)
        return true
    }

    private func hasModelDataChanged(_ data: AnimatedValue.AnimatableData) -> Bool {
        previousModelData.map { $0 != data } ?? true
    }

    private mutating func updatePreviousModelData(_ data: AnimatedValue.AnimatableData) {
        previousModelData = data
    }

    mutating func commitTarget(_ target: AnimatedValue) {
        updatePreviousModelData(target.animatableData)
    }

    var isAnimating: Bool {
        animatorState != nil
    }

    func currentTime() -> Time {
        _time.value
    }

    private mutating func ensureAnimatorState() {
        if animatorState == nil {
            animatorState = AnimatorState()
        }
    }

    private mutating func activate(
        animation: Animation,
        interval: AnimatedValue.AnimatableData,
        beginTime: Time,
        sampleTime: Time,
        transaction: Transaction,
        state: AnimationState<AnimatedValue.AnimatableData>,
        mergeState: AnimationState<AnimatedValue.AnimatableData>,
        isLogicallyComplete: Bool,
        updatesMergeStateWithAnimation: Bool
    ) {
        if animatorState == nil {
            animatorState = AnimatorState(
                animation: animation,
                interval: interval,
                at: beginTime,
                in: transaction
            )
        }
        animatorState?.activate(
            animation: animation,
            interval: interval,
            beginTime: beginTime,
            sampleTime: sampleTime,
            transaction: transaction,
            state: state,
            mergeState: mergeState,
            isLogicallyComplete: isLogicallyComplete,
            updatesMergeStateWithAnimation: updatesMergeStateWithAnimation
        )
    }

    mutating func activateAndAddListeners(
        animation: Animation,
        interval: AnimatedValue.AnimatableData,
        target: AnimatedValue,
        beginTime: Time,
        sampleTime: Time,
        transaction: Transaction,
        state: AnimationState<AnimatedValue.AnimatableData>,
        mergeState: AnimationState<AnimatedValue.AnimatableData>,
        isLogicallyComplete: Bool,
        updatesMergeStateWithAnimation: Bool
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
        updatePreviousModelData(target.animatableData)
        activate(
            animation: animation,
            interval: interval,
            beginTime: beginTime,
            sampleTime: sampleTime,
            transaction: transaction,
            state: state,
            mergeState: mergeState,
            isLogicallyComplete: isLogicallyComplete,
            updatesMergeStateWithAnimation: updatesMergeStateWithAnimation
        )
        return addListenersForCompletionRecords(transaction: transaction)
    }

    mutating func activateStandaloneAnimation(
        animation: Animation,
        start: AnimatedValue,
        target: AnimatedValue,
        transaction: Transaction,
        time: Time
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
        return activateAndAddListeners(
            animation: animation,
            interval: animatableDelta(from: start, to: target),
            target: target,
            beginTime: time,
            sampleTime: time,
            transaction: transaction,
            state: AnimationState(),
            mergeState: AnimationState(),
            isLogicallyComplete: false,
            updatesMergeStateWithAnimation: true
        )
    }

    func baseLayerGenerations() -> Set<UInt64> {
        animatorState?.baseLayerGenerations() ?? []
    }

    func retargetStateSnapshot() -> AnimatorState<AnimatedValue>.RetargetStateSnapshot {
        animatorState?.retargetStateSnapshot() ?? AnimatorState.RetargetStateSnapshot(
            animation: nil,
            state: AnimationState(),
            mergeState: AnimationState(),
            beginTime: .zero,
            isLogicallyComplete: false,
            updatesMergeStateWithAnimation: true,
            baseLayers: [],
            baseLayerStartValue: nil
        )
    }

    func interpolationStateSnapshot(
        defaultFinishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    ) -> AnimatorState<AnimatedValue>.InterpolationStateSnapshot {
        animatorState?.interpolationStateSnapshot(
            defaultFinishingDefinition: defaultFinishingDefinition
        ) ?? AnimatorState.InterpolationStateSnapshot(
            animation: nil,
            state: AnimationState(),
            beginTime: .zero,
            isLogicallyComplete: false,
            finishingDefinition: defaultFinishingDefinition
        )
    }

    mutating func combine(
        newAnimation: Animation,
        newInterval: AnimatedValue.AnimatableData,
        layerStack: [AnimatorState<AnimatedValue>.PresentationLayer]?,
        layerStackBase: AnimatedValue?,
        replacementTarget: AnimatedValue?,
        presentationSeed: AnimatorState<AnimatedValue>.RetargetPresentationSeed?,
        at time: Time,
        in transaction: Transaction,
        environment: Attribute<EnvironmentValues>?
    ) -> AnimatorState<AnimatedValue>.CombineResult {
        animatorState?.combine(
            newAnimation: newAnimation,
            newInterval: newInterval,
            layerStack: layerStack,
            layerStackBase: layerStackBase,
            replacementTarget: replacementTarget,
            presentationSeed: presentationSeed,
            at: time,
            in: transaction,
            environment: environment
        ) ?? AnimatorState<AnimatedValue>.CombineResult(
            merged: false,
            layerStackConversion: nil,
            presentationLayer: nil
        )
    }

    mutating func resetForReplacement() {
        animatorState?.resetForReplacement()
    }

    mutating func resetForFreshActivation() {
        animatorState?.resetForFreshActivation()
    }

    mutating func removeBaseLayers() {
        animatorState?.removeBaseLayers()
    }

    mutating func appendBaseLayer(_ layer: AnimatorState<AnimatedValue>.PresentationLayer) {
        ensureAnimatorState()
        animatorState?.appendBaseLayer(layer)
    }

    private mutating func updateInterval(_ interval: AnimatedValue.AnimatableData) {
        animatorState?.updateInterval(interval)
    }

    mutating func retargetWithoutAnimation(
        to target: AnimatedValue,
        interval: AnimatedValue.AnimatableData
    ) {
        updateInterval(interval)
        updatePreviousModelData(target.animatableData)
    }

    private mutating func addListenersForCompletionRecords(
        transaction: Transaction
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
        return animatorState?.addListenersForCompletionRecords(transaction: transaction) ??
            AnimatorState<AnimatedValue>.ListenerRegistration()
    }

    mutating func beginUpdate(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        transaction: () -> Transaction?
    ) -> UpdateInputs {
        let didReset = checkResetForCompletionRecords()
        let targetChanged = hasModelDataChanged(value.value.animatableData)
        if didReset || targetChanged {
            value.changed = true
        }
        let branch = targetChanged
            ? targetAnimationBranch(
                defaultAnimation: defaultAnimation,
                transaction: transaction
            )
            : nil
        return UpdateInputs(
            didReset: didReset,
            target: value.value,
            targetAnimationBranch: branch
        )
    }

    mutating func beginStandaloneUpdate(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        transaction: () -> Transaction?
    ) -> UpdateInputs {
        let didReset = checkReset()
        let targetChanged = hasModelDataChanged(value.value.animatableData)
        if didReset || targetChanged {
            value.changed = true
        }
        let branch = targetChanged
            ? targetAnimationBranch(
                defaultAnimation: defaultAnimation,
                transaction: transaction
            )
            : nil
        return UpdateInputs(
            didReset: didReset,
            target: value.value,
            targetAnimationBranch: branch
        )
    }

    mutating func update(
        value: inout (value: AnimatedValue, changed: Bool),
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void
    ) {
        guard let animatorState else {
            return
        }
        let time = _time.value
        let continues = animatorState.update(
            value: &value.value,
            at: time,
            environment: environment
        )
        value.changed = true
        if continues {
            finishContinuingUpdate(
                animatorState: animatorState,
                value: value.value,
                time: time,
                sampleCollector: sampleCollector
            )
        } else {
            finishCompletedUpdate(animatorState: animatorState)
        }
    }

    mutating func updateForCompletionRecords(
        value: inout (value: AnimatedValue, changed: Bool),
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void
    ) -> AnimatorState<AnimatedValue>.UpdateResult? {
        guard let animatorState else {
            return nil
        }
        let time = _time.value
        guard let update = animatorState.updateForCompletionRecords(
            value: &value.value,
            at: time,
            environment: environment
        ) else {
            return nil
        }
        if update.continues {
            finishContinuingUpdate(
                animatorState: animatorState,
                value: value.value,
                time: time,
                sampleCollector: sampleCollector
            )
            value.changed = true
        } else {
            finishCompletedUpdateForCompletionRecords()
            value.changed = true
        }
        return update
    }

    mutating func update(
        value: inout (value: AnimatedValue, changed: Bool),
        environment: Attribute<EnvironmentValues>
    ) {
        update(
            value: &value,
            environment: environment,
            sampleCollector: { _, _ in }
        )
    }

    private mutating func removeListeners() {
        animatorState?.removeListeners()
    }

    mutating func clearAnimatorState() {
        removeListeners()
        animatorState = nil
    }

    mutating func clearAnimatorStateForCompletionRecords() {
        animatorState?.clearListenersForCompletionRecords()
        animatorState = nil
    }

    private mutating func finishContinuingUpdate(
        animatorState: AnimatorState<AnimatedValue>,
        value: AnimatedValue,
        time: Time,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void
    ) {
        animatorState.nextUpdate()
        sampleCollector(value.animatableData, time)
    }

    private mutating func finishCompletedUpdate(
        animatorState: AnimatorState<AnimatedValue>
    ) {
        animatorState.removeListeners()
        self.animatorState = nil
    }

    private mutating func finishCompletedUpdateForCompletionRecords() {
        self.animatorState = nil
    }

    private mutating func reset(to currentResetSeed: UInt32) {
        removeListeners()
        animatorState = nil
        previousModelData = nil
        resetSeed = currentResetSeed
    }

    private mutating func resetForCompletionRecords(to currentResetSeed: UInt32) {
        clearAnimatorStateForCompletionRecords()
        previousModelData = nil
        resetSeed = currentResetSeed
    }

    private func animatableDelta(
        from start: AnimatedValue,
        to target: AnimatedValue
    ) -> AnimatedValue.AnimatableData {
        var data = target.animatableData
        data -= start.animatableData
        return data
    }

    private func targetAnimationBranch(
        defaultAnimation: Animation?,
        transaction: () -> Transaction?
    ) -> TargetAnimationBranch {
        let transaction = transaction() ?? _transaction.value
        guard let animation = transaction.effectiveAnimation ?? defaultAnimation else {
            return .noAnimation
        }
        return .animated(
            animation: animation,
            transaction: transaction,
            time: _time.value
        )
    }
}

extension View where Self: Animatable {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var view = view
        Self._makeAnimatable(value: &view, inputs: inputs.base)
        return _makeDefaultView(view: view, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var view = view
        Self._makeAnimatable(value: &view, inputs: inputs.base)
        return _makeDefaultViewList(view: view, inputs: inputs)
    }
}

public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public init(_ _firstType: First.Type, _ _secondType: Second.Type) {
        self.first = _firstType.zero
        self.second = _secondType.zero
    }

    @inlinable subscript() -> (First, Second) {
      get { return (first, second) }
      set { (first, second) = newValue }
    }

    public static var zero: AnimatablePair<First, Second> {
        return .init(First.zero, Second.zero)
    }

    public static func += (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first += rhs.first
        lhs.second += rhs.second
    }

    public static func -= (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first -= rhs.first
        lhs.second -= rhs.second
    }

    public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        return first.magnitudeSquared + second.magnitudeSquared
    }
}

extension AnimatablePair: Equatable {
    public static func == (a: AnimatablePair<First, Second>, b: AnimatablePair<First, Second>) -> Bool {
        return a.first == b.first && a.second == b.second
    }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {
}

public struct _AnyAnimatableData: VectorArithmetic {
    var vtable: _AnyAnimatableDataVTable.Type
    var value: Any

    init<A>(_ value: A) where A: Animatable {
        self.vtable = _AnyAnimatableDataVTableFor<A>.self
        self.value = value.animatableData
    }

    private init(vtable: _AnyAnimatableDataVTable.Type, value: Any) {
        self.vtable = vtable
        self.value = value
    }

    public static var zero: Self {
        Self(vtable: _AnyAnimatableDataZeroVTable.self, value: ())
    }

    func update<A>(_ value: inout A) where A: Animatable {
        guard vtable == _AnyAnimatableDataVTableFor<A>.self,
              let animatableData = self.value as? A.AnimatableData else {
            return
        }
        value.animatableData = animatableData
    }

    public static func += (lhs: inout Self, rhs: Self) {
        if lhs.vtable == rhs.vtable {
            lhs.vtable.add(&lhs.value, rhs.value)
        } else if lhs.vtable == _AnyAnimatableDataZeroVTable.self {
            lhs = rhs
        }
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        if lhs.vtable == rhs.vtable {
            lhs.vtable.subtract(&lhs.value, rhs.value)
        } else if lhs.vtable == _AnyAnimatableDataZeroVTable.self {
            lhs = rhs
            lhs.vtable.negate(&lhs.value)
        }
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }

    public mutating func scale(by rhs: Double) {
        vtable.scale(&value, by: rhs)
    }

    public var magnitudeSquared: Double {
        vtable.magnitudeSquared(value)
    }

    public static func == (a: Self, b: Self) -> Bool {
        guard a.vtable == b.vtable else { return false }
        return a.vtable.isEqual(a.value, b.value)
    }
}

class _AnyAnimatableDataVTable {
    class var zero: Any {
        fatalError()
    }

    class func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        fatalError()
    }

    class func add(_ lhs: inout Any, _ rhs: Any) {
        fatalError()
    }

    class func subtract(_ lhs: inout Any, _ rhs: Any) {
        fatalError()
    }

    class func negate(_ value: inout Any) {
        fatalError()
    }

    class func scale(_ value: inout Any, by rhs: Double) {
        fatalError()
    }

    class func magnitudeSquared(_ value: Any) -> Double {
        fatalError()
    }
}

private final class _AnyAnimatableDataZeroVTable: _AnyAnimatableDataVTable {
    override class var zero: Any {
        ()
    }

    override class func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        lhs is Void && rhs is Void
    }

    override class func add(_ lhs: inout Any, _ rhs: Any) {
    }

    override class func subtract(_ lhs: inout Any, _ rhs: Any) {
    }

    override class func negate(_ value: inout Any) {
    }

    override class func scale(_ value: inout Any, by rhs: Double) {
    }

    override class func magnitudeSquared(_ value: Any) -> Double {
        0
    }
}

private final class _AnyAnimatableDataVTableFor<Value: Animatable>: _AnyAnimatableDataVTable {
    override class var zero: Any {
        Value.AnimatableData.zero
    }

    override class func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let lhs = lhs as? Value.AnimatableData,
              let rhs = rhs as? Value.AnimatableData else {
            return false
        }
        return lhs == rhs
    }

    override class func add(_ lhs: inout Any, _ rhs: Any) {
        guard var lhsValue = lhs as? Value.AnimatableData,
              let rhsValue = rhs as? Value.AnimatableData else {
            return
        }
        lhsValue += rhsValue
        lhs = lhsValue
    }

    override class func subtract(_ lhs: inout Any, _ rhs: Any) {
        guard var lhsValue = lhs as? Value.AnimatableData,
              let rhsValue = rhs as? Value.AnimatableData else {
            return
        }
        lhsValue -= rhsValue
        lhs = lhsValue
    }

    override class func negate(_ value: inout Any) {
        guard var animatableData = value as? Value.AnimatableData else {
            return
        }
        animatableData.scale(by: -1)
        value = animatableData
    }

    override class func scale(_ value: inout Any, by rhs: Double) {
        guard var animatableData = value as? Value.AnimatableData else {
            return
        }
        animatableData.scale(by: rhs)
        value = animatableData
    }

    override class func magnitudeSquared(_ value: Any) -> Double {
        guard let animatableData = value as? Value.AnimatableData else {
            return 0
        }
        return animatableData.magnitudeSquared
    }
}
