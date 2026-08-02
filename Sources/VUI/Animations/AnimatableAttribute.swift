//
//  File: AnimatableAttribute.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Animatable {
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeAnimatable called outside an active _AGGraph context.")
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
        attr.flags = .transactional
        value = _GraphValue(_attribute: attr)
    }
}

extension Attribute where Value: Animatable {
    func animated(inputs: _GraphInputs) -> Attribute<Value> {
        var value = _GraphValue(_attribute: self)
        Value._makeAnimatable(value: &value, inputs: inputs)
        return value._attribute
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

private struct AnimatableAttribute<AnimatedValue: Animatable>: StatefulRule, ObservedAttribute, AsyncAttribute, CustomStringConvertible {
    typealias Value = AnimatedValue

    var _source: Attribute<AnimatedValue>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<AnimatedValue>

    // Presentation endpoints for the active route. These are deliberately kept
    // outside AnimatorState because retargeting needs both the graph output and
    // the old model endpoints while the helper mutates its state.
    var startValue: AnimatedValue?
    var targetValue: AnimatedValue?
    // Interrupted presentation layers are sampled only for listener/completion
    // side effects; they must not become the current graph output again.
    private var samplingLayers: [SideEffectSamplingLayer] = []
    private var customReplacementCompletionGroup: CustomReplacementCompletionGroup?
    private var sourceCustomResidualReplacementCompletionGroup: SourceCustomResidualReplacementCompletionGroup?
    private var residualWrapperReplacementCompletionGroup: ResidualWrapperReplacementCompletionGroup?
    private var combinedResidualCompletionGroup: CombinedResidualCompletionGroup?
    private var combinedFiniteCompletionGroup: CombinedFiniteCompletionGroup?
    private var velocityTrackingImmediateCompletionGroup: CustomReplacementCompletionGroup?
    private var noAnimationRetargetPresentationDeadline: Time?
    private var deferredTerminalPresentationDeadline: Time?
    private var contextLogicalCompletionSuppressedGenerations: Set<UInt64> = []
    private var deadlineOwnedLogicalCompletionGenerations: Set<UInt64> = []
    private var deadlineOwnedLogicalCompletionOrderGenerations: Set<UInt64> = []
    // A generation identifies one target activation. `generation` can be
    // rewritten when a later animation owns an old callback deadline, while
    // `orderGeneration` preserves the original activation for final ordering.
    private var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 1
    // Each entry represents one transaction completion listener waiting on
    // this animatable node. Retargeting extends older entries to the
    // replacement animation deadline while the newest listener is inserted
    // first.
    private var completionRecords: [CompletionRecord] = []

    var description: String {
        "Animatable<\(AnimatedValue.self)>"
    }

    private typealias AnimationLayer = AnimatorState<AnimatedValue>.PresentationLayer
    private typealias StateCompletionListener = AnimatorState<AnimatedValue>.CompletionListener

    private struct CompletionRecord {
        private let listener: StateCompletionListener
        // Deadline decides readiness. The final drain still applies criteria and
        // generation ordering, so a ready record is not necessarily run first.
        var deadline: Time
        var generation: UInt64
        let orderGeneration: UInt64
        let prefersOldToNewLogicalOrder: Bool

        var criteria: AnimationCompletionCriteria {
            listener.criteria
        }

        func finish() -> [() -> Void] {
            listener.finish()
        }

        func isMatched(
            by continuingCompletion: AnimatorState<AnimatedValue>.UpdateResult.ContinuingCompletion
        ) -> Bool {
            continuingCompletion.containsLogicalCompletionListener(listener)
        }

        func isMatched(
            by terminalCompletion: AnimatorState<AnimatedValue>.UpdateResult.TerminalCompletion
        ) -> Bool {
            terminalCompletion.containsDrainedListener(listener)
        }

        init(
            listener: StateCompletionListener,
            deadline: Time,
            generation: UInt64,
            orderGeneration: UInt64,
            prefersOldToNewLogicalOrder: Bool = false
        ) {
            self.listener = listener
            self.deadline = deadline
            self.generation = generation
            self.orderGeneration = orderGeneration
            self.prefersOldToNewLogicalOrder = prefersOldToNewLogicalOrder
        }
    }

    private struct CompletionGroupRecords {
        let oldRemovedRecords: [CompletionRecord]
        let replacementRemovedRecords: [CompletionRecord]
        let replacementOtherRecords: [CompletionRecord]
        let oldOtherRecords: [CompletionRecord]
    }

    private mutating func clearAnimationRuntimeState(
        clearingGeneration: Bool = true
    ) {
        helper.clearAnimatorStateStorageForCompletionRecords()
        clearCompletionRecordSideState(clearingGeneration: clearingGeneration)
    }

    // Completion records intentionally live outside helper/state storage so
    // retarget deadlines and generation ordering can survive helper teardown.
    // Use this after the helper has already cleared its own optional state.
    private mutating func clearCompletionRecordSideState(
        clearingGeneration: Bool = true
    ) {
        samplingLayers.removeAll()
        customReplacementCompletionGroup = nil
        sourceCustomResidualReplacementCompletionGroup = nil
        residualWrapperReplacementCompletionGroup = nil
        combinedResidualCompletionGroup = nil
        combinedFiniteCompletionGroup = nil
        velocityTrackingImmediateCompletionGroup = nil
        noAnimationRetargetPresentationDeadline = nil
        deferredTerminalPresentationDeadline = nil
        contextLogicalCompletionSuppressedGenerations.removeAll()
        deadlineOwnedLogicalCompletionGenerations.removeAll()
        deadlineOwnedLogicalCompletionOrderGenerations.removeAll()
        if clearingGeneration {
            currentGeneration = nil
        }
    }

    private struct SideEffectSamplingLayer {
        let layers: [AnimationLayer]
    }

    private struct SideEffectSamplingResult {
        let isComplete: Bool
        let didFinishCurrentAnimation: Bool
    }

    private struct CustomReplacementCompletionGroup {
        let replacementGeneration: UInt64
        let oldGenerations: Set<UInt64>
        let prefersReplacementLogicalBeforeRemoved: Bool
        let prefersOldLogicalBeforeReplacement: Bool

        init(
            replacementGeneration: UInt64,
            oldGenerations: Set<UInt64>,
            prefersReplacementLogicalBeforeRemoved: Bool = false,
            prefersOldLogicalBeforeReplacement: Bool = false
        ) {
            self.replacementGeneration = replacementGeneration
            self.oldGenerations = oldGenerations
            self.prefersReplacementLogicalBeforeRemoved = prefersReplacementLogicalBeforeRemoved
            self.prefersOldLogicalBeforeReplacement = prefersOldLogicalBeforeReplacement
        }
    }

    private struct SourceCustomResidualReplacementCompletionGroup {
        let replacementGeneration: UInt64
        let oldGenerations: Set<UInt64>
        var completedOldGenerations: Set<UInt64> = []
        var didReachReplacementTerminal = false

        var isReadyToFinish: Bool {
            didReachReplacementTerminal &&
                oldGenerations.isSubset(of: completedOldGenerations)
        }
    }

    private struct ResidualWrapperReplacementCompletionGroup {
        let replacementGeneration: UInt64
        let oldGenerations: Set<UInt64>
    }

    private struct CombinedResidualCompletionGroup {
        let replacementGeneration: UInt64
        let oldGenerations: [UInt64]
        let prefersSourceLogicalBeforeReplacement: Bool
        let prefersOldLogicalBeforeRemoved: Bool
        let prefersReplacementLogicalBeforeRemoved: Bool
        let prefersReplacementLogicalBeforeSourceLogical: Bool
        let holdsSourceLogicalUntilFinalization: Bool
    }

    private struct CombinedFiniteCompletionGroup {
        let replacementGeneration: UInt64
        let oldGenerations: Set<UInt64>
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
        guard _AGGraph.current != nil else {
            fatalError("AnimatableAttribute.updateValue called outside an active _AGGraph context.")
        }

        var updateValue = (value: _source.value, changed: false)
        let updateInputs = helper.beginUpdate(
            value: &updateValue,
            defaultAnimation: nil,
            hasExternalAnimationState: hasExternalAnimationState,
            transactionForChangedTarget: { nil }
        )
        let target = updateInputs.target
        if updateInputs.didReset {
            finishPhaseReset(with: target, at: updateInputs.time)
            return
        }
        let previousOutput: AnimatedValue? = _AGGraph.currentStatefulOutput()

        guard let previousOutput else {
            finishValue(with: target, at: updateInputs.time)
            return
        }

        if let animationBranch = updateInputs.targetAnimationBranch {
            switch animationBranch {
            case .noAnimation:
                guard let fallbackValue = continueAnimationAfterNoAnimationRetarget(
                    to: target,
                    currentOutput: previousOutput
                ) else {
                    finishValue(with: target, at: updateInputs.time)
                    return
                }
                return sampleCurrentAnimationValue(
                    value: &updateValue,
                    fallbackValue: fallbackValue,
                    fallbackTime: updateInputs.time
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
            if !samplingLayers.isEmpty {
                if sampleSideEffectLayers(at: updateInputs.time) {
                    return
                }
                let completions = finishDueCompletionRecords(at: updateInputs.time)
                enqueueAnimationCompletionActions(completions)
            }
            return
        }
        sampleCurrentAnimationValue(
            value: &updateValue,
            fallbackValue: previousOutput,
            fallbackTime: updateInputs.time
        )
    }

    private var hasExternalAnimationState: Bool {
        startValue != nil ||
            currentGeneration != nil ||
            !samplingLayers.isEmpty ||
            customReplacementCompletionGroup != nil ||
            sourceCustomResidualReplacementCompletionGroup != nil ||
            residualWrapperReplacementCompletionGroup != nil ||
            combinedResidualCompletionGroup != nil ||
            combinedFiniteCompletionGroup != nil ||
            velocityTrackingImmediateCompletionGroup != nil ||
            noAnimationRetargetPresentationDeadline != nil ||
            deferredTerminalPresentationDeadline != nil ||
            !contextLogicalCompletionSuppressedGenerations.isEmpty ||
            !deadlineOwnedLogicalCompletionGenerations.isEmpty ||
            !deadlineOwnedLogicalCompletionOrderGenerations.isEmpty ||
            !completionRecords.isEmpty
    }

    private mutating func updateAnimatedTargetChange(
        target: AnimatedValue,
        currentOutput: AnimatedValue,
        animation: Animation,
        transaction effectiveTransaction: Transaction,
        time now: Time
    ) {
        noAnimationRetargetPresentationDeadline = nil
        deferredTerminalPresentationDeadline = nil
        let start = currentOutput
        guard start.animatableData != target.animatableData else {
            finishValue(with: target, at: now)
            return
        }
        // Snapshot helper-owned state before any retarget mutation. This method
        // needs both the pre-combine route and the post-combine active route to
        // rewrite copied completion records without moving listener storage back
        // out of AnimatorState.
        let retargetState = helper.retargetStateSnapshot()
        let previousStart = startValue
        let previousStartTime = retargetState.beginTime
        let previousAnimation = retargetState.animation
        let previousGeneration = currentGeneration
        let replacementGeneration = nextGeneration
        nextGeneration += 1
        // Capture the previous presentation route before combine mutates helper
        // state. The seed is the minimum data needed to rebuild an interrupted
        // animation as a base layer for visual continuity.
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
        // Helper/state owns the merge decision and listener movement. The outer
        // rule keeps copied completion records so deadline rewrites can be
        // ordered independently of state-owned listener storage.
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
        let usesWrapperLocalFiniteReplacementPresentation =
            shouldUseWrapperLocalFiniteReplacementPresentation(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            )
        let usesCombinedAnimation = previousLayer != nil &&
            shouldUseCombinedAnimationForFalseRetarget(
                merged: merged,
                previousAnimation: previousAnimation,
                hasBaseLayers: !retargetState.baseLayers.isEmpty,
                hasLayerStackConversion: combineResult.layerStackConversion != nil,
                usesWrapperLocalFiniteReplacementPresentation: usesWrapperLocalFiniteReplacementPresentation
            )
        let restartsVelocityTrackingPresentationAtCurrentOutput =
            shouldRestartVelocityTrackingPresentationAtCurrentOutput(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            )
        if usesCombinedAnimation,
           let previousAnimation,
           let previousStart {
            // A failed merge can still promote the old presentation route into
            // the new active animation when the replacement must keep sampling
            // against the interrupted presentation value.
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
        if restartsVelocityTrackingPresentationAtCurrentOutput {
            activeStart = start
            activeStartTime = now
        }
        if usesCombinedAnimation {
            helper.removeBaseLayers()
        } else if !merged,
           let previousLayer,
           !usesWrapperLocalFiniteReplacementPresentation {
            helper.appendBaseLayer(previousLayer)
        } else {
            helper.removeBaseLayers()
        }
        let activeAnimationState = activeRetargetState.state
        var activeContextIsLogicallyComplete = activeRetargetState.isLogicallyComplete
        let completionStart = now
        let deadlineStartValue = merged ? mergedStart : start
        let deadlineInterval = animatableDelta(from: deadlineStartValue, to: target)
        var cachedPresentationDuration: TimeInterval?
        func presentationDuration() -> TimeInterval {
            if let cachedPresentationDuration {
                return cachedPresentationDuration
            }
            let duration = animation.box.presentationDuration(for: deadlineInterval)
            cachedPresentationDuration = duration
            return duration
        }
        var cachedResolvedPresentationDuration: TimeInterval?
        func resolvedPresentationDuration() -> TimeInterval {
            if let cachedResolvedPresentationDuration {
                return cachedResolvedPresentationDuration
            }
            let duration = resolvedCompletionPresentationDuration(
                previousAnimation: previousAnimation,
                replacementAnimation: animation,
                previousSamplingLayers: previousSamplingLayers,
                valuePresentationDuration: presentationDuration()
            )
            cachedResolvedPresentationDuration = duration
            return duration
        }
        let deadline = completionStart + animation.box.duration
        let existingRemovedOrderGenerations = Set(
            completionRecords
                .filter { $0.criteria == .removed }
                .map(\.orderGeneration)
        )
        let preservesAllPendingDirectFluidSpringLogicalOnlyRecords =
            previousAnimation?.box is FluidSpringAnimationBox &&
            animation.box is FluidSpringAnimationBox &&
            !completionRecords.isEmpty &&
            completionRecords.allSatisfy {
                $0.criteria != .removed &&
                    !existingRemovedOrderGenerations.contains($0.orderGeneration)
            }
        if previousAnimation != nil,
           !completionRecords.isEmpty,
           !preservesAllPendingDirectFluidSpringLogicalOnlyRecords {
            let valuePresentationDuration = presentationDuration()
            let resolvedDuration = resolvedPresentationDuration()
            if resolvedDuration > valuePresentationDuration {
                deferredTerminalPresentationDeadline =
                    completionStart + resolvedDuration
            }
        }
        velocityTrackingImmediateCompletionGroup = nil
        var holdsCombinedResidualReplacementLogicalUntilPresentation = false
        // The active AnimatorState owns sampling and listener movement. The
        // outer completion records own deadlines across retargets, so each
        // branch below only rewrites copied record ownership; it does not move
        // listener arrays back out of AnimatorState. Keep all deadline rewrites
        // before the replacement activation so new listener records can be
        // inserted with a clean generation boundary.
        //
        // Branch order is intentional: specific grouped handoffs run before the
        // broader "move to replacement boundary" and "clamp earlier" families.
        // Widening an earlier predicate can steal records from a later family.
        if shouldGroupResidualWrapperReplacementCompletionRecords(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            residualWrapperReplacementCompletionGroup = ResidualWrapperReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: [previousGeneration]
            )
        }
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
        } else if let customReplacementCompletionGroup,
                  shouldMoveCombinedCompletionRecordsToResidualReplacementFinalization(
            previousAnimation: previousAnimation,
            replacementAnimation: animation,
            presentationDuration: resolvedPresentationDuration()
        ) {
            let oldGenerations = customReplacementCompletionGroup.oldGenerations
                .union([customReplacementCompletionGroup.replacementGeneration])
                .sorted()
            let letsDeadlineOwnReplacementLogical =
                shouldLetDeadlineOwnCombinedResidualReplacementLogical(
                    replacementAnimation: animation,
                    previousSamplingLayers: previousSamplingLayers,
                    oldGenerations: oldGenerations,
                    replacementLogicalDeadline: deadline
                )
            let prefersReplacementLogicalBeforeSourceLogical =
                shouldFinishCombinedResidualReplacementLogicalBeforeSourceLogical(
                    replacementAnimation: animation
                )
            combinedResidualCompletionGroup = CombinedResidualCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: oldGenerations,
                prefersSourceLogicalBeforeReplacement: shouldFinishCombinedResidualSourceLogicalBeforeReplacement(
                    replacementAnimation: animation
                ) && letsDeadlineOwnReplacementLogical &&
                    !prefersReplacementLogicalBeforeSourceLogical,
                prefersOldLogicalBeforeRemoved: shouldFinishCombinedResidualSourceLogicalBeforeRemoved(
                    replacementAnimation: animation
                ),
                prefersReplacementLogicalBeforeRemoved: shouldFinishCombinedResidualReplacementLogicalBeforeRemoved(
                    replacementAnimation: animation
                ),
                prefersReplacementLogicalBeforeSourceLogical: prefersReplacementLogicalBeforeSourceLogical,
                holdsSourceLogicalUntilFinalization: shouldHoldCombinedResidualSourceLogicalUntilFinalization(
                    replacementAnimation: animation
                )
            )
            for index in completionRecords.indices where oldGenerations.contains(completionRecords[index].orderGeneration) {
                completionRecords[index].deadline = .infinity
            }
            if letsDeadlineOwnReplacementLogical {
                // The logical callback is still registered on the active state,
                // but this family orders it at the copied-record deadline.
                deadlineOwnedLogicalCompletionGenerations.insert(replacementGeneration)
                activeContextIsLogicallyComplete = false
            }
            if shouldHoldCombinedResidualReplacementLogicalUntilFinalization(
                previousAnimation: previousAnimation,
                replacementAnimation: animation,
                previousSamplingLayers: previousSamplingLayers,
                value: deadlineInterval
            ) && combinedResidualCompletionGroup?.prefersSourceLogicalBeforeReplacement != true {
                // Keep context from draining the replacement logical callback
                // early; residual finalization releases it with the grouped
                // removed/source callbacks.
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
            customReplacementCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: [previousGeneration],
                prefersOldLogicalBeforeReplacement: true
            )
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
            let movesLogicalRecords = shouldMoveResidualWrapperLogicalCompletionRecordsToSourceCustomReplacement(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            )
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed || movesLogicalRecords {
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
            customReplacementCompletionGroup = CustomReplacementCompletionGroup(
                replacementGeneration: replacementGeneration,
                oldGenerations: [previousGeneration],
                prefersOldLogicalBeforeReplacement: true
            )
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
        } else if shouldHoldSourceCustomCompletionRecordsUntilResidualWrapperSideEffectNil(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            sourceCustomResidualReplacementCompletionGroup =
                SourceCustomResidualReplacementCompletionGroup(
                    replacementGeneration: replacementGeneration,
                    oldGenerations: [previousGeneration]
                )
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = .infinity
                    completionRecords[index].generation = replacementGeneration
                }
            }
        } else if shouldHoldFiniteRepeatForkCompletionRecordsForNewestRepeatBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            let removedOrderGenerations = Set(
                completionRecords
                    .filter { $0.criteria == .removed }
                    .map(\.orderGeneration)
            )
            for index in completionRecords.indices {
                let orderGeneration = completionRecords[index].orderGeneration
                completionRecords[index].generation = replacementGeneration
                if removedOrderGenerations.contains(orderGeneration) {
                    completionRecords[index].deadline = deadline
                    deadlineOwnedLogicalCompletionOrderGenerations.remove(orderGeneration)
                } else if completionRecords[index].deadline == .infinity {
                    completionRecords[index].deadline = deadline
                } else {
                    completionRecords[index].deadline = .infinity
                    deadlineOwnedLogicalCompletionOrderGenerations.insert(orderGeneration)
                }
            }
        } else if shouldReleaseHeldFiniteRepeatForkCompletionRecordsAtNewestRepeatBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            for index in completionRecords.indices
                where completionRecords[index].criteria != .removed &&
                completionRecords[index].deadline == .infinity {
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveHeldOlderFiniteRepeatForkCompletionRecordsToFiniteReplacementBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            let completionDeadline = completionStart + max(
                animation.box.duration,
                presentationDuration()
            )
            for index in completionRecords.indices
                where completionRecords[index].criteria != .removed &&
                completionRecords[index].orderGeneration != previousGeneration {
                completionRecords[index].deadline = completionDeadline
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldMoveSourceCustomCompletionRecordsToFiniteReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ), let previousGeneration {
            let completionDeadline = completionStart + max(
                animation.box.duration,
                presentationDuration()
            )
            for index in completionRecords.indices where completionRecords[index].orderGeneration == previousGeneration {
                if completionRecords[index].criteria == .removed {
                    completionRecords[index].deadline = completionDeadline
                    completionRecords[index].generation = replacementGeneration
                } else if completionRecords[index].deadline.seconds > completionDeadline.seconds {
                    completionRecords[index].deadline = completionDeadline
                }
            }
        } else if !completionRecords.isEmpty,
           !preservesAllPendingDirectFluidSpringLogicalOnlyRecords,
           merged,
           shouldMoveMergedCompletionRecordsToPresentation(
               previousAnimation: previousAnimation,
               replacementAnimation: animation,
               presentationDuration: resolvedPresentationDuration()
           ) {
            let presentationDeadline = completionStart + resolvedPresentationDuration()
            if shouldGroupResidualWrapperReplacementCompletionRecords(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            ), let previousGeneration {
                residualWrapperReplacementCompletionGroup = ResidualWrapperReplacementCompletionGroup(
                    replacementGeneration: replacementGeneration,
                    oldGenerations: [previousGeneration]
                )
            }
            let movesPreviousRepeatGroup = shouldMoveFiniteRepeatCompletionRecordsAsGroupToPresentation(
                previousAnimation: previousAnimation
            )
            for index in completionRecords.indices {
                if shouldPreserveDirectBezierOrFluidSpringLogicalOnlyForkDeadline(
                    record: completionRecords[index],
                    previousAnimation: previousAnimation,
                    replacementAnimation: animation,
                    replacementBoundary: presentationDeadline,
                    removedOrderGenerations: existingRemovedOrderGenerations
                ) {
                    continue
                }
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
        } else if !completionRecords.isEmpty &&
                  !preservesAllPendingDirectFluidSpringLogicalOnlyRecords &&
                  previousAnimation != nil &&
                  shouldMoveResidualCompletionRecordsToPresentation(
            previousAnimation: previousAnimation,
            replacementAnimation: animation,
            presentationDuration: resolvedPresentationDuration()
        ) {
            let presentationDeadline = completionStart + resolvedPresentationDuration()
            if shouldGroupResidualWrapperReplacementCompletionRecords(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            ), let previousGeneration {
                residualWrapperReplacementCompletionGroup = ResidualWrapperReplacementCompletionGroup(
                    replacementGeneration: replacementGeneration,
                    oldGenerations: [previousGeneration]
                )
            }
            let movesPreviousRepeatGroup = shouldMoveFiniteRepeatCompletionRecordsAsGroupToPresentation(
                previousAnimation: previousAnimation
            )
            for index in completionRecords.indices {
                if shouldPreserveDirectBezierOrFluidSpringLogicalOnlyForkDeadline(
                    record: completionRecords[index],
                    previousAnimation: previousAnimation,
                    replacementAnimation: animation,
                    replacementBoundary: presentationDeadline,
                    removedOrderGenerations: existingRemovedOrderGenerations
                ) {
                    continue
                }
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
                if shouldPreserveDirectBezierOrFluidSpringLogicalOnlyForkDeadline(
                    record: completionRecords[index],
                    previousAnimation: previousAnimation,
                    replacementAnimation: animation,
                    replacementBoundary: deadline,
                    removedOrderGenerations: existingRemovedOrderGenerations
                ) {
                    continue
                }
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        } else if shouldClampCompletionRecordsToEarlierReplacementBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            for index in completionRecords.indices where completionRecords[index].deadline.seconds > deadline.seconds {
                if shouldPreserveDirectBezierOrFluidSpringLogicalOnlyForkDeadline(
                    record: completionRecords[index],
                    previousAnimation: previousAnimation,
                    replacementAnimation: animation,
                    replacementBoundary: deadline,
                    removedOrderGenerations: existingRemovedOrderGenerations
                ) {
                    continue
                }
                completionRecords[index].deadline = deadline
                completionRecords[index].generation = replacementGeneration
            }
        }
        // From this point the replacement generation is active. Older copied
        // records may still remain pending, but their deadlines/generation
        // ownership have been rewritten above.
        startValue = activeStart
        targetValue = target
        let activeInterval = animatableDelta(from: activeStart, to: target)
        func presentationDeadline() -> Time {
            completionStart + max(
                animation.box.duration,
                resolvedPresentationDuration()
            )
        }
        let holdsNewLogicalUntilPresentation =
            shouldHoldDefaultReplacementCompletionUntilPresentation(
                previousAnimation: previousAnimation,
                replacementAnimation: animation
            ) ||
            holdsCombinedResidualReplacementLogicalUntilPresentation ||
            contextLogicalCompletionSuppressedGenerations.contains(replacementGeneration)
        if shouldCompleteCombinedResidualLogicalWrapperAtActivation(
            previousAnimation: previousAnimation,
            replacementAnimation: animation
        ) {
            activeContextIsLogicallyComplete = true
        }
        let completesWithoutWaitingForSamplingWindow = isVelocityTrackingAnimation(animation.box)
        let listenerRegistration = helper.activateAndAddListeners(
            animation: activeAnimation,
            interval: activeInterval,
            target: target,
            beginTime: activeStartTime,
            sampleTime: now,
            transaction: effectiveTransaction,
            state: activeAnimationState,
            isLogicallyComplete: activeContextIsLogicallyComplete
        )
        // ListenerRegistration comes from the live AnimatorState. The records
        // copied here become the outer rule's durable sorter; later helper clears
        // must not drop or reorder these callbacks.
        let newCompletionRecords = completionRecords(
            from: listenerRegistration,
            generation: replacementGeneration,
            orderGeneration: replacementGeneration,
            prefersOldToNewLogicalOrder: shouldOrderFixedAliasLogicalRecordsOldToNew(
                animation: animation,
                registration: listenerRegistration
            )
        ) { criteria in
            let waitsForPresentation = criteria == .removed || holdsNewLogicalUntilPresentation
            let registeredDeadline = animation.box.registeredCompletionDelay(for: criteria).map {
                completionStart + $0
            }
            return completesWithoutWaitingForSamplingWindow
                ? completionStart
                : registeredDeadline ?? (waitsForPresentation ? presentationDeadline() : deadline)
        }
        // New records stay at the front so same-generation ties preserve the
        // newest registration before the final criterion ordering pass.
        completionRecords.insert(contentsOf: newCompletionRecords, at: 0)
        listenerRegistration.enqueueImmediateActions()
        currentGeneration = replacementGeneration
    }

    private func completionRecords(
        from registration: AnimatorState<AnimatedValue>.ListenerRegistration,
        generation: UInt64,
        orderGeneration: UInt64,
        prefersOldToNewLogicalOrder: Bool = false,
        deadline: (AnimationCompletionCriteria) -> Time
    ) -> [CompletionRecord] {
        registration.mapRecords { listener in
            CompletionRecord(
                listener: listener,
                deadline: deadline(listener.criteria),
                generation: generation,
                orderGeneration: orderGeneration,
                prefersOldToNewLogicalOrder: prefersOldToNewLogicalOrder && listener.criteria != .removed
            )
        }
    }

    private mutating func sampleCurrentAnimationValue(
        value updateValue: inout (value: AnimatedValue, changed: Bool),
        fallbackValue: AnimatedValue?,
        fallbackTime now: Time
    ) {
        guard helper.isAnimating,
              let targetValue else {
            if let fallbackValue {
                finishValue(with: fallbackValue, at: now)
            }
            return
        }
        guard let update = helper.updateForCompletionRecords(
            value: &updateValue,
            environment: _environment
        ) else {
            if let fallbackValue {
                finishValue(with: fallbackValue, at: now)
            }
            return
        }
        let now = update.time
        let continuingCompletion:
            AnimatorState<AnimatedValue>.UpdateResult.ContinuingCompletion?
            = update.resolveCompletion(
                continuing: { .some($0) },
                terminal: { terminalCompletion in
                    finishTerminalAnimationSample(
                        terminalCompletion,
                        with: targetValue,
                        at: now
                    )
                    return nil
                }
            )
        guard let continuingCompletion else {
            return
        }
        let output = updateValue.value
        // Continuing samples may still complete logical criteria or
        // presentation-bound groups. State has already updated the listener
        // snapshot; the outer rule decides which copied records are due.
        if isCombinedFiniteCompletionGroupPresentationDue(at: now) {
            _AGGraph.setStatefulOutput(targetValue)
            let completions = finishCombinedFiniteCompletionGroup()
            enqueueAnimationCompletionActions(completions)
            return
        }
        if isNoAnimationRetargetPresentationDue(at: now) {
            finishAnimation(with: targetValue, at: now)
            return
        }
        // Side-effect layers can finish deferred nil/completion boundaries even
        // though they no longer drive the visible output. Sample them before
        // publishing the active output so they can clear grouped state first.
        if sampleSideEffectLayers(at: now) {
            return
        }
        _AGGraph.setStatefulOutput(output)
        if let velocityTrackingImmediateCompletionGroup {
            self.velocityTrackingImmediateCompletionGroup = nil
            samplingLayers.removeAll()
            let completions = finishCustomReplacementCompletionRecords(
                velocityTrackingImmediateCompletionGroup
            )
            enqueueAnimationCompletionActions(completions)
        }
        finishContinuingLogicalCompletionRecords(continuingCompletion, at: now)
        if isCombinedResidualCompletionGroupPresentationDue(at: now) {
            finishAnimation(with: targetValue, at: now)
            return
        }
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishTerminalAnimationSample(
        _ terminalCompletion: AnimatorState<AnimatedValue>.UpdateResult.TerminalCompletion,
        with targetValue: AnimatedValue,
        at now: Time
    ) {
        if shouldDeferTerminalAnimationSample(at: now) {
            _AGGraph.setStatefulOutput(targetValue)
            let completions = finishDueCompletionRecords(at: now)
            enqueueAnimationCompletionActions(completions)
            return
        }
        // Terminal samples let completion-record ordering own criteria
        // priority. Drained logical state tokens are still present in the
        // copied records, so finishing them directly from helper/state would
        // reorder the boundary.
        if isCombinedFiniteCompletionGroupReplacement(currentGeneration) {
            _AGGraph.setStatefulOutput(targetValue)
            let completions = finishCombinedFiniteCompletionGroup()
            enqueueAnimationCompletionActions(completions)
            return
        }
        if isCombinedResidualCompletionGroupReplacement(currentGeneration) {
            finishAnimation(
                with: targetValue,
                at: now,
                discardedBaseLayerGenerations:
                    terminalCompletion.discardedBaseLayerGenerations()
            )
            return
        }
        if isCustomReplacementCompletionGroupReplacement(currentGeneration) {
            _AGGraph.setStatefulOutput(targetValue)
            // The replacement nil boundary owns this handoff; discarded
            // side-effect layers should not be sampled again after it.
            let completions = finishCustomReplacementCompletionGroup(at: now)
            enqueueAnimationCompletionActions(completions)
            return
        }
        if isSourceCustomResidualReplacementCompletionGroupReplacement(currentGeneration) {
            let completions = finishSourceCustomResidualReplacementTerminal(
                with: targetValue,
                at: now
            )
            enqueueAnimationCompletionActions(completions)
            return
        }
        if isResidualWrapperReplacementCompletionGroupReplacement(currentGeneration) {
            finishAnimation(
                with: targetValue,
                at: now,
                discardedBaseLayerGenerations:
                    terminalCompletion.discardedBaseLayerGenerations()
            )
            return
        }
        let completions = finishTerminalCompletionRecords(
            matching: terminalCompletion,
            at: now
        )
        enqueueAnimationCompletionActions(completions)
        finishAnimation(
            with: targetValue,
            at: now,
            discardedBaseLayerGenerations:
                terminalCompletion.discardedBaseLayerGenerations()
        )
    }

    private mutating func shouldDeferTerminalAnimationSample(at now: Time) -> Bool {
        guard let deadline = deferredTerminalPresentationDeadline else {
            return false
        }
        if now.seconds < deadline.seconds {
            return true
        }
        deferredTerminalPresentationDeadline = nil
        return false
    }

    private mutating func finishContinuingLogicalCompletionRecords(
        _ continuingCompletion: AnimatorState<AnimatedValue>.UpdateResult.ContinuingCompletion,
        at now: Time
    ) {
        guard continuingCompletion.isReadyForLogicalCompletion(
            currentGeneration: currentGeneration,
            suppressedGenerations: contextLogicalCompletionSuppressedGenerations,
            deadlineOwnedGenerations: deadlineOwnedLogicalCompletionGenerations
        ),
              let currentGeneration else {
            return
        }

        var completions =
            finishCombinedResidualDueSourceLogicalBeforeReplacementLogicalIfNeeded(
                for: currentGeneration,
                at: now
            )
        if !hasPendingCombinedResidualSourceLogicalBeforeReplacement(
            for: currentGeneration
        ) {
            let prefersSourceLogicalBeforeReplacement =
                prefersCombinedResidualSourceLogicalBeforeReplacementLogical(
                    for: currentGeneration
                )
            if hasDueRemovedCompletionRecord(
                for: currentGeneration,
                at: now
            ) {
                enqueueAnimationCompletionActions(completions)
                return
            }
            completions.append(
                contentsOf: !continuingCompletion.hasLogicalCompletionListeners
                    ? finishCompletionRecords(
                        for: currentGeneration,
                        matching: {
                            $0.criteria != .removed &&
                            $0.orderGeneration == currentGeneration
                        }
                    )
                    : finishCompletionRecords(
                        matching: continuingCompletion,
                        preferLogicalBeforeRemoved: prefersSourceLogicalBeforeReplacement
                    )
            )
        }
        enqueueAnimationCompletionActions(completions)
    }

    private func hasDueRemovedCompletionRecord(
        for generation: UInt64,
        at now: Time
    ) -> Bool {
        completionRecords.contains {
            $0.generation == generation &&
                $0.criteria == .removed &&
                ($0.deadline < now || $0.deadline == now)
        }
    }

    mutating func destroy() {
        // Node removal is the last chance to finish listeners that were waiting
        // on this animatable value but no longer have a live output node.
        let teardownActiveGeneration = currentGeneration
        clearAnimationRuntimeState()
        let completions = finishAllCompletionRecords(
            teardownActiveGeneration: teardownActiveGeneration
        )
        enqueueAnimationCompletionActions(completions)
    }

    // Phase reset reaches this point after beginUpdate has already reset the
    // helper-owned animation state. The outer rule snaps the value and drains
    // only the copied completion records that remain in its sorter.
    private mutating func finishPhaseReset(with value: AnimatedValue, at now: Time) {
        startValue = nil
        targetValue = value
        helper.commitTarget(value)
        let teardownActiveGeneration = currentGeneration
        clearCompletionRecordSideState()
        nextGeneration = 1
        _AGGraph.setStatefulOutput(value)
        let completions = finishAllCompletionRecords(
            teardownActiveGeneration: teardownActiveGeneration
        )
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
        // A no-animation retarget keeps the existing animation clock but shifts
        // both endpoints by the target delta. The visible output follows the same
        // shift, avoiding a snap while the remaining animation samples.
        self.startValue = applying(delta: retargetDelta, to: startValue, target: target)
        let fallbackOutput = applying(delta: retargetDelta, to: currentOutput, target: target)
        targetValue = target
        if let adjustedStart = self.startValue {
            let interval = animatableDelta(from: adjustedStart, to: target)
            noAnimationRetargetPresentationDeadline =
                noAnimationRetargetPresentationDeadline(for: interval)
            helper.retargetWithoutAnimation(to: target, interval: interval)
        } else {
            noAnimationRetargetPresentationDeadline = nil
            helper.commitTarget(target)
        }
        return fallbackOutput
    }

    private func noAnimationRetargetPresentationDeadline(
        for interval: AnimatedValue.AnimatableData
    ) -> Time? {
        let defaultFinishingDefinition =
            AnimatedValue.self as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type
        let state = helper.interpolationStateSnapshot(
            defaultFinishingDefinition: defaultFinishingDefinition
        )
        guard let animation = state.animation,
              shouldForceNoAnimationRetargetPresentationDeadline(animation.box) else {
            return nil
        }

        let presentationDuration = animation.box.presentationDuration(for: interval)
        guard presentationDuration.isFinite else {
            return nil
        }
        return state.beginTime + presentationDuration
    }

    private func shouldForceNoAnimationRetargetPresentationDeadline(
        _ box: AnimationBoxBase
    ) -> Bool {
        box is DefaultAnimationBox ||
            box is FluidSpringAnimationBox ||
            hasResidualWrapperPresentation(box)
    }

    private func isNoAnimationRetargetPresentationDue(at now: Time) -> Bool {
        guard let deadline = noAnimationRetargetPresentationDeadline else {
            return false
        }
        return deadline < now || deadline == now
    }

    private mutating func finishValue(with value: AnimatedValue, at now: Time) {
        startValue = nil
        targetValue = value
        helper.commitTarget(value)
        clearAnimationRuntimeState()
        _AGGraph.setStatefulOutput(value)
        guard !completionRecords.isEmpty else { return }
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
        // Capture group state before runtime teardown. Clearing helper/state
        // storage must not erase the copied completion records that are about
        // to be ordered and drained below.
        clearAnimationRuntimeState(clearingGeneration: false)
        _AGGraph.setStatefulOutput(value)
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
        } else if let currentGeneration,
                  let residualWrapperGroup = residualWrapperReplacementCompletionGroup,
                  residualWrapperGroup.replacementGeneration == currentGeneration {
            completions = finishResidualWrapperReplacementCompletionRecords(
                residualWrapperGroup
            )
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
        let residualDeferredRemovedDeadline: Time?
        if currentDirectResidualAnimationHasSeparatePresentation(),
           helper.isAnimating,
           let currentGeneration {
            residualDeferredRemovedDeadline = completionRecords
                .filter {
                    $0.generation == currentGeneration &&
                        $0.criteria == .removed
                }
                .map(\.deadline)
                .min { $0.seconds < $1.seconds }
        } else {
            residualDeferredRemovedDeadline = nil
        }
        let sourceCustomResidualGroup = sourceCustomResidualReplacementCompletionGroup
        let residualWrapperReplacementGroup = residualWrapperReplacementCompletionGroup
        if let residualWrapperReplacementGroup,
           isResidualWrapperReplacementCompletionGroupReady(
            residualWrapperReplacementGroup,
            at: now
           ) {
            return finishResidualWrapperReplacementCompletionRecords(
                residualWrapperReplacementGroup
            )
        }
        let readyRecords = takeCompletionRecords { record in
            guard record.deadline < now || record.deadline == now else {
                return false
            }
            if let residualDeferredRemovedDeadline,
               record.deadline.seconds >= residualDeferredRemovedDeadline.seconds {
                return false
            }
            if Self.isResidualWrapperReplacementGroupRemovedRecord(
                record,
                group: residualWrapperReplacementGroup
            ) {
                return false
            }
            if Self.isSourceCustomResidualReplacementGroupRecord(
                record,
                group: sourceCustomResidualGroup
            ) {
                return false
            }
            return true
        }
        // Deadline selection only decides readiness; finishRecords applies the
        // criteria and generation ordering for the selected boundary.
        return finishRecords(readyRecords)
    }

    private func currentDirectResidualAnimationHasSeparatePresentation() -> Bool {
        let defaultFinishingDefinition =
            AnimatedValue.self as? any AnimationFinishingDefinition<AnimatedValue.AnimatableData>.Type
        let state = helper.interpolationStateSnapshot(
            defaultFinishingDefinition: defaultFinishingDefinition
        )
        guard let box = state.animation?.box,
              box.presentationDuration > box.duration else {
            return false
        }
        return box is DefaultAnimationBox ||
            box is FluidSpringAnimationBox ||
            box is SpringAnimationBox ||
            hasResidualWrapperPresentation(box)
    }

    private static func isSourceCustomResidualReplacementGroupRecord(
        _ record: CompletionRecord,
        group: SourceCustomResidualReplacementCompletionGroup?
    ) -> Bool {
        guard let group else {
            return false
        }
        return record.generation == group.replacementGeneration ||
            group.oldGenerations.contains(record.orderGeneration)
    }

    private static func isResidualWrapperReplacementGroupRemovedRecord(
        _ record: CompletionRecord,
        group: ResidualWrapperReplacementCompletionGroup?
    ) -> Bool {
        guard let group,
              record.criteria == .removed else {
            return false
        }
        return record.generation == group.replacementGeneration ||
            group.oldGenerations.contains(record.orderGeneration)
    }

    private mutating func finishAllCompletionRecords(
        teardownActiveGeneration: UInt64? = nil
    ) -> [() -> Void] {
        let records = takeAllCompletionRecords()
        guard let teardownActiveGeneration else {
            return finishRecords(records)
        }
        return finishTeardownCompletionRecords(
            records,
            activeGeneration: teardownActiveGeneration
        )
    }

    private mutating func finishCombinedResidualCompletionGroup(
        _ group: CombinedResidualCompletionGroup
    ) -> [() -> Void] {
        // Group finalization first partitions by old/replacement generation and
        // removed/logical criteria, then reassembles the sampled same-boundary
        // order for this replacement family.
        let groupRecords = takeCompletionGroupRecords(
            oldGenerations: Set(group.oldGenerations),
            replacementGeneration: group.replacementGeneration
        )
        let sourceBeforeReplacementGenerations =
            combinedResidualSourceLogicalBeforeReplacementGenerations(group)
        let sourceBeforeReplacementRecords = groupRecords.oldOtherRecords.filter {
            sourceBeforeReplacementGenerations.contains($0.orderGeneration)
        }
        let remainingOldOtherRecords = groupRecords.oldOtherRecords.filter {
            !sourceBeforeReplacementGenerations.contains($0.orderGeneration)
        }
        let orderedRecords: [CompletionRecord]
        if !sourceBeforeReplacementRecords.isEmpty {
            orderedRecords = sourceBeforeReplacementRecords +
                groupRecords.replacementOtherRecords +
                groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                remainingOldOtherRecords
        } else if group.prefersOldLogicalBeforeRemoved {
            orderedRecords = groupRecords.replacementOtherRecords +
                remainingOldOtherRecords +
                groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords
        } else if group.prefersReplacementLogicalBeforeRemoved &&
                    !groupRecords.replacementOtherRecords.isEmpty {
            orderedRecords = groupRecords.replacementOtherRecords +
                groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                remainingOldOtherRecords
        } else if groupRecords.replacementOtherRecords.isEmpty {
            // If the replacement logical record drained earlier, residual
            // finalization only owns removed records plus remaining source
            // logical records.
            orderedRecords = groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                remainingOldOtherRecords
        } else {
            // Same-boundary residual families drain removed records before
            // logical records at finalization.
            orderedRecords = groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                groupRecords.replacementOtherRecords +
                remainingOldOtherRecords
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
        // Finite combined replacements drain old teardown before replacement
        // teardown, then logical records, while leaving unrelated generations
        // pending in the sorter.
        let groupRecords = takeCompletionGroupRecords(
            oldGenerations: group.oldGenerations,
            replacementGeneration: group.replacementGeneration
        )
        let orderedRecords = groupRecords.oldRemovedRecords +
            groupRecords.replacementRemovedRecords +
            groupRecords.replacementOtherRecords +
            groupRecords.oldOtherRecords
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
        let readyRecords = takeCompletionRecords { record in
            generations.contains(record.generation) && predicate(record)
        }
        return finishRecords(readyRecords)
    }

    private mutating func finishTerminalCompletionRecords(
        matching terminalCompletion: AnimatorState<AnimatedValue>.UpdateResult.TerminalCompletion,
        at now: Time
    ) -> [() -> Void] {
        let readyRecords = takeCompletionRecords { record in
            record.isMatched(by: terminalCompletion) ||
                record.deadline < now ||
                record.deadline == now
        }
        return finishRecords(readyRecords)
    }

    private mutating func finishCompletionRecords(
        matching continuingCompletion: AnimatorState<AnimatedValue>.UpdateResult.ContinuingCompletion,
        preferLogicalBeforeRemoved: Bool
    ) -> [() -> Void] {
        let deadlineOwnedOrderGenerations = deadlineOwnedLogicalCompletionOrderGenerations
        let readyRecords = takeCompletionRecords { record in
            record.isMatched(by: continuingCompletion) &&
                !deadlineOwnedOrderGenerations.contains(record.orderGeneration)
        }
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
        let readyRecords = takeCompletionRecords { record in
            record.generation == generation && predicate(record)
        }
        return finishRecords(
            readyRecords,
            preferLogicalBeforeRemoved: preferLogicalBeforeRemoved
        )
    }

    private mutating func finishInfiniteCompletionRecords(for generations: Set<UInt64>) -> [() -> Void] {
        guard !generations.isEmpty else { return [] }

        let readyRecords = takeCompletionRecords { record in
            generations.contains(record.generation) && !record.deadline.seconds.isFinite
        }
        return finishRecords(readyRecords)
    }

    private mutating func takeAllCompletionRecords() -> [CompletionRecord] {
        let records = completionRecords
        completionRecords.removeAll()
        return records
    }

    private mutating func takeCompletionRecords(
        matching predicate: (CompletionRecord) -> Bool
    ) -> [CompletionRecord] {
        var readyRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if predicate(record) {
                readyRecords.append(record)
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return readyRecords
    }

    private mutating func takeCompletionGroupRecords(
        oldGenerations: Set<UInt64>,
        replacementGeneration: UInt64
    ) -> CompletionGroupRecords {
        var oldRemovedRecords: [CompletionRecord] = []
        var replacementRemovedRecords: [CompletionRecord] = []
        var replacementOtherRecords: [CompletionRecord] = []
        var oldOtherRecords: [CompletionRecord] = []
        var pendingRecords: [CompletionRecord] = []

        for record in completionRecords {
            if oldGenerations.contains(record.orderGeneration) {
                if record.criteria == .removed {
                    oldRemovedRecords.append(record)
                } else {
                    oldOtherRecords.append(record)
                }
            } else if record.generation == replacementGeneration {
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
        return CompletionGroupRecords(
            oldRemovedRecords: oldRemovedRecords,
            replacementRemovedRecords: replacementRemovedRecords,
            replacementOtherRecords: replacementOtherRecords,
            oldOtherRecords: oldOtherRecords
        )
    }

    private func finishRecords(
        _ records: [CompletionRecord],
        preferLogicalBeforeRemoved: Bool = false
    ) -> [() -> Void] {
        // Default ordering treats removed callbacks as teardown in
        // oldest-generation order, then logical callbacks in newest-generation
        // order. Some grouped boundaries opt into logical-before-removed.
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
        let indexedOtherRecords = indexedRecords
            .filter { $0.element.criteria != .removed }
        let ordersOtherRecordsOldToNew =
            !indexedOtherRecords.isEmpty &&
            indexedOtherRecords.allSatisfy(\.element.prefersOldToNewLogicalOrder)
        let otherRecords = indexedOtherRecords
            .sorted {
                if $0.element.orderGeneration != $1.element.orderGeneration {
                    return ordersOtherRecordsOldToNew
                        ? $0.element.orderGeneration < $1.element.orderGeneration
                        : $0.element.orderGeneration > $1.element.orderGeneration
                }
                return $0.offset < $1.offset
            }
            .map { $0.element }
        return (removedRecords + otherRecords).flatMap { $0.finish() }
    }

    private func finishTeardownCompletionRecords(
        _ records: [CompletionRecord],
        activeGeneration: UInt64
    ) -> [() -> Void] {
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
                let lhsIsActive = $0.element.orderGeneration == activeGeneration
                let rhsIsActive = $1.element.orderGeneration == activeGeneration
                if lhsIsActive != rhsIsActive {
                    return lhsIsActive
                }
                if $0.element.orderGeneration != $1.element.orderGeneration {
                    return $0.element.orderGeneration < $1.element.orderGeneration
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
            return _AGGraph.currentStatefulOutput()
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

        // Side-effect layers no longer drive the output. They are sampled only
        // to reach listener/completion boundaries carried by interrupted
        // animations.
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
            // Each layer samples from the previous layer's result, matching the
            // stacked presentation path used while retargeting.
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
            let ownsLogicalDeadline =
                deadlineOwnedLogicalCompletionOrderGenerations.contains(layer.generation)
            if context.isLogicallyComplete {
                if !contextLogicalCompletionSuppressedGenerations.contains(layer.generation),
                   !ownsLogicalDeadline,
                   !shouldHoldCombinedResidualSourceLogicalUntilFinalization(layer.generation) {
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
                if isSourceCustomResidualReplacementCompletionGroupOldGeneration(layer.generation) {
                    var completions = finishCompletionRecords(for: layer.generation) {
                        if ownsLogicalDeadline, $0.criteria != .removed {
                            return $0.deadline < now || $0.deadline == now
                        }
                        return $0.criteria != .removed
                    }
                    completions.append(
                        contentsOf: markSourceCustomResidualReplacementOldGenerationComplete(
                            layer.generation
                        )
                    )
                    enqueueAnimationCompletionActions(completions)
                    continue
                }
                if isDeferredCompletionGroupOldGeneration(layer.generation) {
                    if !ownsLogicalDeadline,
                       !shouldHoldCombinedResidualSourceLogicalUntilFinalization(layer.generation) {
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
                    continue
                }
                let completions = finishCompletionRecords(for: layer.generation) {
                    if ownsLogicalDeadline, $0.criteria != .removed {
                        return $0.deadline < now || $0.deadline == now
                    }
                    return $0.criteria != .removed ||
                        $0.deadline < now ||
                        $0.deadline == now
                }
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

    private func isSourceCustomResidualReplacementCompletionGroupReplacement(
        _ generation: UInt64?
    ) -> Bool {
        guard let generation,
              let group = sourceCustomResidualReplacementCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
    }

    private func isResidualWrapperReplacementCompletionGroupReplacement(
        _ generation: UInt64?
    ) -> Bool {
        guard let generation,
              let group = residualWrapperReplacementCompletionGroup else {
            return false
        }
        return group.replacementGeneration == generation
    }

    private func isSourceCustomResidualReplacementCompletionGroupOldGeneration(
        _ generation: UInt64
    ) -> Bool {
        sourceCustomResidualReplacementCompletionGroup?.oldGenerations.contains(generation) ?? false
    }

    private func isDeferredCompletionGroupOldGeneration(_ generation: UInt64) -> Bool {
        isCustomReplacementCompletionGroupOldGeneration(generation) ||
            isSourceCustomResidualReplacementCompletionGroupOldGeneration(generation) ||
            (residualWrapperReplacementCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (combinedFiniteCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (combinedResidualCompletionGroup?.oldGenerations.contains(generation) ?? false) ||
            (velocityTrackingImmediateCompletionGroup?.oldGenerations.contains(generation) ?? false)
    }

    private func shouldHoldCombinedResidualSourceLogicalUntilFinalization(
        _ generation: UInt64
    ) -> Bool {
        guard let group = combinedResidualCompletionGroup,
              group.holdsSourceLogicalUntilFinalization else {
            return false
        }
        return group.oldGenerations.contains(generation)
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
        let sourceBeforeReplacementGenerations =
            combinedResidualSourceLogicalBeforeReplacementGenerations(group)
        let readyRecords = takeCompletionRecords { record in
            sourceBeforeReplacementGenerations.contains(record.orderGeneration) &&
                record.criteria != .removed &&
                (record.deadline < now || record.deadline == now)
        }
        return finishRecords(readyRecords, preferLogicalBeforeRemoved: true)
    }

    private func hasPendingCombinedResidualSourceLogicalBeforeReplacement(
        for generation: UInt64
    ) -> Bool {
        guard let group = combinedResidualCompletionGroup,
              group.replacementGeneration == generation else {
            return false
        }
        let sourceBeforeReplacementGenerations =
            combinedResidualSourceLogicalBeforeReplacementGenerations(group)
        return completionRecords.contains {
            sourceBeforeReplacementGenerations.contains($0.orderGeneration) &&
                $0.criteria != .removed
        }
    }

    private func combinedResidualSourceLogicalBeforeReplacementGenerations(
        _ group: CombinedResidualCompletionGroup
    ) -> Set<UInt64> {
        guard group.prefersSourceLogicalBeforeReplacement,
              !group.prefersReplacementLogicalBeforeSourceLogical,
              group.oldGenerations.count > 1 else {
            return []
        }
        // A combined source stack can have one interrupted child that reaches
        // its logical boundary before the residual replacement. Older and later
        // source children stay grouped with the final teardown boundary.
        return [group.oldGenerations[1]]
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

    private mutating func finishSourceCustomResidualReplacementTerminal(
        with value: AnimatedValue,
        at now: Time
    ) -> [() -> Void] {
        _ = now
        startValue = nil
        targetValue = value
        helper.commitTarget(value)
        helper.clearAnimatorStateStorageForCompletionRecords()
        currentGeneration = nil
        _AGGraph.setStatefulOutput(value)

        guard var group = sourceCustomResidualReplacementCompletionGroup else {
            return []
        }
        group.didReachReplacementTerminal = true
        sourceCustomResidualReplacementCompletionGroup = group

        var completions = finishCompletionRecords(for: group.replacementGeneration) {
            $0.criteria != .removed &&
                $0.orderGeneration == group.replacementGeneration
        }
        completions.append(contentsOf: finishSourceCustomResidualReplacementGroupIfReady())
        return completions
    }

    private mutating func markSourceCustomResidualReplacementOldGenerationComplete(
        _ generation: UInt64
    ) -> [() -> Void] {
        guard var group = sourceCustomResidualReplacementCompletionGroup,
              group.oldGenerations.contains(generation) else {
            return []
        }
        group.completedOldGenerations.insert(generation)
        sourceCustomResidualReplacementCompletionGroup = group
        return finishSourceCustomResidualReplacementGroupIfReady()
    }

    private mutating func finishSourceCustomResidualReplacementGroupIfReady() -> [() -> Void] {
        guard let group = sourceCustomResidualReplacementCompletionGroup,
              group.isReadyToFinish else {
            return []
        }
        sourceCustomResidualReplacementCompletionGroup = nil
        samplingLayers.removeAll()
        let groupRecords = takeCompletionGroupRecords(
            oldGenerations: group.oldGenerations,
            replacementGeneration: group.replacementGeneration
        )
        let orderedRecords = groupRecords.oldRemovedRecords +
            groupRecords.replacementRemovedRecords +
            groupRecords.replacementOtherRecords +
            groupRecords.oldOtherRecords
        return orderedRecords.flatMap { $0.finish() }
    }

    private mutating func finishResidualWrapperReplacementCompletionRecords(
        _ group: ResidualWrapperReplacementCompletionGroup
    ) -> [() -> Void] {
        residualWrapperReplacementCompletionGroup = nil
        let groupRecords = takeCompletionGroupRecords(
            oldGenerations: group.oldGenerations,
            replacementGeneration: group.replacementGeneration
        )
        let orderedRecords = groupRecords.replacementOtherRecords +
            groupRecords.oldOtherRecords +
            groupRecords.oldRemovedRecords +
            groupRecords.replacementRemovedRecords
        return orderedRecords.flatMap { $0.finish() }
    }

    private func isResidualWrapperReplacementCompletionGroupReady(
        _ group: ResidualWrapperReplacementCompletionGroup,
        at now: Time
    ) -> Bool {
        var hasDueReplacementRemovedRecord = false
        for record in completionRecords {
            if record.generation == group.replacementGeneration,
               record.criteria == .removed,
               record.deadline < now || record.deadline == now {
                hasDueReplacementRemovedRecord = true
            }
            if group.oldGenerations.contains(record.orderGeneration),
               record.criteria != .removed,
               record.deadline.seconds > now.seconds {
                return false
            }
        }
        return hasDueReplacementRemovedRecord
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
            _AGGraph.setStatefulOutput(finalValue)
        }
        clearAnimationRuntimeState()

        return finishCustomReplacementCompletionRecords(group)
    }

    private mutating func finishCustomReplacementCompletionRecords(
        _ group: CustomReplacementCompletionGroup
    ) -> [() -> Void] {
        // Custom replacement groups pair the replacement generation with one or
        // more old presentation generations. Old teardown normally owns the
        // boundary; wrapper families can opt into replacement logical first.
        let groupRecords = takeCompletionGroupRecords(
            oldGenerations: group.oldGenerations,
            replacementGeneration: group.replacementGeneration
        )
        let pendingOldLogicalGenerations = Set(groupRecords.oldOtherRecords.map(\.orderGeneration))
        let ownsAllOldLogicalRecords = group.oldGenerations.isSubset(
            of: pendingOldLogicalGenerations
        )
        let orderedRecords: [CompletionRecord]
        if group.prefersOldLogicalBeforeReplacement &&
            ownsAllOldLogicalRecords {
            orderedRecords = groupRecords.oldRemovedRecords +
                groupRecords.oldOtherRecords +
                groupRecords.replacementRemovedRecords +
                groupRecords.replacementOtherRecords
        } else if group.prefersReplacementLogicalBeforeRemoved &&
            ownsAllOldLogicalRecords &&
            !groupRecords.replacementOtherRecords.isEmpty {
            orderedRecords = groupRecords.replacementOtherRecords +
                groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                groupRecords.oldOtherRecords
        } else {
            orderedRecords = groupRecords.oldRemovedRecords +
                groupRecords.replacementRemovedRecords +
                groupRecords.replacementOtherRecords +
                groupRecords.oldOtherRecords
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
        // The routing predicates below stay deliberately narrow and family
        // named. Completion ordering depends on sampled handoff classes, not on
        // duration alone, so a broad helper would hide important boundaries.
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

    private func shouldRestartVelocityTrackingPresentationAtCurrentOutput(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        return isVelocityTrackingAnimation(previousAnimation.box) &&
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
        hasLayerStackConversion: Bool,
        usesWrapperLocalFiniteReplacementPresentation: Bool
    ) -> Bool {
        !merged &&
            previousAnimation != nil &&
            !usesWrapperLocalFiniteReplacementPresentation &&
            (!hasBaseLayers || hasLayerStackConversion)
    }

    private func shouldUseWrapperLocalFiniteReplacementPresentation(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        if previousAnimation.box is DefaultAnimationBox,
           isFiniteNonResidualWrapper(replacementAnimation.box) {
            return true
        }
        if previousAnimation.box is SpringAnimationBox ||
           previousAnimation.box is DefaultAnimationBox {
            return false
        }
        return previousAnimation.box.presentationDuration > previousAnimation.box.duration &&
            isFiniteNonResidualAnimation(replacementAnimation.box)
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

    private func shouldHoldSourceCustomCompletionRecordsUntilResidualWrapperSideEffectNil(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard shouldMoveSourceCustomCompletionRecordsToFiniteReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: replacementAnimation
        ) else {
            return false
        }
        return hasResidualWrapperPresentation(replacementAnimation.box)
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

    private func resolvedCompletionPresentationDuration(
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        previousSamplingLayers: [AnimationLayer],
        valuePresentationDuration: TimeInterval
    ) -> TimeInterval {
        guard let fluidSpring = replacementAnimation.box as? FluidSpringAnimationBox,
              isSampledDurationBounceFluidSpringSameBoundaryAlias(fluidSpring),
              hasDirectRepeatForeverSource(
                previousAnimation: previousAnimation,
                previousSamplingLayers: previousSamplingLayers
              ) else {
            return valuePresentationDuration
        }
        return max(valuePresentationDuration, replacementAnimation.box.presentationDuration)
    }

    private func shouldHoldCombinedResidualReplacementLogicalUntilFinalization(
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        previousSamplingLayers: [AnimationLayer],
        value: AnimatedValue.AnimatableData
    ) -> Bool {
        guard let fluidSpring = replacementAnimation.box as? FluidSpringAnimationBox else {
            return false
        }
        guard fluidSpring.reachesTargetAtLogicalDuration(for: value) else {
            return false
        }
        if isSampledDurationBounceFluidSpringSameBoundaryAlias(fluidSpring),
           hasDirectRepeatForeverSource(
            previousAnimation: previousAnimation,
            previousSamplingLayers: previousSamplingLayers
           ) {
            return false
        }
        return true
    }

    private func shouldCompleteCombinedResidualLogicalWrapperAtActivation(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation,
              isDefaultCombiningAnimation(previousAnimation.box),
              let logicalCompletion = replacementAnimation.box as? LogicalCompletionAnimationBox else {
            return false
        }
        return logicalCompletion.base is DefaultAnimationBox ||
            logicalCompletion.base is FluidSpringAnimationBox
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
        let replacementBox = logicalCompletionBase(replacementAnimation.box)
        guard replacementBox is DefaultAnimationBox ||
              replacementBox is FluidSpringAnimationBox else {
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
        // This classifier is intentionally direct-wrapper only. Nested
        // delay/speed/repeat combinations have separate ordering families below,
        // and folding them into this path would steal source-logical callbacks
        // from their sampled residual boundary.
        if let delay = box as? DelayAnimationBox {
            guard delay.delay >= 0 else { return false }
            return isNonInteractiveFluidSpringAlias(delay.base)
        }
        if let speed = box as? SpeedAnimationBox {
            guard speed.speed > 0 else { return false }
            return isNonInteractiveFluidSpringAlias(speed.base)
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

    private func shouldFinishCombinedResidualSourceLogicalBeforeReplacement(
        replacementAnimation: Animation
    ) -> Bool {
        let replacementBox = logicalCompletionBase(replacementAnimation.box)
        if replacementBox is DefaultAnimationBox ||
           replacementBox is SpringAnimationBox {
            return true
        }
        if let fluidSpring = replacementBox as? FluidSpringAnimationBox {
            return !isResidualFirstDirectFluidSpringAlias(fluidSpring)
        }
        return shouldFinishCombinedResidualSourceLogicalBeforeRemoved(
            replacementAnimation: replacementAnimation
        )
    }

    private func shouldFinishCombinedResidualReplacementLogicalBeforeRemoved(
        replacementAnimation: Animation
    ) -> Bool {
        let replacementBox = logicalCompletionBase(replacementAnimation.box)
        return hasSpringAnimationBase(replacementBox) ||
            shouldFinishDirectFluidSpringReplacementLogicalBeforeRemoved(replacementBox) ||
            isSpringPropertyFluidSpringAlias(replacementBox) ||
            hasResidualWrapperPresentation(replacementBox)
    }

    private func logicalCompletionBase(_ box: AnimationBoxBase) -> AnimationBoxBase {
        if let logicalCompletion = box as? LogicalCompletionAnimationBox {
            return logicalCompletion.base
        }
        return box
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

    private func hasDirectRepeatForeverSource(
        previousAnimation: Animation?,
        previousSamplingLayers: [AnimationLayer]
    ) -> Bool {
        if let previousAnimation,
           containsDirectRepeatForeverAnimation(previousAnimation.box) {
            return true
        }
        return previousSamplingLayers.contains {
            containsDirectRepeatForeverAnimation($0.animation.box)
        }
    }

    private func containsDirectRepeatForeverAnimation(_ box: AnimationBoxBase) -> Bool {
        if isDirectRepeatForeverAnimation(box) {
            return true
        }
        if let combinedBox = box as? CustomAnimationBox<DefaultCombiningAnimation> {
            return combinedBox.base.entries.contains {
                containsDirectRepeatForeverAnimation($0.animation.box)
            }
        }
        return false
    }

    private func isDirectRepeatForeverAnimation(_ box: AnimationBoxBase) -> Bool {
        guard let repeatBox = box as? RepeatAnimationBox else {
            return false
        }
        return repeatBox.repeatCount == nil
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 1.0e-9
    }

    private func shouldFinishCombinedResidualReplacementLogicalBeforeSourceLogical(
        replacementAnimation: Animation
    ) -> Bool {
        let replacementBox = logicalCompletionBase(replacementAnimation.box)
        if let fluidSpring = replacementBox as? FluidSpringAnimationBox {
            return isResidualFirstDirectFluidSpringAlias(fluidSpring)
        }
        return isCombinedResidualReplacementLogicalBeforeSourceWrapper(replacementBox)
    }

    private func shouldHoldCombinedResidualSourceLogicalUntilFinalization(
        replacementAnimation: Animation
    ) -> Bool {
        guard let fluidSpring = replacementAnimation.box as? FluidSpringAnimationBox else {
            return false
        }
        return isResidualFirstDirectFluidSpringAlias(fluidSpring)
    }

    private func isCombinedResidualOldSourceLogicalBeforeRemovedWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let logicalCompletion = box as? LogicalCompletionAnimationBox {
            return logicalCompletion.base.presentationDuration > logicalCompletion.base.duration &&
                hasCombinedResidualLogicalCompletionOldSourceBeforeRemovedBase(logicalCompletion.base)
        }
        guard hasResidualWrapperPresentation(box) else {
            return false
        }
        if isResidualFirstNestedSpeedRepeatWrapper(box) ||
           isResidualFirstNestedDelaySpeedWrapper(box) {
            return false
        }
        return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(box)
    }

    private func hasCombinedResidualOldSourceLogicalBeforeRemovedBase(
        _ box: AnimationBoxBase
    ) -> Bool {
        // Walk only through wrappers that preserve the old-source logical
        // boundary. Nested speed/repeat and delay/speed exceptions are filtered
        // by the caller before this recursive base check.
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
            if let spring = speed.base as? SpringAnimationBox {
                return spring.usesMassStiffnessDampingWrapperOrdering
            }
            return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(speed.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            return hasCombinedResidualOldSourceLogicalBeforeRemovedRepeatBase(repeatBox)
        }
        return false
    }

    private func hasCombinedResidualLogicalCompletionOldSourceBeforeRemovedBase(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let fluidSpring = box as? FluidSpringAnimationBox,
           isSampledSnappyDurationFluidSpringLogicalCompletionAlias(fluidSpring) {
            return false
        }
        return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(box)
    }

    private func isSampledSnappyDurationFluidSpringLogicalCompletionAlias(
        _ box: FluidSpringAnimationBox
    ) -> Bool {
        approximatelyEqual(box.response, 0.45) &&
            approximatelyEqual(box.dampingFraction, 0.85) &&
            approximatelyEqual(box.blendDuration, 0)
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
            return repeatCount >= 0 &&
                (
                    !isInteractiveFluidSpringAlias(fluidSpring) ||
                    isDefaultDurationInteractiveFluidSpringAlias(fluidSpring)
                )
        }
        if repeatCount > 0,
           hasSpringAnimationBaseThroughDelayRepeat(repeatBox.base) {
            return true
        }
        return hasCombinedResidualOldSourceLogicalBeforeRemovedBase(repeatBox.base)
    }

    private func isResidualFirstNestedSpeedRepeatWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let repeatBox = box as? RepeatAnimationBox,
           repeatBox.repeatCount != nil,
           let speed = repeatBox.base as? SpeedAnimationBox,
           speed.speed > 0 {
            return isNonInteractiveFluidSpringAlias(speed.base) ||
                speed.base is SpringAnimationBox
        }
        if let speed = box as? SpeedAnimationBox,
           speed.speed > 0,
           let repeatBox = speed.base as? RepeatAnimationBox,
           repeatBox.repeatCount != nil {
            return isNonInteractiveFluidSpringAlias(repeatBox.base) ||
                repeatBox.base is SpringAnimationBox
        }
        return false
    }

    private func isResidualFirstNestedDelaySpeedWrapper(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let delay = box as? DelayAnimationBox,
           delay.delay >= 0,
           let speed = delay.base as? SpeedAnimationBox,
           speed.speed > 0 {
            return isResidualFirstNestedDelaySpeedBase(speed.base)
        }
        if let speed = box as? SpeedAnimationBox,
           speed.speed > 0,
           let delay = speed.base as? DelayAnimationBox,
           delay.delay >= 0 {
            return isResidualFirstNestedDelaySpeedBase(delay.base)
        }
        return false
    }

    private func isResidualFirstNestedDelaySpeedBase(
        _ box: AnimationBoxBase
    ) -> Bool {
        if box is DefaultAnimationBox {
            return true
        }
        if let fluidSpring = box as? FluidSpringAnimationBox {
            return !isInteractiveFluidSpringAlias(fluidSpring)
        }
        if let spring = box as? SpringAnimationBox {
            return spring.usesMassStiffnessDampingWrapperOrdering
        }
        return false
    }

    private func hasSpringAnimationBaseThroughDelayRepeat(
        _ box: AnimationBoxBase
    ) -> Bool {
        if let spring = box as? SpringAnimationBox {
            return spring.usesMassStiffnessDampingWrapperOrdering
        }
        if let delay = box as? DelayAnimationBox {
            guard delay.delay >= 0 else { return false }
            return hasSpringAnimationBaseThroughDelayRepeat(delay.base)
        }
        if let repeatBox = box as? RepeatAnimationBox {
            guard let repeatCount = repeatBox.repeatCount,
                  repeatCount > 0 else {
                return false
            }
            return hasSpringAnimationBaseThroughDelayRepeat(repeatBox.base)
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

    private func shouldOrderFixedAliasLogicalRecordsOldToNew(
        animation: Animation,
        registration: AnimatorState<AnimatedValue>.ListenerRegistration
    ) -> Bool {
        guard isFixedDurationLogicalOrderAlias(animation.box) else {
            return false
        }
        let criteria = registration.mapRecords(\.criteria)
        return criteria.contains(.logicallyComplete) &&
            !criteria.contains(.removed)
    }

    private func isFixedDurationLogicalOrderAlias(_ box: AnimationBoxBase) -> Bool {
        isFixedDurationBezierAlias(box) ||
            isFixedDurationFluidSpringAlias(box)
    }

    private func isFixedDurationBezierAlias(_ box: AnimationBoxBase) -> Bool {
        guard let bezier = box as? BezierAnimationBox else {
            return false
        }
        return approximatelyEqual(bezier.storedDuration, 0.35)
    }

    private func isFixedDurationFluidSpringAlias(_ box: AnimationBoxBase) -> Bool {
        guard let fluidSpring = box as? FluidSpringAnimationBox else {
            return false
        }
        return isSpringPropertyFluidSpringAlias(box) ||
            isDefaultDurationInteractiveFluidSpringAlias(fluidSpring)
    }

    private func isResidualFirstDirectFluidSpringAlias(
        _ box: FluidSpringAnimationBox
    ) -> Bool {
        isInteractiveFluidSpringAlias(box) ||
            isDurationBasedInteractiveFluidSpringAlias(box)
    }

    private func isDurationBasedInteractiveFluidSpringAlias(
        _ box: FluidSpringAnimationBox
    ) -> Bool {
        approximatelyEqual(box.response, 0.5) &&
            approximatelyEqual(box.blendDuration, 0) &&
            box.dampingFraction < 0.8
    }

    private func isDefaultDurationInteractiveFluidSpringAlias(
        _ box: FluidSpringAnimationBox
    ) -> Bool {
        approximatelyEqual(box.response, 0.15) &&
            approximatelyEqual(box.dampingFraction, 0.85) &&
            approximatelyEqual(box.blendDuration, 0.25)
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

    private func shouldMoveResidualWrapperLogicalCompletionRecordsToSourceCustomReplacement(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard shouldMoveResidualWrapperCompletionRecordsToSourceCustomReplacement(
            previousAnimation: previousAnimation,
            replacementAnimation: replacementAnimation
        ), let previousAnimation else {
            return false
        }
        return isDirectSpringSpeedResidualWrapper(previousAnimation.box)
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

    private func shouldPreserveDirectBezierOrFluidSpringLogicalOnlyForkDeadline(
        record: CompletionRecord,
        previousAnimation: Animation?,
        replacementAnimation: Animation,
        replacementBoundary: Time,
        removedOrderGenerations: Set<UInt64>
    ) -> Bool {
        guard record.criteria != .removed,
              !removedOrderGenerations.contains(record.orderGeneration),
              let previousAnimation,
              replacementAnimation.box is FluidSpringAnimationBox else {
            return false
        }
        // A logical-only direct lane keeps its own completion boundary while
        // the replacement spring begins from the sampled presentation value.
        if previousAnimation.box is FluidSpringAnimationBox {
            return true
        }
        return previousAnimation.box is BezierAnimationBox &&
            record.deadline.seconds <= replacementBoundary.seconds
    }

    private func shouldGroupResidualWrapperReplacementCompletionRecords(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation,
              hasResidualWrapperPresentation(replacementAnimation.box) else {
            return false
        }
        return previousAnimation.box is DefaultAnimationBox ||
            previousAnimation.box is FluidSpringAnimationBox ||
            previousAnimation.box is SpringAnimationBox
    }

    private func shouldMovePlainFiniteCompletionRecordsToReplacementBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        guard !shouldHoldFiniteRepeatForkCompletionRecordsForNewestRepeatBoundary(
            previousAnimation: previousAnimation,
            replacementAnimation: replacementAnimation
        ) else {
            return false
        }
        return isFiniteNonResidualAnimation(previousAnimation.box) &&
            isFiniteNonResidualAnimation(replacementAnimation.box)
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
        if isFiniteNonResidualAnimation(previousAnimation.box),
           isFiniteNonResidualAnimation(replacementAnimation.box) {
            return false
        }
        if !previousAnimation.box.duration.isFinite {
            return true
        }
        if previousAnimation.box is FluidSpringAnimationBox,
           replacementAnimation.box.presentationDuration == replacementAnimation.box.duration {
            return true
        }
        return false
    }

    private func shouldHoldFiniteRepeatForkCompletionRecordsForNewestRepeatBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation else { return false }
        if isDefaultCombiningAnimation(previousAnimation.box) {
            return isFiniteRepeatDelayedWrapper(replacementAnimation.box)
        }
        return containsFiniteNonResidualRepeat(previousAnimation.box) &&
            containsFiniteNonResidualRepeat(replacementAnimation.box)
    }

    private func shouldReleaseHeldFiniteRepeatForkCompletionRecordsAtNewestRepeatBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation,
              containsFiniteNonResidualRepeat(replacementAnimation.box) else {
            return false
        }
        return containsFiniteNonResidualRepeat(previousAnimation.box)
    }

    private func shouldMoveHeldOlderFiniteRepeatForkCompletionRecordsToFiniteReplacementBoundary(
        previousAnimation: Animation?,
        replacementAnimation: Animation
    ) -> Bool {
        guard let previousAnimation,
              !deadlineOwnedLogicalCompletionOrderGenerations.isEmpty,
              containsFiniteNonResidualRepeat(previousAnimation.box),
              isDirectFiniteCurveAnimation(replacementAnimation.box) else {
            return false
        }
        return true
    }

    private func isDirectFiniteCurveAnimation(_ box: AnimationBoxBase) -> Bool {
        box is BezierAnimationBox || box is UnitCurveAnimationBox
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

    private func isDirectSpringSpeedResidualWrapper(_ box: AnimationBoxBase) -> Bool {
        guard let speed = box as? SpeedAnimationBox,
              speed.speed > 0,
              let spring = speed.base as? SpringAnimationBox,
              spring.usesMassStiffnessDampingWrapperOrdering else {
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

    private func isFiniteRepeatDelayedWrapper(_ box: AnimationBoxBase) -> Bool {
        guard let delayBox = box as? DelayAnimationBox,
              delayBox.duration.isFinite,
              delayBox.presentationDuration == delayBox.duration else {
            return false
        }
        return containsFiniteNonResidualRepeat(delayBox.base)
    }

    private func containsFiniteNonResidualRepeat(_ box: AnimationBoxBase) -> Bool {
        if isFiniteNonResidualRepeat(box) {
            return true
        }
        if let delayBox = box as? DelayAnimationBox {
            return containsFiniteNonResidualRepeat(delayBox.base)
        }
        if let speedBox = box as? SpeedAnimationBox {
            return containsFiniteNonResidualRepeat(speedBox.base)
        }
        if let combinedBox = box as? CustomAnimationBox<DefaultCombiningAnimation> {
            return combinedBox.base.entries.contains {
                containsFiniteNonResidualRepeat($0.animation.box)
            }
        }
        return false
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
