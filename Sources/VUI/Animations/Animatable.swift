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

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: Self.AnimatableData { get set }

    static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { fatalError() }
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
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeAnimatable called outside an active AttributeGraph context.")
        }
        let attr: Attribute<Self> = graph.makeStatefulRule(
            AnimatableAttribute(
                source: value._attribute,
                time: inputs.time,
                transaction: inputs.transaction,
                environment: inputs.cachedEnvironment.value.environment
            )
        )
        value = _GraphValue(_attribute: attr)
    }
}

private struct AnimatableAttribute<AnimatedValue: Animatable>: StatefulRule {
    typealias Value = AnimatedValue

    var source: Attribute<AnimatedValue>
    var time: Attribute<Time>
    var transaction: Attribute<Transaction>
    var environment: Attribute<EnvironmentValues>

    var startValue: AnimatedValue?
    var targetValue: AnimatedValue?
    var currentValue: AnimatedValue?
    var startTime: Time = .zero
    var animation: Animation?
    var animationState = AnimationState<AnimatedValue.AnimatableData>()
    var mergeState = AnimationState<AnimatedValue.AnimatableData>()
    private var animationContextIsLogicallyComplete = false
    private var updatesMergeStateWithAnimation = true
    private var baseLayers: [AnimationLayer] = []
    private var samplingLayers: [SideEffectSamplingLayer] = []
    private var customReplacementCompletionGroup: CustomReplacementCompletionGroup?
    private var combinedResidualCompletionGroup: CombinedResidualCompletionGroup?
    private var combinedFiniteCompletionGroup: CombinedFiniteCompletionGroup?
    private var velocityTrackingImmediateCompletionGroup: CustomReplacementCompletionGroup?
    private var contextLogicalCompletionSuppressedGenerations: Set<UInt64> = []
    private var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 1
    // Each entry represents one transaction completion token waiting on this
    // animatable node. Retargeting extends older entries to the replacement
    // animation deadline while the newest token is inserted first.
    private var completionRecords: [CompletionRecord] = []

    private struct CompletionRecord {
        var token: AnimationCompletionToken
        var deadline: Time
        var generation: UInt64
        var orderGeneration: UInt64

        var criteria: AnimationCompletionCriteria {
            token.criteria
        }
    }

    private struct AnimationLayer {
        var animation: Animation
        var startValue: AnimatedValue
        var targetValue: AnimatedValue
        var startTime: Time
        var state: AnimationState<AnimatedValue.AnimatableData>
        var contextIsLogicallyComplete: Bool = false
        var generation: UInt64
        var isFinished: Bool = false
    }

    private struct SideEffectSamplingLayer {
        var layers: [AnimationLayer]
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
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        environment: Attribute<EnvironmentValues>
    ) {
        self.source = source
        self.time = time
        self.transaction = transaction
        self.environment = environment
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("AnimatableAttribute.updateValue called outside an active AttributeGraph context.")
        }

        let target = source.value
        let inheritedTransaction = transaction.value
        let sourceTransaction = graph.transaction(for: source.identifier)
        let effectiveTransaction = sourceTransaction ?? inheritedTransaction

        if currentValue == nil {
            finishValue(with: target)
            return
        }

        let targetChanged = targetValue.map {
            $0.animatableData != target.animatableData
        } ?? true

        if targetChanged {
            guard let animation = effectiveTransaction.effectiveAnimation else {
                guard continueAnimationAfterNoAnimationRetarget(to: target) else {
                    finishValue(with: target)
                    return
                }
                return sampleCurrentAnimationValue()
            }
            guard !animation.box.isImmediatelyComplete else {
                finishZeroDurationAnimationRetarget(
                    with: target,
                    transaction: effectiveTransaction
                )
                return
            }
            let now = time.value
            let start = currentValue ?? target
            guard start.animatableData != target.animatableData else {
                finishValue(with: target)
                return
            }
            let previousStart = startValue
            let previousStartTime = startTime
            let previousAnimation = self.animation
            let previousAnimationState = animationState
            let previousGeneration = currentGeneration
            let replacementGeneration = nextGeneration
            nextGeneration += 1
            let previousLayer: AnimationLayer?
            let previousSamplingLayers: [AnimationLayer]
            if let previousAnimation,
               let previousStart,
               let previousTarget = targetValue,
               let previousGeneration {
                let layer = AnimationLayer(
                    animation: previousAnimation,
                    startValue: previousStart,
                    targetValue: previousTarget,
                    startTime: previousStartTime,
                    state: previousAnimationState,
                    contextIsLogicallyComplete: animationContextIsLogicallyComplete,
                    generation: previousGeneration
                )
                previousLayer = layer
                previousSamplingLayers = baseLayers + [layer]
            } else {
                previousLayer = nil
                previousSamplingLayers = []
            }
            let mergedStart = baseLayers.first?.startValue ?? previousStart ?? start
            let mergedStartTime = baseLayers.first?.startTime ?? previousStartTime
            let merged = mergeAnimationStateIfNeeded(
                newAnimation: animation,
                previousAnimation: previousAnimation,
                previousStart: previousStart,
                previousTarget: targetValue,
                now: now
            )
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
               let previousStart,
               let previousTarget = targetValue {
                if !baseLayers.isEmpty,
                   let converted = combinedAnimationFromLayerStack(
                       previousSamplingLayers,
                       appending: animation,
                       target: target,
                       at: now
                   ) {
                    activeAnimation = converted.animation
                    animationState = converted.state
                    activeStart = converted.start
                    activeStartTime = converted.startTime
                } else {
                    var combinedAnimation = previousAnimation
                    var combinedState = previousAnimationState
                    combineAnimation(
                        into: &combinedAnimation,
                        state: &combinedState,
                        value: animatableDelta(from: previousStart, to: previousTarget),
                        elapsed: max(now.seconds - previousStartTime.seconds, 0),
                        newAnimation: animation,
                        newValue: animatableDelta(from: previousTarget, to: target)
                    )
                    activeAnimation = combinedAnimation
                    animationState = combinedState
                    activeStart = previousStart
                    activeStartTime = previousStartTime
                }
            }
            if !previousSamplingLayers.isEmpty {
                samplingLayers.append(SideEffectSamplingLayer(layers: previousSamplingLayers))
            }
            if usesCombinedAnimation {
                baseLayers.removeAll()
            } else if !merged,
               let previousLayer {
                baseLayers.append(previousLayer)
            } else {
                baseLayers.removeAll()
            }
            updatesMergeStateWithAnimation = previousAnimation == nil || merged
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
            if let observer = effectiveTransaction.animationCompletionObserver {
                let presentationDeadline = completionStart + max(animation.box.duration, presentationDuration)
                let holdsNewLogicalUntilPresentation = shouldHoldDefaultReplacementCompletionUntilPresentation(
                    previousAnimation: previousAnimation,
                    replacementAnimation: animation
                )
                let completesWithoutWaitingForSamplingWindow = isVelocityTrackingAnimation(animation.box)
                for criteria in observer.criteriaForNewAnimation() {
                    guard let token = observer.animationDidStart(criteria: criteria) else {
                        continue
                    }
                    let waitsForPresentation = criteria == .removed || holdsNewLogicalUntilPresentation
                    let registeredDeadline = animation.box.registeredCompletionDelay(for: criteria).map {
                        completionStart + $0
                    }
                    let recordDeadline = completesWithoutWaitingForSamplingWindow
                        ? completionStart
                        : registeredDeadline ?? (waitsForPresentation ? presentationDeadline : deadline)
                    completionRecords.insert(
                        CompletionRecord(
                            token: token,
                            deadline: recordDeadline,
                            generation: replacementGeneration,
                            orderGeneration: replacementGeneration
                        ),
                        at: 0
                    )
                }
            }
            startValue = activeStart
            targetValue = target
            currentValue = start
            startTime = activeStartTime
            self.animation = activeAnimation
            currentGeneration = replacementGeneration
        }

        sampleCurrentAnimationValue()
    }

    private mutating func sampleCurrentAnimationValue() {
        guard let animation,
              let startValue,
              let targetValue else {
            if let currentValue {
                finishValue(with: currentValue)
            }
            return
        }
        let now = time.value
        let elapsed = max(now.seconds - startTime.seconds, 0)
        var context = makeAnimationContext(
            for: AnimatedValue.self,
            state: animationState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: environment.value
        )
        let baseValue = sampledBaseStackValue(at: now) ?? startValue
        let delta = animatableDelta(from: baseValue, to: targetValue)
        guard let animatedDelta = animation.box.animate(
            value: delta,
            time: elapsed,
            context: &context
        ) else {
            animationState = context.state
            animationContextIsLogicallyComplete = context.isLogicallyComplete
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
            finishAnimation(with: targetValue, at: now)
            return
        }
        animationState = context.state
        animationContextIsLogicallyComplete = context.isLogicallyComplete
        if updatesMergeStateWithAnimation {
            mergeState = context.state
        }
        let output = applying(delta: animatedDelta, to: baseValue, target: targetValue)
        sampleSideEffectLayers(at: now)
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
        if context.isLogicallyComplete,
           let currentGeneration,
           !contextLogicalCompletionSuppressedGenerations.contains(currentGeneration) {
            let completions = finishCompletionRecords(
                for: currentGeneration,
                matching: {
                    $0.criteria != .removed &&
                    $0.orderGeneration == currentGeneration
                }
            )
            enqueueAnimationCompletionActions(completions)
        }
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    mutating func destroy() {
        // Node removal is the last chance to finish listeners that were waiting
        // on this animatable value but no longer have a live output node.
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
        return true
    }

    private mutating func finishZeroDurationAnimationRetarget(
        with value: AnimatedValue,
        transaction: Transaction
    ) {
        let now = time.value
        sampleActiveAnimationBeforeImmediateReplacement(at: now)

        let replacementGeneration = nextGeneration
        nextGeneration += 1
        let immediateCompletionGroup = customReplacementCompletionGroup.map {
            CombinedFiniteCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: $0.oldGenerations.union([$0.replacementGeneration])
            )
        }

        if let observer = transaction.animationCompletionObserver {
            for criteria in observer.criteriaForNewAnimation() {
                guard let token = observer.animationDidStart(criteria: criteria) else {
                    continue
                }
                completionRecords.insert(
                    CompletionRecord(
                        token: token,
                        deadline: now,
                        generation: replacementGeneration,
                        orderGeneration: replacementGeneration
                    ),
                    at: 0
                )
            }
        }

        startValue = nil
        targetValue = value
        currentValue = value
        animation = nil
        animationState = AnimationState()
        mergeState = AnimationState()
        animationContextIsLogicallyComplete = false
        updatesMergeStateWithAnimation = true
        baseLayers.removeAll()
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
        currentGeneration = nil
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
            for: AnimatedValue.self,
            state: animationState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: environment.value
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
        currentValue = value
        animation = nil
        animationState = AnimationState()
        mergeState = AnimationState()
        animationContextIsLogicallyComplete = false
        updatesMergeStateWithAnimation = true
        baseLayers.removeAll()
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
        currentGeneration = nil
        AttributeGraph.setStatefulOutput(value)
        guard !completionRecords.isEmpty else { return }
        let now = time.value
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishAnimation(
        with value: AnimatedValue,
        at now: Time,
        finishAllRecords: Bool = false
    ) {
        startValue = nil
        targetValue = value
        currentValue = value
        animation = nil
        animationContextIsLogicallyComplete = false
        let discardedInfiniteGenerations = discardedInfiniteLayerGenerations()
        let combinedResidualGroup = combinedResidualCompletionGroup
        let combinedFiniteGroup = combinedFiniteCompletionGroup
        baseLayers.removeAll()
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
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
        let orderedRecords = replacementOtherRecords +
            oldRemovedRecords +
            replacementRemovedRecords +
            oldOtherRecords
        return orderedRecords.flatMap { $0.token.finish() }
    }

    private mutating func finishCombinedFiniteCompletionGroup() -> [() -> Void] {
        guard let group = combinedFiniteCompletionGroup else {
            return []
        }
        let finalValue = targetValue ?? currentValue
        startValue = nil
        if let finalValue {
            targetValue = finalValue
            currentValue = finalValue
        }
        animation = nil
        animationState = AnimationState()
        mergeState = AnimationState()
        animationContextIsLogicallyComplete = false
        updatesMergeStateWithAnimation = true
        baseLayers.removeAll()
        samplingLayers.removeAll()
        currentGeneration = nil
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()

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
        return orderedRecords.flatMap { $0.token.finish() }
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
                .flatMap { $0.token.finish() }
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
        return (removedRecords + otherRecords).flatMap { $0.token.finish() }
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
            for: AnimatedValue.self,
            state: animationState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: environment.value
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

    private mutating func sampleSideEffectLayers(at now: Time) {
        guard !samplingLayers.isEmpty else { return }

        let sampledLayers = samplingLayers
        var remainingLayers: [SideEffectSamplingLayer] = []
        remainingLayers.reserveCapacity(sampledLayers.count)
        for samplingLayer in sampledLayers {
            if !isSideEffectSamplingLayerComplete(samplingLayer, at: now) {
                remainingLayers.append(samplingLayer)
            }
        }
        samplingLayers = remainingLayers
    }

    private mutating func isSideEffectSamplingLayerComplete(
        _ samplingLayer: SideEffectSamplingLayer,
        at now: Time
    ) -> Bool {
        guard !samplingLayer.layers.isEmpty else { return true }

        var baseValue = samplingLayer.layers[0].startValue
        var didReachLastLayer = false
        for index in samplingLayer.layers.indices {
            let layer = samplingLayer.layers[index]
            let elapsed = max(now.seconds - layer.startTime.seconds, 0)
            var context = makeAnimationContext(
                for: AnimatedValue.self,
                state: layer.state,
                isLogicallyComplete: layer.contextIsLogicallyComplete,
                environment: environment.value
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
        return didReachLastLayer
    }

    private mutating func sampledBaseStackValue(at now: Time) -> AnimatedValue? {
        guard !baseLayers.isEmpty else {
            return nil
        }

        var layers = baseLayers
        var baseValue = layers[0].startValue
        for index in layers.indices {
            var layer = layers[index]
            if layer.isFinished {
                baseValue = layer.targetValue
                continue
            }

            let elapsed = max(now.seconds - layer.startTime.seconds, 0)
            var context = makeAnimationContext(
                for: AnimatedValue.self,
                state: layer.state,
                isLogicallyComplete: layer.contextIsLogicallyComplete,
                environment: environment.value
            )
            let animatedDelta = layer.animation.box.animate(
                value: animatableDelta(from: baseValue, to: layer.targetValue),
                time: elapsed,
                context: &context
            )
            guard let animatedDelta else {
                layer.state = context.state
                layer.contextIsLogicallyComplete = context.isLogicallyComplete
                layer.isFinished = true
                layers[index] = layer
                baseValue = layer.targetValue
                continue
            }

            layer.state = context.state
            layer.contextIsLogicallyComplete = context.isLogicallyComplete
            layers[index] = layer
            baseValue = applying(
                delta: animatedDelta,
                to: baseValue,
                target: layer.targetValue
            )
        }

        baseLayers = layers
        return baseValue
    }

    private func isCustomReplacementCompletionGroupReplacement(_ generation: UInt64?) -> Bool {
        guard let generation,
              let group = customReplacementCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
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
            currentValue = finalValue
            AttributeGraph.setStatefulOutput(finalValue)
        }
        animation = nil
        animationState = AnimationState()
        mergeState = AnimationState()
        animationContextIsLogicallyComplete = false
        updatesMergeStateWithAnimation = true
        baseLayers.removeAll()
        samplingLayers.removeAll()
        currentGeneration = nil
        customReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()

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
        return orderedRecords.flatMap { $0.token.finish() }
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

    private func combinedAnimationFromLayerStack(
        _ layers: [AnimationLayer],
        appending replacementAnimation: Animation,
        target replacementTarget: AnimatedValue,
        at now: Time
    ) -> (
        animation: Animation,
        state: AnimationState<AnimatedValue.AnimatableData>,
        start: AnimatedValue,
        startTime: Time
    )? {
        guard let firstLayer = layers.first,
              let lastLayer = layers.last else {
            return nil
        }

        var entries: [DefaultCombiningAnimation.Entry] = []
        var stateEntries: [CombinedAnimationState<AnimatedValue.AnimatableData>.Entry] = []
        entries.reserveCapacity(layers.count)
        stateEntries.reserveCapacity(layers.count)

        for layer in layers {
            entries.append(
                DefaultCombiningAnimation.Entry(
                    animation: layer.animation,
                    elapsed: max(layer.startTime.seconds - firstLayer.startTime.seconds, 0)
                )
            )
            stateEntries.append(
                CombinedAnimationState.Entry(
                    value: animatableDelta(
                        from: firstLayer.startValue,
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
            value: animatableDelta(from: firstLayer.startValue, to: lastLayer.targetValue),
            elapsed: max(now.seconds - firstLayer.startTime.seconds, 0),
            newAnimation: replacementAnimation,
            newValue: animatableDelta(from: lastLayer.targetValue, to: replacementTarget)
        )

        return (
            animation: combinedAnimation,
            state: combinedState,
            start: firstLayer.startValue,
            startTime: firstLayer.startTime
        )
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

    private mutating func mergeAnimationStateIfNeeded(
        newAnimation: Animation,
        previousAnimation: Animation?,
        previousStart: AnimatedValue?,
        previousTarget: AnimatedValue?,
        now: Time
    ) -> Bool {
        guard let previousAnimation,
              let previousStart,
              let previousTarget else {
            animationState = AnimationState()
            mergeState = AnimationState()
            animationContextIsLogicallyComplete = false
            return false
        }
        let elapsed = max(now.seconds - startTime.seconds, 0)
        var context = makeAnimationContext(
            for: AnimatedValue.self,
            state: mergeState,
            isLogicallyComplete: animationContextIsLogicallyComplete,
            environment: environment.value
        )
        let shouldMerge = newAnimation.box.shouldMerge(
            previous: previousAnimation,
            value: animatableDelta(from: previousStart, to: previousTarget),
            time: elapsed,
            context: &context
        )
        if shouldMerge {
            animationState = context.state
            mergeState = context.state
            animationContextIsLogicallyComplete = context.isLogicallyComplete
        } else {
            animationState = AnimationState()
            mergeState = AnimationState()
            animationContextIsLogicallyComplete = false
        }
        return shouldMerge
    }
}

extension View where Self: Animatable {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}

public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
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

private extension VectorArithmetic {
    @inline(__always)
    func add(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self + (rhs as! Self)
    }
    @inline(__always)
    func subtract(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self - (rhs as! Self)
    }
    @inline(__always)
    func isEqual(to rhs: any VectorArithmetic) -> Bool {
        if let v = rhs as? Self {
            return self == v
        }
        return false
    }
}

public struct _AnyAnimatableData: VectorArithmetic {

    private struct _Zero: VectorArithmetic {
        static func += (_: inout Self, _: Self)     { fatalError() }
        static func -= (_: inout Self, _: Self)     { fatalError() }
        static func + (_: Self, _: Self) -> Self    { fatalError() }
        static func - (_: Self, _: Self) -> Self    { fatalError() }
        static func == (_: Self, _: Self) -> Bool   { fatalError() }
        static var zero: Self { Self() }
        func scale(by: Double) { }
        var magnitudeSquared: Double { 0 }
    }

    var value: any VectorArithmetic

    init(_ value: any VectorArithmetic) {
        self.value = value
    }

    public static var zero: Self {
        Self(_Zero.zero)
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero { return Self(rhs) }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.add(rhs))
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero {
            var v = rhs.value
            v.scale(by: -1)
            return Self(v)
        }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.subtract(rhs))
    }

    public mutating func scale(by rhs: Double) {
        self.value.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        self.value.magnitudeSquared
    }

    public static func == (a: Self, b: Self) -> Bool {
        if a.value is _Zero { return b.magnitudeSquared == 0 }
        if b.value is _Zero { return a.magnitudeSquared == 0 }
        return a.value.isEqual(to: b.value)
    }
}
