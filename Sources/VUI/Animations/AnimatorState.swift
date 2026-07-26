//
//  File: AnimatorState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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

final class AnimatorState<AnimatedValue: Animatable> {
    // Local sampling phase for the active animation. This is separate from the
    // graph phase seed used by the helper to detect attribute resets.
    private enum Phase {
        case pending
        case first
        case second
        case running
    }

    // Retargeting moves logical listeners into a fork when the previous
    // animation still needs to sample its own completion boundary.
    private struct Fork {
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
    // `state` drives active sampling.
    private var state = AnimationState<AnimatedValue.AnimatableData>()
    // Model-space delta from the active start value to the current target. The
    // animation box samples this delta; resolvedData applies the sampled delta
    // back to the latest model target.
    private var interval: AnimatedValue.AnimatableData = .zero
    private var beginTime: Time = .zero
    private var quantizedFrameInterval: TimeInterval = 0
    private var nextTime: Time = .zero
    private var previousAnimationValue: AnimatedValue.AnimatableData = .zero
    private var reason: UInt32?
    private var phase: Phase = .pending
    private var listeners: [AnimationListener] = []
    private var logicalListeners: [AnimationListener] = []
    private var isLogicallyComplete = false
    private var finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    // Forks are old logical-completion routes. They no longer affect output,
    // but still sample until their own logical completion boundary is reached.
    private var forks: [Fork] = []
    // Base layers preserve visual continuity across false retargets. The active
    // route samples against their stacked presentation output instead of the raw
    // model start value.
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

    struct ListenerRegistration {
        private let records: [CompletionListener]
        private let immediateActions: [() -> Void]

        static var empty: ListenerRegistration {
            ListenerRegistration(records: [], immediateActions: [])
        }

        static func records(_ records: [CompletionListener]) -> ListenerRegistration {
            ListenerRegistration(records: records, immediateActions: [])
        }

        static func immediateActions(_ immediateActions: [() -> Void]) -> ListenerRegistration {
            ListenerRegistration(records: [], immediateActions: immediateActions)
        }

        func appending(_ registration: ListenerRegistration) -> ListenerRegistration {
            ListenerRegistration(
                records: records + registration.records,
                immediateActions: immediateActions + registration.immediateActions
            )
        }

        func reversingRecordOrder() -> ListenerRegistration {
            ListenerRegistration(
                records: Array(records.reversed()),
                immediateActions: immediateActions
            )
        }

        func mapRecords<Record>(_ transform: (CompletionListener) -> Record) -> [Record] {
            records.map(transform)
        }

        func enqueueImmediateActions() {
            enqueueAnimationCompletionActions(immediateActions)
        }

        private init(
            records: [CompletionListener] = [],
            immediateActions: [() -> Void] = []
        ) {
            self.records = records
            self.immediateActions = immediateActions
        }
    }

    struct CombineResult {
        let merged: Bool
        let layerStackConversion: LayerStackConversion?
        let presentationLayer: PresentationLayer?
        let finishesRetargetCompletionAtActivation: Bool

        init(
            merged: Bool,
            layerStackConversion: LayerStackConversion?,
            presentationLayer: PresentationLayer?,
            finishesRetargetCompletionAtActivation: Bool = false
        ) {
            self.merged = merged
            self.layerStackConversion = layerStackConversion
            self.presentationLayer = presentationLayer
            self.finishesRetargetCompletionAtActivation = finishesRetargetCompletionAtActivation
        }
    }

    struct LayerStackConversion {
        let animation: Animation
        let state: AnimationState<AnimatedValue.AnimatableData>
        let start: AnimatedValue
        let startTime: Time
    }

    struct RetargetPresentationSeed {
        let startValue: AnimatedValue
        let targetValue: AnimatedValue
        let startTime: Time
        let generation: UInt64
    }

    struct RetargetStateSnapshot {
        let animation: Animation?
        let state: AnimationState<AnimatedValue.AnimatableData>
        let beginTime: Time
        let isLogicallyComplete: Bool
        let baseLayers: [PresentationLayer]
        let baseLayerStartValue: AnimatedValue?
    }

    struct InterpolationStateSnapshot {
        let animation: Animation?
        let state: AnimationState<AnimatedValue.AnimatableData>
        let beginTime: Time
        let isLogicallyComplete: Bool
        let finishingDefinition: (any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type)?
    }

    struct CompletionListener {
        struct Identity: Hashable {
            let listenerID: ObjectIdentifier
            let criteria: AnimationCompletionCriteria
        }

        private let listener: AnimationListener
        let criteria: AnimationCompletionCriteria

        var identity: Identity {
            Identity(
                listenerID: ObjectIdentifier(listener),
                criteria: criteria
            )
        }

        func finish() -> [() -> Void] {
            listener.animationWasRemoved()
        }

        fileprivate init(
            listener: AnimationListener,
            criteria: AnimationCompletionCriteria
        ) {
            self.listener = listener
            self.criteria = criteria
        }
    }

    private struct Listener {
        let listener: AnimationListener
        let criteria: AnimationCompletionCriteria

        var completionListener: CompletionListener {
            CompletionListener(
                listener: listener,
                criteria: criteria
            )
        }

        func finish() -> [() -> Void] {
            completionListener.finish()
        }
    }

    struct ListenerSnapshot {
        private let listenerIdentities: Set<CompletionListener.Identity>

        init() {
            listenerIdentities = []
        }

        private init(listenerIdentities: Set<CompletionListener.Identity>) {
            self.listenerIdentities = listenerIdentities
        }

        func inserting(_ listener: CompletionListener) -> ListenerSnapshot {
            var identities = listenerIdentities
            identities.insert(listener.identity)
            return ListenerSnapshot(listenerIdentities: identities)
        }

        func union(_ snapshot: ListenerSnapshot) -> ListenerSnapshot {
            ListenerSnapshot(
                listenerIdentities: listenerIdentities.union(snapshot.listenerIdentities)
            )
        }

        var isEmpty: Bool {
            listenerIdentities.isEmpty
        }

        func contains(_ listener: CompletionListener) -> Bool {
            listenerIdentities.contains(listener.identity)
        }
    }

    // Immutable sample summary for the outer completion-record matcher.
    // AnimatorState owns listener storage and decides which state listeners
    // were drained by this sample; AnimatableAttribute only reads the snapshot
    // to reconcile its copied records and deadline/group ordering.
    struct UpdateResult {
        struct ContinuingCompletion {
            private let isLogicallyComplete: Bool
            private let logicalCompletionListeners: ListenerSnapshot

            func isReadyForLogicalCompletion(
                currentGeneration: UInt64?,
                suppressedGenerations: Set<UInt64>,
                deadlineOwnedGenerations: Set<UInt64>
            ) -> Bool {
                guard isLogicallyComplete,
                      let currentGeneration,
                      !suppressedGenerations.contains(currentGeneration),
                      !deadlineOwnedGenerations.contains(currentGeneration) else {
                    return false
                }
                return true
            }

            var hasLogicalCompletionListeners: Bool {
                !logicalCompletionListeners.isEmpty
            }

            func containsLogicalCompletionListener(
                _ listener: CompletionListener
            ) -> Bool {
                logicalCompletionListeners.contains(listener)
            }

            fileprivate static func snapshot(
                isLogicallyComplete: Bool,
                logicalCompletionListeners: ListenerSnapshot
            ) -> ContinuingCompletion {
                ContinuingCompletion(
                    isLogicallyComplete: isLogicallyComplete,
                    logicalCompletionListeners: logicalCompletionListeners
                )
            }

            private init(
                isLogicallyComplete: Bool,
                logicalCompletionListeners: ListenerSnapshot
            ) {
                self.isLogicallyComplete = isLogicallyComplete
                self.logicalCompletionListeners = logicalCompletionListeners
            }
        }

        struct TerminalCompletion {
            private let listeners: ListenerSnapshot
            private let discardedBaseLayerGenerations: Set<UInt64>

            func containsDrainedListener(_ listener: CompletionListener) -> Bool {
                listeners.contains(listener)
            }

            func discardedBaseLayerGenerations(
                adding generations: Set<UInt64> = []
            ) -> Set<UInt64> {
                generations.union(discardedBaseLayerGenerations)
            }

            fileprivate static func snapshot(
                listeners: ListenerSnapshot,
                discardedBaseLayerGenerations: Set<UInt64>
            ) -> TerminalCompletion {
                TerminalCompletion(
                    listeners: listeners,
                    discardedBaseLayerGenerations: discardedBaseLayerGenerations
                )
            }

            private init(
                listeners: ListenerSnapshot,
                discardedBaseLayerGenerations: Set<UInt64>
            ) {
                self.listeners = listeners
                self.discardedBaseLayerGenerations = discardedBaseLayerGenerations
            }
        }

        private enum CompletionKind {
            case continuing(ContinuingCompletion)
            case terminal(TerminalCompletion)
        }

        let time: Time
        private let completionKind: CompletionKind

        func resolveCompletion<Result>(
            continuing: (ContinuingCompletion) -> Result,
            terminal: (TerminalCompletion) -> Result
        ) -> Result {
            switch completionKind {
            case .continuing(let completion):
                continuing(completion)
            case .terminal(let completion):
                terminal(completion)
            }
        }

        static func continuing(
            time: Time,
            isLogicallyComplete: Bool,
            logicalCompletionListeners: ListenerSnapshot
        ) -> UpdateResult {
            UpdateResult(
                time: time,
                completionKind: .continuing(
                    ContinuingCompletion.snapshot(
                        isLogicallyComplete: isLogicallyComplete,
                        logicalCompletionListeners: logicalCompletionListeners
                    )
                ),
            )
        }

        static func terminal(
            time: Time,
            terminalListeners: ListenerSnapshot,
            discardedBaseLayerGenerations: Set<UInt64>
        ) -> UpdateResult {
            UpdateResult(
                time: time,
                completionKind: .terminal(
                    TerminalCompletion.snapshot(
                        listeners: terminalListeners,
                        discardedBaseLayerGenerations: discardedBaseLayerGenerations
                    )
                )
            )
        }

        private init(
            time: Time,
            completionKind: CompletionKind
        ) {
            self.time = time
            self.completionKind = completionKind
        }
    }

    func activate(
        animation: Animation,
        interval: AnimatedValue.AnimatableData,
        beginTime: Time,
        sampleTime: Time,
        transaction: Transaction,
        state: AnimationState<AnimatedValue.AnimatableData>,
        isLogicallyComplete: Bool
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
        self.isLogicallyComplete = isLogicallyComplete
        self.finishingDefinition = Self.defaultFinishingDefinition
        reason = transaction.animationReason
        updateFrameInterval(from: transaction)
    }

    func updateInterval(_ interval: AnimatedValue.AnimatableData) {
        self.interval = interval
    }

    func resetForReplacement() {
        state = AnimationState()
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
            beginTime: beginTime,
            isLogicallyComplete: isLogicallyComplete,
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

    func forkLogicalListenersForRetargetIfNeeded() {
        guard let previousAnimation = animation,
              phase != .pending else {
            return
        }
        forkListeners(
            animation: previousAnimation,
            state: state,
            interval: interval
        )
    }

    func hasElapsedSinceActivation(at time: Time) -> Bool {
        // A target written at the activation timestamp has not established an
        // elapsed presentation interval and can still be replaced directly.
        phase != .pending && beginTime.seconds < time.seconds
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
            // No active animation means there is nothing to merge against. Reset
            // stateful animation data, but still refresh scheduling from the new
            // transaction before the caller activates the replacement.
            resetForReplacement()
            refreshScheduling(at: time, from: transaction)
            return CombineResult(
                merged: false,
                layerStackConversion: nil,
                presentationLayer: nil
            )
        }
        if phase == .pending {
            // A pending animation has not produced a real sample yet, so the
            // replacement can take over the same storage without treating the
            // old route as an interrupted presentation layer.
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
            // Build the merge query from the active animation state.
            // A true result commits the mutated copy; a false result leaves the
            // active state for combineAnimation to consume unchanged.
            state: state,
            isLogicallyComplete: false,
            environment: resolvedAnimationEnvironment(environment),
            finishingDefinition: finishingDefinition
        )
        // Move logical listeners before querying the replacement. The merge
        // query may mutate context, but old logical listeners must remain tied
        // to the previous route until their own boundary is sampled.
        forkListeners(
            animation: previousAnimation,
            state: state,
            interval: interval
        )
        // Save the visual route before asking the new animation whether it can
        // merge. If merge fails, this layer can still be kept as a presentation
        // base or as a side-effect-only completion sampler.
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
                // Several interrupted presentation layers can collapse into one
                // combined animation. The conversion becomes the new active
                // route, while the caller keeps the old layer for completion
                // side effects if needed.
                animation = conversion.animation
                state = conversion.state
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
        environment: Attribute<EnvironmentValues>?,
        advancesDelayedSecondSample: Bool = false
    ) -> Bool {
        guard let sample = sampleAnimationValue(
            value: &value,
            at: time,
            environment: environment,
            advancesDelayedSecondSample: advancesDelayedSecondSample
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
            : ListenerSnapshot()
        // Terminal sampling is handed back to the outer completion-record
        // sorter. AnimatorState reports which listeners drained; it does not
        // decide cross-generation callback order.
        if sample.output == nil {
            return .terminal(
                time: time,
                terminalListeners: logicalListeners.union(drainRemovedListenersForCompletionRecords()),
                discardedBaseLayerGenerations: baseLayerGenerations()
            )
        }
        return .continuing(
            time: time,
            isLogicallyComplete: sample.isLogicallyComplete,
            logicalCompletionListeners: logicalListeners
        )
    }

    private func sampleAnimationValue(
        value: inout AnimatedValue.AnimatableData,
        at time: Time,
        environment: Attribute<EnvironmentValues>?,
        advancesDelayedSecondSample: Bool = false
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
            // The first rule evaluation establishes the animation clock but does
            // not advance the value yet.
            beginTime = time
            phase = .first
        case .first:
            // The second evaluation preserves the first sampled value while
            // aligning the next frame lane to the current graph time.
            phase = .second
            let elapsedFromPreviousBegin = nextTime.seconds - beginTime.seconds
            let frameInterval = max(quantizedFrameInterval, 1.0 / 60.0)
            let minimumElapsed = frameInterval * 2.0
            let elapsed = time.seconds - beginTime.seconds
            if advancesDelayedSecondSample,
               canAdvanceDelayedSecondSampleForFiniteCurve(),
               listeners.isEmpty,
               logicalListeners.isEmpty,
               forks.isEmpty,
               baseLayers.isEmpty,
               completedBaseLayerValue == nil,
               minimumElapsed <= elapsed {
                phase = .running
            } else {
                nextTime = Time(seconds: time.seconds + elapsedFromPreviousBegin)
                beginTime = time
                let output = restorePreviousAnimationValue(value: &value)
                return (
                    output: output,
                    elapsed: time,
                    isLogicallyComplete: isLogicallyComplete,
                    didRunAnimation: false
                )
            }
        case .second:
            // Avoid an early near-zero sample when the graph produces the first
            // real animation frame late. Clamp the clock to at least two display
            // intervals before entering the steady running phase.
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
            recordSampledAnimationValue(output, at: time)
        }
        return (
            output: output,
            elapsed: Time(seconds: elapsed),
            isLogicallyComplete: context.isLogicallyComplete,
            didRunAnimation: true
        )
    }

    private func canAdvanceDelayedSecondSampleForFiniteCurve() -> Bool {
        guard let animation else { return false }
        return animation.box is BezierAnimationBox ||
            animation.box is UnitCurveAnimationBox
    }

    func update(
        value: inout AnimatedValue,
        at time: Time,
        environment: Attribute<EnvironmentValues>?,
        advancesDelayedSecondSample: Bool = false
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
            environment: environment,
            advancesDelayedSecondSample: advancesDelayedSecondSample
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

        update.resolveCompletion(
            continuing: { _ in value.animatableData = targetData },
            terminal: { _ in value = targetValue }
        )
        return update
    }

    private func sampleBaseStackValue(
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> AnimatedValue? {
        guard !baseLayers.isEmpty || completedBaseLayerValue != nil else {
            return nil
        }

        // Presentation layers form a stack: each completed layer becomes the
        // base for the next layer before the active animation samples against it.
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

    private func recordSampledAnimationValue(
        _ value: AnimatedValue.AnimatableData,
        at time: Time
    ) {
        previousAnimationValue = value
        // Keep scheduling on the same quantized frame lane that produced this
        // sample so velocity-sensitive retargets see stable frame spacing.
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
        // A graph can reevaluate before the selected frame lane advances. Reuse
        // the previous sampled value so velocity-sensitive retargets see stable
        // frame spacing instead of near-duplicate samples.
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
        // The state-owned path can finish already-complete listeners
        // immediately because no outer record sorter needs to copy them first.
        let registration = registerListeners(transaction: transaction)
        registration.enqueueImmediateActions()
    }

    func addListenersForCompletionRecords(
        transaction: Transaction
    ) -> ListenerRegistration {
        // Some callers copy listener identity into a separate deadline sorter.
        // Return the registration payload there, but keep the actual listener
        // storage owned by AnimatorState.
        registerListeners(transaction: transaction)
    }

    private func registerListeners(
        transaction: Transaction
    ) -> ListenerRegistration {
        guard transaction.animationListener != nil ||
              transaction.animationLogicalListener != nil else {
            return .empty
        }

        var registration = ListenerRegistration.empty
        if let animationListener = transaction.animationListener {
            registration = registration.appending(
                registerListener(
                    animationListener,
                    isLogical: false
                )
            )
        }
        if let animationLogicalListener = transaction.animationLogicalListener {
            registration = registration.appending(
                registerListener(
                    animationLogicalListener,
                    isLogical: true
                )
            )
        }

        // Completion ordering prepends newly registered records one at a time.
        // Return the reversed batch so inserting at the front keeps the same
        // newest-first record order while registration moves into AnimatorState.
        return registration.reversingRecordOrder()
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
                return .records([record.completionListener])
            }
            // A logical listener registered after logical completion should see
            // an add/remove pair immediately instead of entering live storage.
            return .immediateActions(record.finish())
        }

        listeners.append(animationListener)
        return .records([record.completionListener])
    }

    private func updateListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?
    ) {
        var actions: [() -> Void] = []
        drainCompletedListeners(
            isLogicallyComplete: isLogicallyComplete,
            time: time,
            environment: environment
        ) { listener in
            actions.append(contentsOf: listener.finish())
        }
        enqueueAnimationCompletionActions(actions)
    }

    private func updateListenersForCompletionRecords(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> ListenerSnapshot {
        var completed = ListenerSnapshot()
        drainCompletedListeners(
            isLogicallyComplete: isLogicallyComplete,
            time: time,
            environment: environment
        ) { listener in
            completed = completed.inserting(listener.completionListener)
        }
        return completed
    }

    private func drainCompletedListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?,
        onCompletion: (Listener) -> Void
    ) {
        guard isLogicallyComplete, !logicalListeners.isEmpty else {
            // Forks have their own animation state. They still need a chance to
            // finish even when the active route has not crossed its logical
            // completion boundary.
            updateForkListeners(
                time: time,
                environment: environment,
                onCompletion: onCompletion
            )
            return
        }
        logicalListeners.forEach {
            onCompletion(Listener(listener: $0, criteria: .logicallyComplete))
        }
        logicalListeners.removeAll()
        updateForkListeners(
            time: time,
            environment: environment,
            onCompletion: onCompletion
        )
    }

    private func updateForkListeners(
        time: Time,
        environment: Attribute<EnvironmentValues>?,
        onCompletion: (Listener) -> Void
    ) {
        guard !forks.isEmpty else { return }
        var completedForkOffsets = IndexSet()
        for index in forks.indices {
            if forks[index].update(time: time, environment: environment) {
                // A fork's listeners are logical listeners from an old route.
                // They complete as logical callbacks, not as removed callbacks,
                // even though the route is no longer active.
                forks[index].listeners.forEach {
                    onCompletion(
                        Listener(listener: $0, criteria: .logicallyComplete)
                    )
                }
                completedForkOffsets.insert(index)
            }
        }
        forks.remove(atOffsets: completedForkOffsets)
    }

    func removeListeners() {
        var actions: [() -> Void] = []
        drainRemovedListenersBeforeClearingStorage { listener in
            actions.append(contentsOf: listener.finish())
        }
        enqueueAnimationCompletionActions(actions)
    }

    private func drainRemovedListenersForCompletionRecords() -> ListenerSnapshot {
        var removed = ListenerSnapshot()
        drainRemovedListenersBeforeClearingStorage { listener in
            removed = removed.inserting(listener.completionListener)
        }
        return removed
    }

    func clearListenersForCompletionRecords() {
        // Completion-record callers already copied listener identities; keep
        // the same storage drain order as removeListeners(), but drop callbacks.
        drainRemovedListenersBeforeClearingStorage { _ in }
    }

    private func drainRemovedListenersBeforeClearingStorage(
        onCompletion: (Listener) -> Void
    ) {
        listeners.forEach {
            onCompletion(Listener(listener: $0, criteria: .removed))
        }
        listeners.removeAll()
        logicalListeners.forEach {
            onCompletion(Listener(listener: $0, criteria: .logicallyComplete))
        }
        logicalListeners.removeAll()
        for fork in forks {
            fork.listeners.forEach {
                onCompletion(Listener(listener: $0, criteria: .logicallyComplete))
            }
        }
        forks.removeAll()
    }

    private func forkListeners(
        animation: Animation,
        state: AnimationState<AnimatedValue.AnimatableData>,
        interval: AnimatedValue.AnimatableData
    ) {
        guard !isLogicallyComplete, !logicalListeners.isEmpty else {
            return
        }
        // The active state is about to retarget. Forked listeners keep using the
        // old animation state and interval so their logical boundary is not lost.
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

// Stateful rule for an animatable value in the graph. The helper below owns the
// live AnimatorState and model-data cache; this outer rule owns presentation
// endpoints and copied completion records so callback ordering can survive
// helper teardown, phase resets, and retargeting.
struct AnimatableAttributeHelper<AnimatedValue: Animatable> {
    struct UpdateInputs {
        let didReset: Bool
        let target: AnimatedValue
        let targetAnimationBranch: TargetAnimationBranch?
        let time: Time
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
        isLogicallyComplete: Bool
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
            isLogicallyComplete: isLogicallyComplete
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
        isLogicallyComplete: Bool
    ) -> AnimatorState<AnimatedValue>.ListenerRegistration {
        updatePreviousModelData(target.animatableData)
        activate(
            animation: animation,
            interval: interval,
            beginTime: beginTime,
            sampleTime: sampleTime,
            transaction: transaction,
            state: state,
            isLogicallyComplete: isLogicallyComplete
        )
        return addListenersForCompletionRecords(transaction: transaction)
    }

    mutating func retargetStandaloneAnimation(
        animation: Animation,
        start: AnimatedValue,
        target: AnimatedValue,
        transaction: Transaction,
        time: Time,
        environment: Attribute<EnvironmentValues>
    ) {
        // Standalone frame-style callers have no copied completion records to
        // update after activation, so listener registration must finish inside
        // AnimatorState before control returns to the rule.
        if let previousModelData,
           let animatorState,
           animatorState.hasElapsedSinceActivation(at: time) {
            var newInterval = target.animatableData
            newInterval -= previousModelData
            updatePreviousModelData(target.animatableData)
            _ = animatorState.combine(
                newAnimation: animation,
                newInterval: newInterval,
                at: time,
                in: transaction,
                environment: environment
            )
            animatorState.addListeners(transaction: transaction)
            return
        }

        updatePreviousModelData(target.animatableData)
        animatorState?.forkLogicalListenersForRetargetIfNeeded()
        activate(
            animation: animation,
            interval: animatableDelta(from: start, to: target),
            beginTime: time,
            sampleTime: time,
            transaction: transaction,
            state: AnimationState(),
            isLogicallyComplete: false
        )
        animatorState?.addListeners(transaction: transaction)
    }

    mutating func replaceUnelapsedStandaloneTargetWithoutAnimation(
        start: AnimatedValue,
        target: AnimatedValue,
        at time: Time
    ) -> Bool {
        guard let animatorState,
              !animatorState.hasElapsedSinceActivation(at: time) else {
            return false
        }
        updatePreviousModelData(target.animatableData)
        animatorState.updateInterval(animatableDelta(from: start, to: target))
        return true
    }

    func baseLayerGenerations() -> Set<UInt64> {
        animatorState?.baseLayerGenerations() ?? []
    }

    func retargetStateSnapshot() -> AnimatorState<AnimatedValue>.RetargetStateSnapshot {
        animatorState?.retargetStateSnapshot() ?? AnimatorState.RetargetStateSnapshot(
            animation: nil,
            state: AnimationState(),
            beginTime: .zero,
            isLogicallyComplete: false,
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
            AnimatorState<AnimatedValue>.ListenerRegistration.empty
    }

    mutating func beginUpdate(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        hasExternalAnimationState: Bool,
        transactionForChangedTarget: () -> Transaction?
    ) -> UpdateInputs {
        // The completion-record path lets the outer rule drain copied records
        // after a phase reset, while the helper clears its own optional state.
        let existingAnimationTime =
            animatorState != nil || hasExternalAnimationState
                ? _time.value
                : nil
        let didReset = checkResetForCompletionRecords()
        let targetChanged = hasModelDataChanged(value.value.animatableData)
        if didReset || targetChanged {
            value.changed = true
        }
        let branch = targetChanged
            ? targetAnimationBranch(
                defaultAnimation: defaultAnimation,
                transactionForChangedTarget: transactionForChangedTarget
            )
            : nil
        return UpdateInputs(
            didReset: didReset,
            target: value.value,
            targetAnimationBranch: branch,
            time: targetChanged
                ? _time.value
                : existingAnimationTime
                    ?? Time(seconds: -Double.infinity)
        )
    }

    mutating func beginStandaloneUpdate(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        transactionForChangedTarget: () -> Transaction?
    ) -> UpdateInputs {
        // An idle helper must not retain a dynamic dependency on graph time.
        // Sample time before reset only when live animation state entered this
        // update, while a changed target still acquires its activation time.
        let existingAnimationTime = animatorState.map { _ in _time.value }
        let didReset = checkReset()
        let targetChanged = hasModelDataChanged(value.value.animatableData)
        if didReset || targetChanged {
            value.changed = true
        }
        let branch = targetChanged
            ? targetAnimationBranch(
                defaultAnimation: defaultAnimation,
                transactionForChangedTarget: transactionForChangedTarget
            )
            : nil
        return UpdateInputs(
            didReset: didReset,
            target: value.value,
            targetAnimationBranch: branch,
            time: targetChanged
                ? _time.value
                : existingAnimationTime
                    ?? Time(seconds: -Double.infinity)
        )
    }

    mutating func update(
        value: inout (value: AnimatedValue, changed: Bool),
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void = { _, _ in },
        advancesDelayedSecondSample: Bool = false
    ) {
        guard let animatorState else {
            return
        }
        let time = _time.value
        let continues = animatorState.update(
            value: &value.value,
            at: time,
            environment: environment,
            advancesDelayedSecondSample: advancesDelayedSecondSample
        )
        value.changed = true
        if continues {
            finishContinuingUpdate(
                value: value.value,
                time: time,
                sampleCollector: sampleCollector
            )
        } else {
            finishCompletedUpdate()
        }
    }

    mutating func updateForCompletionRecords(
        value: inout (value: AnimatedValue, changed: Bool),
        environment: Attribute<EnvironmentValues>
    ) -> AnimatorState<AnimatedValue>.UpdateResult? {
        guard let animatorState else {
            return nil
        }
        let time = _time.value
        // State samples the animation and returns listener identity snapshots;
        // the outer attribute matches those identities against copied records.
        guard let update = animatorState.updateForCompletionRecords(
            value: &value.value,
            at: time,
            environment: environment
        ) else {
            return nil
        }
        // Mark the caller payload changed exactly once after a real state
        // sample. Terminal cleanup below must not overwrite that sample result.
        value.changed = true
        update.resolveCompletion(
            continuing: { _ in
                // The matcher bridge has no caller sample collector; it only
                // needs the state to schedule its next frame before returning
                // identities to the outer completion-record sorter.
                animatorState.nextUpdate()
            },
            terminal: { _ in
                // Listener identities needed for completion ordering are
                // already in `update`; removing listeners here would be too
                // late and would risk changing callback order. Drop only the
                // live animator container.
                dropCompletedAnimatorStateForCompletionRecords()
            }
        )
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

    mutating func finishAndClearAnimatorState() {
        // Immediate teardown path: live AnimatorState still owns listener
        // callbacks, so clearing it must finish them before dropping storage.
        removeListeners()
        animatorState = nil
    }

    mutating func clearAnimatorStateStorageForCompletionRecords() {
        // Copied-record path: the outer attribute owns callback ordering. Clear
        // live listener arrays without firing callbacks from the helper.
        animatorState?.clearListenersForCompletionRecords()
        animatorState = nil
    }

    private mutating func finishContinuingUpdate(
        value: AnimatedValue,
        time: Time,
        sampleCollector: (AnimatedValue.AnimatableData, Time) -> Void
    ) {
        animatorState?.nextUpdate()
        sampleCollector(value.animatableData, time)
    }

    private mutating func finishCompletedUpdate() {
        finishAndClearAnimatorState()
    }

    // Completion-record samples have already drained state-owned listener
    // identities into the returned snapshot. The helper tail only drops the
    // optional state; the outer copied-record sorter owns callback ordering.
    private mutating func dropCompletedAnimatorStateForCompletionRecords() {
        self.animatorState = nil
    }

    private mutating func reset(to currentResetSeed: UInt32) {
        finishAndClearAnimatorState()
        previousModelData = nil
        resetSeed = currentResetSeed
    }

    private mutating func resetForCompletionRecords(to currentResetSeed: UInt32) {
        // Completion records are copied by the outer rule, so reset only the
        // helper-owned live state and model cache.
        clearAnimatorStateStorageForCompletionRecords()
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
        transactionForChangedTarget: () -> Transaction?
    ) -> TargetAnimationBranch {
        let transaction = transactionForChangedTarget() ?? _transaction.value
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
