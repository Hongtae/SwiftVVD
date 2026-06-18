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

private final class AnimatorState<AnimatedValue: Animatable> {
    enum Phase {
        case pending
        case first
        case second
        case running
    }

    struct Fork {
        struct UpdateResult {
            var value: AnimatedValue
            var removedListeners: [Listener]
        }

        var animation: Animation
        var startValue: AnimatedValue
        var targetValue: AnimatedValue
        var startTime: Time
        var state: AnimationState<AnimatedValue.AnimatableData>
        var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
        var listeners: [AnimationListener] = []
        var contextIsLogicallyComplete: Bool = false
        var generation: UInt64
        var isFinished: Bool = false

        mutating func update(
            time: Time,
            environment: EnvironmentValues,
            baseValue: AnimatedValue
        ) -> UpdateResult {
            guard !isFinished else {
                return UpdateResult(value: targetValue, removedListeners: [])
            }

            let elapsed = max(time.seconds - startTime.seconds, 0)
            var context = makeAnimationContext(
                state: state,
                isLogicallyComplete: contextIsLogicallyComplete,
                environment: environment,
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
                let removedListeners = listeners.map {
                    Listener(listener: $0, criteria: .logicallyComplete)
                }
                listeners.removeAll()
                return UpdateResult(
                    value: targetValue,
                    removedListeners: removedListeners
                )
            }

            return UpdateResult(
                value: AnimatorState.applying(
                    delta: animatedDelta,
                    to: baseValue,
                    target: targetValue
                ),
                removedListeners: []
            )
        }
    }

    var animation: Animation?
    var interval: AnimatedValue.AnimatableData = .zero
    var beginTime: Time = .zero
    var quantizedFrameInterval: TimeInterval = 0
    var nextTime: Time = .zero
    var previousAnimationValue: AnimatedValue.AnimatableData = .zero
    var reason: UInt32?
    var state = AnimationState<AnimatedValue.AnimatableData>()
    var mergeState = AnimationState<AnimatedValue.AnimatableData>()
    var phase: Phase = .pending
    var listeners: [AnimationListener] = []
    var logicalListeners: [AnimationListener] = []
    var isLogicallyComplete = false
    var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    var updatesMergeStateWithAnimation = true
    var baseLayers: [Fork] = []
    var completedBaseLayerValue: AnimatedValue?

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
        var value: AnimatedValue.AnimatableData?
        var isLogicallyComplete: Bool
        var logicalListeners: [Listener] = []
        var discardedBaseLayerGenerations: Set<UInt64> = []
    }

    struct BaseStackSample {
        var value: AnimatedValue
        var removedListeners: [Listener]
    }

    struct ListenerRegistration {
        var records: [Listener] = []
        var immediateActions: [() -> Void] = []
    }

    struct CombineResult {
        var merged: Bool
        var layerStackConversion: LayerStackConversion?
        var forkedLayer: Fork?
    }

    struct LayerStackConversion {
        var animation: Animation
        var state: AnimationState<AnimatedValue.AnimatableData>
        var start: AnimatedValue
        var startTime: Time
    }

    struct RetargetForkSeed {
        var startValue: AnimatedValue
        var targetValue: AnimatedValue
        var startTime: Time
        var generation: UInt64
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

    func combine(
        newAnimation: Animation,
        newInterval: AnimatedValue.AnimatableData?,
        layerStack: [Fork]? = nil,
        layerStackBase: AnimatedValue? = nil,
        replacementTarget: AnimatedValue? = nil,
        forkSeed: RetargetForkSeed? = nil,
        at time: Time,
        in transaction: Transaction,
        environment: EnvironmentValues
    ) -> CombineResult {
        guard let previousAnimation = animation else {
            resetForReplacement()
            refreshScheduling(at: time, from: transaction)
            return CombineResult(
                merged: false,
                layerStackConversion: nil,
                forkedLayer: nil
            )
        }
        if phase == .pending {
            animation = newAnimation
            if let newInterval {
                interval = newInterval
            }
            refreshScheduling(at: time, from: transaction)
            return CombineResult(
                merged: false,
                layerStackConversion: nil,
                forkedLayer: nil
            )
        }
        let elapsed = max(time.seconds - beginTime.seconds, 0)
        var context = makeAnimationContext(
            state: mergeState,
            isLogicallyComplete: isLogicallyComplete,
            environment: environment,
            finishingDefinition: finishingDefinition
        )
        let forkedLayer = makeRetargetFork(
            previousAnimation,
            seed: forkSeed
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
            if let newInterval {
                interval += newInterval
            }
        } else {
            if let newInterval {
                combineCurrentAnimation(
                    previousAnimation,
                    newAnimation: newAnimation,
                    newInterval: newInterval,
                    elapsed: elapsed
                )
            } else if let layerStack,
                      let replacementTarget,
                      let forkedLayer,
                      let conversion = combineLayerStack(
                          layerStack + [forkedLayer],
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
                    forkedLayer: forkedLayer
                )
            } else {
                resetForReplacement()
            }
        }
        refreshScheduling(at: time, from: transaction)
        return CombineResult(
            merged: shouldMerge,
            layerStackConversion: nil,
            forkedLayer: forkedLayer
        )
    }

    func update(
        value: AnimatedValue.AnimatableData,
        at time: Time,
        environment: EnvironmentValues
    ) -> UpdateResult? {
        guard let animation else {
            return nil
        }

        if shouldUsePreviousAnimationValue(at: time) {
            return previousAnimationResult()
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
            return previousAnimationResult()
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
            environment: environment,
            finishingDefinition: finishingDefinition
        )
        let output = animation.box.animate(
            value: value,
            time: elapsed,
            context: &context
        )
        state = context.state
        isLogicallyComplete = context.isLogicallyComplete
        let logicalListeners = updateListeners(
            isLogicallyComplete: context.isLogicallyComplete,
            time: time,
            environment: environment
        )
        if let output {
            recordSampledAnimationValue(output, at: time)
            if updatesMergeStateWithAnimation {
                mergeState = context.state
            }
        }
        return UpdateResult(
            value: output,
            isLogicallyComplete: context.isLogicallyComplete,
            logicalListeners: logicalListeners
        )
    }

    func sampleBaseStackValue(
        at time: Time,
        environment: EnvironmentValues
    ) -> BaseStackSample? {
        guard !baseLayers.isEmpty || completedBaseLayerValue != nil else {
            return nil
        }

        var baseValue = completedBaseLayerValue ?? baseLayers[0].startValue
        var removedListeners: [Listener] = []
        for index in baseLayers.indices {
            var layer = baseLayers[index]
            let result = layer.update(
                time: time,
                environment: environment,
                baseValue: baseValue
            )
            baseValue = result.value
            removedListeners.append(contentsOf: result.removedListeners)
            baseLayers[index] = layer
        }

        pruneFinishedBaseLayerPrefix()

        return BaseStackSample(
            value: baseValue,
            removedListeners: removedListeners
        )
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

    private func previousAnimationResult() -> UpdateResult {
        UpdateResult(
            value: previousAnimationValue,
            isLogicallyComplete: isLogicallyComplete
        )
    }

    func addListeners(
        transaction: Transaction
    ) -> ListenerRegistration {
        guard transaction.animationListener != nil ||
              transaction.animationLogicalListener != nil else {
            return ListenerRegistration()
        }

        var registeredListeners: [Listener] = []
        var immediateActions: [() -> Void] = []
        if let animationListener = transaction.animationListener {
            let registration = addListeners(
                animationListener,
                isLogical: false
            )
            registeredListeners.append(contentsOf: registration.records)
            immediateActions.append(contentsOf: registration.immediateActions)
        }
        if let animationLogicalListener = transaction.animationLogicalListener {
            let registration = addListeners(
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

    private func addListeners(
        _ animationListener: AnimationListener,
        isLogical: Bool
    ) -> ListenerRegistration {
        let criteria: AnimationCompletionCriteria = isLogical
            ? .logicallyComplete
            : .removed
        guard animationListener.criteriaForNewAnimation().contains(criteria) else {
            return ListenerRegistration()
        }

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

    func updateListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: EnvironmentValues
    ) -> [Listener] {
        guard isLogicallyComplete, !logicalListeners.isEmpty else {
            return []
        }
        _ = time
        _ = environment
        let completed = logicalListeners.map {
            Listener(listener: $0, criteria: .logicallyComplete)
        }
        logicalListeners.removeAll()
        return completed
    }

    func removeListeners() -> [Listener] {
        var removed = listeners.map {
            Listener(listener: $0, criteria: .removed)
        }
        removed.append(contentsOf: logicalListeners.map {
            Listener(listener: $0, criteria: .logicallyComplete)
        })
        for layer in baseLayers {
            removed.append(
                contentsOf: layer.listeners.map {
                    Listener(listener: $0, criteria: .logicallyComplete)
                }
            )
        }
        listeners.removeAll()
        logicalListeners.removeAll()
        for index in baseLayers.indices {
            baseLayers[index].listeners.removeAll()
        }
        return removed
    }

    func forkLogicalListeners() -> [AnimationListener] {
        guard !isLogicallyComplete, !logicalListeners.isEmpty else {
            return []
        }
        let forked = logicalListeners
        logicalListeners.removeAll()
        return forked
    }

    private func makeRetargetFork(
        _ previousAnimation: Animation,
        seed: RetargetForkSeed?
    ) -> Fork? {
        guard let seed else {
            return nil
        }
        return Fork(
            animation: previousAnimation,
            startValue: seed.startValue,
            targetValue: seed.targetValue,
            startTime: seed.startTime,
            state: state,
            finishingDefinition: finishingDefinition,
            listeners: forkLogicalListeners(),
            contextIsLogicallyComplete: isLogicallyComplete,
            generation: seed.generation
        )
    }

    func removeBaseLayers() {
        baseLayers.removeAll()
        completedBaseLayerValue = nil
    }

    var baseLayerStartValue: AnimatedValue? {
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
        _ layers: [Fork],
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
    var currentValue: AnimatedValue?
    private var samplingLayers: [SideEffectSamplingLayer] = []
    private var customReplacementCompletionGroup: CustomReplacementCompletionGroup?
    private var combinedResidualCompletionGroup: CombinedResidualCompletionGroup?
    private var combinedFiniteCompletionGroup: CombinedFiniteCompletionGroup?
    private var velocityTrackingImmediateCompletionGroup: CustomReplacementCompletionGroup?
    private var contextLogicalCompletionSuppressedGenerations: Set<UInt64> = []
    private var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 1
    // Each entry represents one transaction completion listener waiting on
    // this animatable node. Retargeting extends older entries to the
    // replacement animation deadline while the newest listener is inserted
    // first.
    private var completionRecords: [CompletionRecord] = []

    private typealias AnimationLayer = AnimatorState<AnimatedValue>.Fork
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

    private var animation: Animation? {
        get { helper.animatorState?.animation }
        set {
            if newValue == nil, helper.animatorState == nil {
                return
            }
            helper.ensureAnimatorState()
            helper.animatorState?.animation = newValue
        }
    }

    private var animationState: AnimationState<AnimatedValue.AnimatableData> {
        get { helper.animatorState?.state ?? AnimationState() }
        set {
            helper.ensureAnimatorState()
            helper.animatorState?.state = newValue
        }
    }

    private var startTime: Time {
        get { helper.animatorState?.beginTime ?? .zero }
        set {
            helper.ensureAnimatorState()
            helper.animatorState?.beginTime = newValue
        }
    }

    private var mergeState: AnimationState<AnimatedValue.AnimatableData> {
        get { helper.animatorState?.mergeState ?? AnimationState() }
        set {
            helper.ensureAnimatorState()
            helper.animatorState?.mergeState = newValue
        }
    }

    private var animationContextIsLogicallyComplete: Bool {
        get { helper.animatorState?.isLogicallyComplete ?? false }
        set {
            helper.ensureAnimatorState()
            helper.animatorState?.isLogicallyComplete = newValue
        }
    }

    private var updatesMergeStateWithAnimation: Bool {
        get { helper.animatorState?.updatesMergeStateWithAnimation ?? true }
        set {
            helper.ensureAnimatorState()
            helper.animatorState?.updatesMergeStateWithAnimation = newValue
        }
    }

    private var baseLayers: [AnimationLayer] {
        get { helper.animatorState?.baseLayers ?? [] }
        set {
            if newValue.isEmpty, helper.animatorState == nil {
                return
            }
            helper.ensureAnimatorState()
            helper.animatorState?.baseLayers = newValue
        }
    }

    private var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)? {
        helper.animatorState?.finishingDefinition ??
            (AnimatedValue.self as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)
    }

    @discardableResult
    private mutating func clearAnimatorState() -> [StateListener] {
        helper.clearAnimatorState()
    }

    @discardableResult
    private mutating func clearAnimationRuntimeState(
        clearingGeneration: Bool = true
    ) -> [StateListener] {
        let removedListeners = clearAnimatorState()
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
        if clearingGeneration {
            currentGeneration = nil
        }
        return removedListeners
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
    }

    private struct CombinedResidualCompletionGroup {
        var replacementGeneration: UInt64
        var oldGenerations: [UInt64]
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
        let updateInputs = helper.beginUpdate(
            value: &updateValue,
            defaultAnimation: nil,
            source: _source,
            in: graph
        )
        if updateInputs.didReset {
            resetAnimationStateForPhaseChange()
        }
        let target = updateInputs.target

        if currentValue == nil {
            finishValue(with: target)
            return
        }

        if let animationBranch = updateInputs.targetAnimationBranch {
            switch animationBranch {
            case .noAnimation:
                guard continueAnimationAfterNoAnimationRetarget(to: target) else {
                    finishValue(with: target)
                    return
                }
                return sampleCurrentAnimationValue()

            case .immediatelyComplete(_, let effectiveTransaction):
                finishZeroDurationAnimationRetarget(
                    with: target,
                    transaction: effectiveTransaction
                )
                return

            case let .animated(animation, effectiveTransaction, now):
                updateAnimatedTargetChange(
                    target: target,
                    animation: animation,
                    transaction: effectiveTransaction,
                    time: now
                )
            }
        }

        sampleCurrentAnimationValue()
    }

    private mutating func updateAnimatedTargetChange(
        target: AnimatedValue,
        animation: Animation,
        transaction effectiveTransaction: Transaction,
        time now: Time
    ) {
        let start = currentValue ?? target
        guard start.animatableData != target.animatableData else {
            finishValue(with: target)
            return
        }
        let previousStart = startValue
        let previousStartTime = startTime
        let previousAnimation = self.animation
        let previousGeneration = currentGeneration
        let replacementGeneration = nextGeneration
        nextGeneration += 1
        let previousForkSeed: AnimatorState<AnimatedValue>.RetargetForkSeed?
        if previousAnimation != nil,
           let previousStart,
           let previousTarget = targetValue,
           let previousGeneration {
            previousForkSeed = AnimatorState.RetargetForkSeed(
                startValue: previousStart,
                targetValue: previousTarget,
                startTime: previousStartTime,
                generation: previousGeneration
            )
        } else {
            previousForkSeed = nil
        }
        let mergedStart = helper.baseLayerStartValue ?? previousStart ?? start
        let mergedStartTime = baseLayers.first?.startTime ?? previousStartTime
        let canCombineInAnimatorState = previousAnimation != nil &&
            previousStart != nil &&
            targetValue != nil &&
            baseLayers.isEmpty &&
            isSourceCustomReplacementAnimation(animation.box)
        let animatorStateNewInterval = canCombineInAnimatorState
            ? targetValue.map { animatableDelta(from: $0, to: target) }
            : nil
        let animatorStateLayerStack = !baseLayers.isEmpty &&
            previousForkSeed != nil &&
            isSourceCustomReplacementAnimation(animation.box)
            ? baseLayers
            : nil
        let animatorStateLayerStackBase = helper.baseLayerStartValue
        let combineResult: AnimatorState<AnimatedValue>.CombineResult
        if previousAnimation != nil,
           previousStart != nil,
           targetValue != nil {
            combineResult = helper.combine(
                newAnimation: animation,
                newInterval: animatorStateNewInterval,
                layerStack: animatorStateLayerStack,
                layerStackBase: animatorStateLayerStackBase,
                replacementTarget: target,
                forkSeed: previousForkSeed,
                at: now,
                in: effectiveTransaction,
                environment: _environment.value
            )
        } else {
            helper.resetForReplacement()
            combineResult = AnimatorState<AnimatedValue>.CombineResult(
                merged: false,
                layerStackConversion: nil,
                forkedLayer: nil
            )
        }
        let merged = combineResult.merged
        let previousLayer = combineResult.forkedLayer
        let previousSamplingLayers = previousLayer.map { baseLayers + [$0] } ?? []
        var activeAnimation = animation
        var activeStart = merged ? mergedStart : start
        var activeStartTime = merged ? mergedStartTime : now
        let usesCombinedAnimation = shouldUseCombinedAnimationForFalseRetarget(
            merged: merged,
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        )
        if usesCombinedAnimation,
           let previousAnimation,
           let previousStart {
            if let converted = combineResult.layerStackConversion {
                activeAnimation = converted.animation
                activeStart = converted.start
                activeStartTime = converted.startTime
            } else {
                activeAnimation = self.animation ?? previousAnimation
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
            baseLayers.append(previousLayer)
        } else {
            helper.removeBaseLayers()
        }
        let activeAnimationState = animationState
        let activeMergeState = mergeState
        let activeContextIsLogicallyComplete = animationContextIsLogicallyComplete
        let activeUpdatesMergeStateWithAnimation = previousAnimation == nil || merged
        let completionStart = now
        let deadlineStartValue = merged ? mergedStart : start
        let presentationDuration = animation.box.presentationDuration(
            for: animatableDelta(from: deadlineStartValue, to: target)
        )
        let deadline = completionStart + animation.box.duration
        velocityTrackingImmediateCompletionGroup = nil
        if shouldFinishCombinedCompletionRecordsWithVelocityTrackingReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let customReplacementCompletionGroup {
            let oldGenerations = customReplacementCompletionGroup.oldGenerations
                .union([customReplacementCompletionGroup.replacementGeneration])
            velocityTrackingImmediateCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: oldGenerations
            )
            self.customReplacementCompletionGroup = nil
        } else if shouldGroupCompletionRecordsForCustomToCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            customReplacementCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: customReplacementOldGenerations(
                    from: previousSamplingLayers,
                    previousGeneration: previousGeneration
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
                oldGenerations: oldGenerations
            )
            for index in completionRecords.indices where oldGenerations.contains(completionRecords[index].orderGeneration) {
                completionRecords[index].deadline = .infinity
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
        helper.updatePreviousModelData(target.animatableData)
        currentValue = start
        let presentationDeadline = completionStart + max(animation.box.duration, presentationDuration)
        let holdsNewLogicalUntilPresentation = shouldHoldDefaultReplacementCompletionUntilPresentation(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        )
        let completesWithoutWaitingForSamplingWindow = isVelocityTrackingAnimation(animation.box)
        let listenerRegistration = helper.activateAndAddListeners(
            animation: activeAnimation,
            interval: activeInterval,
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

    private mutating func sampleCurrentAnimationValue() {
        guard helper.isAnimating,
              let startValue,
              let targetValue else {
            if let currentValue {
                finishValue(with: currentValue)
            }
            return
        }
        let now = helper._time.value
        let baseStackSample = sampleBaseStack(at: now)
        let baseValue = baseStackSample?.value ?? startValue
        let delta = animatableDelta(from: baseValue, to: targetValue)
        var sampledDelta: AnimatedValue.AnimatableData?
        guard let update = helper.update(
            value: delta,
            at: now,
            environment: _environment.value,
            sampleCollector: { value, _ in
                sampledDelta = value
            }
        ) else {
            if let currentValue {
                finishValue(with: currentValue)
            }
            return
        }
        guard let animatedDelta = sampledDelta else {
            enqueueBaseStackCompletionActions(from: baseStackSample)
            // Terminal samples let completion-record ordering own criteria
            // priority. Drained logical state tokens are still present in the
            // copied records, so finishing them here would reorder the boundary.
            if isCombinedFiniteCompletionGroupReplacement(currentGeneration) {
                currentValue = targetValue
                AttributeGraph.setStatefulOutput(targetValue)
                let completions = finishCombinedFiniteCompletionGroup()
                enqueueAnimationCompletionActions(completions)
                return
            }
            if isCustomReplacementCompletionGroupReplacement(currentGeneration) {
                currentValue = targetValue
                AttributeGraph.setStatefulOutput(targetValue)
                // The replacement nil boundary owns this handoff; discarded
                // side-effect layers should not be sampled again after it.
                let completions = finishCustomReplacementCompletionGroup(at: now)
                enqueueAnimationCompletionActions(completions)
                return
            }
            let completions = finishDueCompletionRecords(at: now)
            enqueueAnimationCompletionActions(completions)
            finishAnimation(
                with: targetValue,
                at: now,
                discardedBaseLayerGenerations: update.discardedBaseLayerGenerations
            )
            return
        }
        let output = applying(delta: animatedDelta, to: baseValue, target: targetValue)
        if sampleSideEffectLayers(at: now) {
            return
        }
        currentValue = output
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
           !contextLogicalCompletionSuppressedGenerations.contains(currentGeneration) {
            let logicalListeners = update.logicalListeners
            let completions = logicalListeners.isEmpty
                ? finishCompletionRecords(
                    for: currentGeneration,
                    matching: {
                        $0.criteria != .removed &&
                        $0.orderGeneration == currentGeneration
                    }
                )
                : finishCompletionRecords(matching: logicalListeners)
            enqueueAnimationCompletionActions(completions)
        }
        enqueueBaseStackCompletionActions(from: baseStackSample)
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    mutating func destroy() {
        // Node removal is the last chance to finish listeners that were waiting
        // on this animatable value but no longer have a live output node.
        let completions = finishAllCompletionRecords()
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func resetAnimationStateForPhaseChange() {
        startValue = nil
        targetValue = nil
        currentValue = nil
        clearAnimationRuntimeState()
        nextGeneration = 1
        let completions = finishAllCompletionRecords()
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func continueAnimationAfterNoAnimationRetarget(to target: AnimatedValue) -> Bool {
        guard animation != nil,
              let startValue,
              let previousTarget = targetValue else {
            return false
        }

        let retargetDelta = animatableDelta(from: previousTarget, to: target)
        self.startValue = applying(delta: retargetDelta, to: startValue, target: target)
        if let currentValue {
            self.currentValue = applying(delta: retargetDelta, to: currentValue, target: target)
        }
        targetValue = target
        if let adjustedStart = self.startValue {
            let interval = animatableDelta(from: adjustedStart, to: target)
            helper.updateInterval(interval)
        }
        helper.updatePreviousModelData(target.animatableData)
        return true
    }

    private mutating func finishZeroDurationAnimationRetarget(
        with value: AnimatedValue,
        transaction: Transaction
    ) {
        let now = helper._time.value
        sampleActiveAnimationBeforeImmediateReplacement(at: now)

        let replacementGeneration = nextGeneration
        nextGeneration += 1
        let immediateCompletionGroup = customReplacementCompletionGroup.map {
            CombinedFiniteCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: $0.oldGenerations.union([$0.replacementGeneration])
            )
        }

        let listenerRegistration = helper.addListeners(
            transaction: transaction,
            creatingStateIfNeeded: true
        )
        let newCompletionRecords = completionRecords(
            from: listenerRegistration.records,
            generation: replacementGeneration,
            orderGeneration: replacementGeneration,
            deadline: { _ in now }
        )
        completionRecords.insert(contentsOf: newCompletionRecords, at: 0)
        enqueueAnimationCompletionActions(listenerRegistration.immediateActions)

        startValue = nil
        targetValue = value
        helper.updatePreviousModelData(value.animatableData)
        currentValue = value
        clearAnimationRuntimeState()
        AttributeGraph.setStatefulOutput(value)
        let completions = finishImmediateReplacementCompletionRecords(
            completionGroup: immediateCompletionGroup
        )
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishImmediateReplacementCompletionRecords(
        completionGroup: CombinedFiniteCompletionGroup?
    ) -> [() -> Void] {
        if let completionGroup {
            return finishCombinedFiniteCompletionRecords(completionGroup) +
                finishAllCompletionRecords()
        }
        return finishAllCompletionRecords()
    }

    private func sampleActiveAnimationBeforeImmediateReplacement(at now: Time) {
        guard let animation,
              let startValue,
              let targetValue else {
            return
        }

        let elapsed = max(now.seconds - startTime.seconds, 0)
        var context = makeAnimationContext(
            state: animationState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: _environment.value,
            finishingDefinition: finishingDefinition
        )
        _ = animation.box.animate(
            value: animatableDelta(from: startValue, to: targetValue),
            time: elapsed,
            context: &context
        )
    }

    private mutating func finishValue(with value: AnimatedValue) {
        startValue = nil
        targetValue = value
        helper.updatePreviousModelData(value.animatableData)
        currentValue = value
        clearAnimationRuntimeState()
        AttributeGraph.setStatefulOutput(value)
        guard !completionRecords.isEmpty else { return }
        let now = helper._time.value
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
        helper.updatePreviousModelData(value.animatableData)
        currentValue = value
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
        // If the replacement logical record is still pending at residual
        // finalization, this boundary owns ordinary same-boundary criteria
        // priority. Otherwise an earlier sample already drained it.
        if replacementOtherRecords.isEmpty {
            orderedRecords = oldRemovedRecords +
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

    private mutating func finishCombinedFiniteCompletionGroup() -> [() -> Void] {
        guard let group = combinedFiniteCompletionGroup else {
            return []
        }
        let finalValue = targetValue ?? currentValue
        startValue = nil
        if let finalValue {
            targetValue = finalValue
            helper.updatePreviousModelData(finalValue.animatableData)
            currentValue = finalValue
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
        matching listeners: [StateListener]
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
        return finishRecords(readyRecords)
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
        guard !baseLayers.isEmpty || !samplingLayers.isEmpty else {
            return []
        }

        var generations = Set<UInt64>()
        for layer in baseLayers {
            generations.insert(layer.generation)
        }
        for samplingLayer in samplingLayers {
            for layer in samplingLayer.layers {
                generations.insert(layer.generation)
            }
        }
        return generations
    }

    private func interpolatedValue(at time: Time) -> AnimatedValue? {
        guard let animation,
              let startValue,
              let targetValue else {
            return currentValue
        }
        let elapsed = max(time.seconds - startTime.seconds, 0)
        var context = makeAnimationContext(
            state: animationState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: _environment.value,
            finishingDefinition: finishingDefinition
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
                    let completions = finishCompletionRecords(for: layer.generation) {
                        $0.criteria != .removed
                    }
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
                    let completions = finishCompletionRecords(for: layer.generation) {
                        $0.criteria != .removed
                    }
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

    private mutating func sampleBaseStack(
        at now: Time
    ) -> AnimatorState<AnimatedValue>.BaseStackSample? {
        helper.sampleBaseStackValue(
            at: now,
            environment: _environment.value
        )
    }

    private mutating func enqueueBaseStackCompletionActions(
        from sample: AnimatorState<AnimatedValue>.BaseStackSample?
    ) {
        guard let sample else { return }
        let completions = finishCompletionRecords(
            matching: sample.removedListeners
        )
        enqueueAnimationCompletionActions(completions)
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

    private func isCustomReplacementCompletionGroupOldGeneration(_ generation: UInt64) -> Bool {
        customReplacementCompletionGroup?.oldGenerations.contains(generation) ?? false
    }

    private func isDeferredCompletionGroupOldGeneration(_ generation: UInt64) -> Bool {
        isCustomReplacementCompletionGroupOldGeneration(generation) ||
            (combinedFiniteCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (combinedResidualCompletionGroup?.oldGenerations.contains(generation) ?? false)
    }

    private mutating func finishCustomReplacementCompletionGroup(at now: Time) -> [() -> Void] {
        guard let group = customReplacementCompletionGroup else {
            return []
        }
        let finalValue = targetValue ?? currentValue
        startValue = nil
        if let finalValue {
            targetValue = finalValue
            helper.updatePreviousModelData(finalValue.animatableData)
            currentValue = finalValue
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
        let orderedRecords = oldRemovedRecords +
            replacementRemovedRecords +
            replacementOtherRecords +
            oldOtherRecords
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

    private func shouldUseCombinedAnimationForFalseRetarget(
        merged: Bool,
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        !merged &&
            previousAnimation != nil &&
            isSourceCustomReplacementAnimation(replacementAnimation.box)
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
        box is CustomAnimationBox<VelocityTrackingAnimation>
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
        return isDefaultCombiningAnimation(previousAnimation.box) &&
            presentationDuration > replacementAnimation.box.duration
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
        !box.duration.isFinite && box.preservesRetargetedCompletionDeadlines
    }

    private func isSourceCustomReplacementAnimation(_ box: AnimationBoxBase) -> Bool {
        isSourceDefinedCustomAnimation(box) &&
            !isDefaultCombiningAnimation(box) &&
            !isVelocityTrackingAnimation(box)
    }

    private func isDefaultCombiningAnimation(_ box: AnimationBoxBase) -> Bool {
        box is CustomAnimationBox<DefaultCombiningAnimation>
    }

}

private struct AnimatableAttributeHelper<AnimatedValue: Animatable> {
    struct UpdateInputs {
        var didReset: Bool
        var target: AnimatedValue
        var targetChanged: Bool
        var targetAnimationBranch: TargetAnimationBranch?
    }

    struct AnimationSelection {
        var transaction: Transaction
        var animation: Animation?
    }

    enum TargetAnimationBranch {
        case noAnimation(transaction: Transaction)
        case immediatelyComplete(animation: Animation, transaction: Transaction)
        case animated(animation: Animation, transaction: Transaction, time: Time)
    }

    var _phase: Attribute<Phase>
    var _time: Attribute<Time>
    var _transaction: Attribute<Transaction>
    var previousModelData: AnimatedValue.AnimatableData?
    var animatorState: AnimatorState<AnimatedValue>?
    var resetSeed: UInt32 = 0

    mutating func checkReset() -> Bool {
        let currentResetSeed = _phase.value.resetSeed
        guard currentResetSeed != resetSeed else { return false }
        reset(to: currentResetSeed)
        return true
    }

    func hasModelDataChanged(_ data: AnimatedValue.AnimatableData) -> Bool {
        previousModelData.map { $0 != data } ?? true
    }

    mutating func updatePreviousModelData(_ data: AnimatedValue.AnimatableData) {
        previousModelData = data
    }

    var isAnimating: Bool {
        animatorState != nil
    }

    mutating func ensureAnimatorState() {
        if animatorState == nil {
            animatorState = AnimatorState()
        }
    }

    mutating func activate(
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
        beginTime: Time,
        sampleTime: Time,
        transaction: Transaction,
        state: AnimationState<AnimatedValue.AnimatableData>,
        mergeState: AnimationState<AnimatedValue.AnimatableData>,
        isLogicallyComplete: Bool,
        updatesMergeStateWithAnimation: Bool
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
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
        return addListeners(transaction: transaction)
    }

    var baseLayerStartValue: AnimatedValue? {
        animatorState?.baseLayerStartValue
    }

    mutating func combine(
        newAnimation: Animation,
        newInterval: AnimatedValue.AnimatableData?,
        layerStack: [AnimatorState<AnimatedValue>.Fork]?,
        layerStackBase: AnimatedValue?,
        replacementTarget: AnimatedValue?,
        forkSeed: AnimatorState<AnimatedValue>.RetargetForkSeed?,
        at time: Time,
        in transaction: Transaction,
        environment: EnvironmentValues
    ) -> AnimatorState<AnimatedValue>.CombineResult {
        animatorState?.combine(
            newAnimation: newAnimation,
            newInterval: newInterval,
            layerStack: layerStack,
            layerStackBase: layerStackBase,
            replacementTarget: replacementTarget,
            forkSeed: forkSeed,
            at: time,
            in: transaction,
            environment: environment
        ) ?? AnimatorState<AnimatedValue>.CombineResult(
            merged: false,
            layerStackConversion: nil,
            forkedLayer: nil
        )
    }

    mutating func resetForReplacement() {
        animatorState?.resetForReplacement()
    }

    mutating func removeBaseLayers() {
        animatorState?.removeBaseLayers()
    }

    mutating func updateInterval(_ interval: AnimatedValue.AnimatableData) {
        animatorState?.updateInterval(interval)
    }

    mutating func addListeners(
        transaction: Transaction,
        creatingStateIfNeeded: Bool = false
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
        if creatingStateIfNeeded {
            ensureAnimatorState()
        }
        return animatorState?.addListeners(transaction: transaction) ??
            AnimatorState<AnimatedValue>.ListenerRegistration()
    }

    mutating func updateListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: EnvironmentValues
    ) -> [AnimatorState<AnimatedValue>.Listener] {
        animatorState?.updateListeners(
            isLogicallyComplete: isLogicallyComplete,
            time: time,
            environment: environment
        ) ?? []
    }

    mutating func sampleBaseStackValue(
        at time: Time,
        environment: EnvironmentValues
    ) -> AnimatorState<AnimatedValue>.BaseStackSample? {
        animatorState?.sampleBaseStackValue(
            at: time,
            environment: environment
        )
    }

    mutating func beginUpdate(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        source: Attribute<AnimatedValue>,
        in graph: AttributeGraph
    ) -> UpdateInputs {
        let didReset = checkReset()
        let targetChanged = hasModelDataChanged(value.value.animatableData)
        if didReset || targetChanged {
            value.changed = true
        }
        let branch = targetChanged
            ? targetAnimationBranch(
                defaultAnimation: defaultAnimation,
                source: source,
                in: graph
            )
            : nil
        return UpdateInputs(
            didReset: didReset,
            target: value.value,
            targetChanged: targetChanged,
            targetAnimationBranch: branch
        )
    }

    mutating func update(
        value: AnimatedValue.AnimatableData,
        at time: Time,
        environment: EnvironmentValues,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void
    ) -> AnimatorState<AnimatedValue>.UpdateResult? {
        guard var update = animatorState?.update(
            value: value,
            at: time,
            environment: environment
        ) else {
            return nil
        }
        if let sampledValue = update.value {
            animatorState?.nextUpdate()
            sampleCollector(sampledValue, time)
        } else {
            update.discardedBaseLayerGenerations = Set(
                animatorState?.baseLayers.map(\.generation) ?? []
            )
            _ = clearAnimatorState()
        }
        return update
    }

    mutating func update(
        value: AnimatedValue.AnimatableData,
        at time: Time,
        environment: EnvironmentValues
    ) -> AnimatorState<AnimatedValue>.UpdateResult? {
        update(
            value: value,
            at: time,
            environment: environment,
            sampleCollector: { _, _ in }
        )
    }

    mutating func removeListeners() -> [AnimatorState<AnimatedValue>.Listener] {
        guard let animatorState else {
            return []
        }
        return animatorState.removeListeners()
    }

    mutating func clearAnimatorState() -> [AnimatorState<AnimatedValue>.Listener] {
        let removedListeners = removeListeners()
        animatorState = nil
        return removedListeners
    }

    private mutating func reset(to currentResetSeed: UInt32) {
        _ = clearAnimatorState()
        previousModelData = nil
        resetSeed = currentResetSeed
    }

    func effectiveTransaction(
        source: Attribute<AnimatedValue>,
        in graph: AttributeGraph
    ) -> Transaction {
        graph.transaction(for: source.identifier) ?? _transaction.value
    }

    func animationSelection(
        defaultAnimation: Animation?,
        source: Attribute<AnimatedValue>,
        in graph: AttributeGraph
    ) -> AnimationSelection {
        let transaction = effectiveTransaction(source: source, in: graph)
        return AnimationSelection(
            transaction: transaction,
            animation: transaction.effectiveAnimation ?? defaultAnimation
        )
    }

    func targetAnimationBranch(
        defaultAnimation: Animation?,
        source: Attribute<AnimatedValue>,
        in graph: AttributeGraph
    ) -> TargetAnimationBranch {
        let selection = animationSelection(
            defaultAnimation: defaultAnimation,
            source: source,
            in: graph
        )
        guard let animation = selection.animation else {
            return .noAnimation(transaction: selection.transaction)
        }
        if animation.box.isImmediatelyComplete {
            return .immediatelyComplete(
                animation: animation,
                transaction: selection.transaction
            )
        }
        return .animated(
            animation: animation,
            transaction: selection.transaction,
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
