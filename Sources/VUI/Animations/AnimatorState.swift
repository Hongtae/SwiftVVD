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

final class AnimatorState<Value: VectorArithmetic> {
    private enum Phase {
        case pending
        case first
        case second
        case running
    }

    private struct Fork {
        var animation: Animation
        var state: AnimationState<Value>
        var interval: Value
        var finishingDefinition: (any AnimationFinishingDefinition<Value>.Type)?
        var listeners: [AnimationListener]

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
            let output = animation.box.animate(
                value: interval,
                time: time.seconds,
                context: &context
            )
            return output == nil || context.isLogicallyComplete
        }
    }

    private var animation: Animation
    private var state: AnimationState<Value>
    private var interval: Value
    private var beginTime: Time
    private var quantizedFrameInterval: TimeInterval
    private var nextTime: Time
    private var previousAnimationValue: Value
    private var reason: UInt32?
    private var phase: Phase
    private var listeners: [AnimationListener]
    private var logicalListeners: [AnimationListener]
    private var isLogicallyComplete: Bool
    private var finishingDefinition: (any AnimationFinishingDefinition<Value>.Type)?
    private var forks: [Fork]

    init(
        animation: Animation,
        interval: Value,
        at time: Time,
        in transaction: Transaction,
        finishingDefinition: (any AnimationFinishingDefinition<Value>.Type)? = nil
    ) {
        self.animation = animation
        self.state = AnimationState()
        self.interval = interval
        self.beginTime = time
        self.quantizedFrameInterval = 0
        self.nextTime = time
        self.previousAnimationValue = .zero
        self.reason = transaction.animationReason
        self.phase = .pending
        self.listeners = []
        self.logicalListeners = []
        self.isLogicallyComplete = false
        self.finishingDefinition = finishingDefinition
        self.forks = []
        updateFrameInterval(from: transaction)
    }

    func combine(
        newAnimation: Animation,
        newInterval: Value,
        at time: Time,
        in transaction: Transaction,
        environment: Attribute<EnvironmentValues>?
    ) {
        if phase == .pending {
            animation = newAnimation
            interval = newInterval
            refreshScheduling(at: time, from: transaction)
            return
        }

        let elapsed = time.seconds - beginTime.seconds
        var context = makeAnimationContext(
            state: state,
            isLogicallyComplete: false,
            environment: resolvedAnimationEnvironment(environment),
            finishingDefinition: finishingDefinition
        )
        forkListeners(
            animation: animation,
            state: state,
            interval: interval
        )
        isLogicallyComplete = false

        if newAnimation.box.shouldMerge(
            previous: animation,
            value: interval,
            time: elapsed,
            context: &context
        ) {
            state = context.state
            animation = newAnimation
            interval += newInterval
        } else {
            combineAnimation(
                into: &animation,
                state: &state,
                value: interval,
                elapsed: elapsed,
                newAnimation: newAnimation,
                newValue: newInterval
            )
            interval += newInterval
        }
        refreshScheduling(at: time, from: transaction)
    }

    /// Returns `true` when the active animation has reached its terminal
    /// `nil` sample. A non-sampling frame and a continuing sample return false.
    func update(
        _ value: inout Value,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> Bool {
        if shouldUsePreviousAnimationValue(at: time) {
            restorePreviousAnimationValue(value: &value)
            return false
        }

        switch phase {
        case .pending:
            beginTime = time
            phase = .first
        case .first:
            phase = .second
            let previousOffset = nextTime.seconds - beginTime.seconds
            nextTime = Time(seconds: time.seconds + previousOffset)
            beginTime = time
            restorePreviousAnimationValue(value: &value)
            return false
        case .second:
            let minimumElapsed = 2 * max(
                quantizedFrameInterval,
                1.0 / 60.0
            )
            let elapsed = time.seconds - beginTime.seconds
            if minimumElapsed < elapsed {
                beginTime = Time(seconds: time.seconds - minimumElapsed)
            }
            phase = .running
        case .running:
            break
        }

        let elapsed = time.seconds - beginTime.seconds
        var context = makeAnimationContext(
            state: state,
            isLogicallyComplete: isLogicallyComplete,
            environment: resolvedAnimationEnvironment(environment),
            finishingDefinition: finishingDefinition
        )
        guard let output = animation.box.animate(
            value: interval,
            time: elapsed,
            context: &context
        ) else {
            return true
        }

        updateListeners(
            isLogicallyComplete: context.isLogicallyComplete,
            time: Time(seconds: elapsed),
            environment: environment
        )
        state = context.state
        value += output
        value -= interval
        previousAnimationValue = output
        nextTime = time
        if quantizedFrameInterval > 0 {
            let frame = (time.seconds / quantizedFrameInterval)
                .rounded(.toNearestOrAwayFromZero)
            nextTime = Time(
                seconds: (frame + 1) * quantizedFrameInterval
            )
        }
        return false
    }

    func nextUpdate() {
        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError("AnimatorState.nextUpdate requires an active ViewGraph host.")
        }
        viewGraph.nextUpdate.views.at(nextTime)
        viewGraph.nextUpdate.views.interval(
            quantizedFrameInterval,
            reason: reason
        )
    }

    func addListeners(transaction: Transaction) {
        if let listener = transaction.animationListener {
            listener.animationWasAdded()
            listeners.append(listener)
        }
        if let listener = transaction.animationLogicalListener {
            listener.animationWasAdded()
            if isLogicallyComplete {
                listener.animationWasRemoved()
            } else {
                logicalListeners.append(listener)
            }
        }
    }

    func removeListeners() {
        for listener in listeners {
            listener.animationWasRemoved()
        }
        listeners.removeAll()
        for listener in logicalListeners {
            listener.animationWasRemoved()
        }
        logicalListeners.removeAll()
        for fork in forks {
            for listener in fork.listeners {
                listener.animationWasRemoved()
            }
        }
        forks.removeAll()
    }

    private func updateListeners(
        isLogicallyComplete: Bool,
        time: Time,
        environment: Attribute<EnvironmentValues>?
    ) {
        if !self.isLogicallyComplete, isLogicallyComplete {
            self.isLogicallyComplete = true
            for listener in logicalListeners {
                listener.animationWasRemoved()
            }
            logicalListeners.removeAll()
        }

        guard !forks.isEmpty else {
            return
        }
        var completed = IndexSet()
        for index in forks.indices {
            if forks[index].update(
                time: time,
                environment: environment
            ) {
                for listener in forks[index].listeners {
                    listener.animationWasRemoved()
                }
                completed.insert(index)
            }
        }
        forks.remove(atOffsets: completed)
    }

    private func forkListeners(
        animation: Animation,
        state: AnimationState<Value>,
        interval: Value
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

    private func shouldUsePreviousAnimationValue(at time: Time) -> Bool {
        guard quantizedFrameInterval > 0 else {
            return false
        }
        return time.seconds <=
            nextTime.seconds - quantizedFrameInterval * 0.5
    }

    private func restorePreviousAnimationValue(value: inout Value) {
        value += previousAnimationValue
        value -= interval
    }

    private func updateFrameInterval(from transaction: Transaction) {
        guard let frameInterval = transaction.animationFrameInterval,
              frameInterval > 0 else {
            quantizedFrameInterval = 0
            return
        }
        quantizedFrameInterval =
            floor((frameInterval * 120) + 0.01) / 120
    }

    private func refreshScheduling(
        at time: Time,
        from transaction: Transaction
    ) {
        nextTime = time
        updateFrameInterval(from: transaction)
        reason = transaction.animationReason
    }
}

struct AnimatableAttributeHelper<AnimatedValue: Animatable> {
    private var _phase: Attribute<Phase>
    private var _time: Attribute<Time>
    private var _transaction: Attribute<Transaction>
    private var previousModelData: AnimatedValue.AnimatableData?
    private var animatorState: AnimatorState<AnimatedValue.AnimatableData>?
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

    var isAnimating: Bool {
        animatorState != nil
    }

    var needsModelResolutionForReset: Bool {
        _phase.value.resetSeed != resetSeed
    }

    mutating func commitTarget(_ target: AnimatedValue) {
        previousModelData = target.animatableData
    }

    mutating func update(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (
            AnimatedValue.AnimatableData,
            Time
        ) -> Void
    ) {
        if checkReset() {
            value.changed = true
        }

        let targetData = value.value.animatableData
        if previousModelData == nil {
            previousModelData = targetData
        } else if value.changed {
            if let previousModelData {
                if previousModelData != targetData {
                    let transaction = _transaction.value
                    if let animation =
                        transaction.effectiveAnimation ??
                        defaultAnimation {
                        var newInterval = targetData
                        newInterval -= previousModelData
                        let time = _time.value
                        if let animatorState {
                            animatorState.combine(
                                newAnimation: animation,
                                newInterval: newInterval,
                                at: time,
                                in: transaction,
                                environment: environment
                            )
                        } else {
                            animatorState = AnimatorState(
                                animation: animation,
                                interval: newInterval,
                                at: time,
                                in: transaction,
                                finishingDefinition:
                                    Self.finishingDefinition
                            )
                        }
                        animatorState?.addListeners(
                            transaction: transaction
                        )
                    }
                    self.previousModelData = targetData
                }
            }
        }

        guard let animatorState else {
            return
        }
        let time = _time.value
        var data = value.value.animatableData
        let isComplete = animatorState.update(
            &data,
            at: time,
            environment: environment
        )
        value.value.animatableData = data
        value.changed = true
        if isComplete {
            animatorState.removeListeners()
            self.animatorState = nil
        } else {
            animatorState.nextUpdate()
            sampleCollector(data, time)
        }
    }

    mutating func update(
        value: inout (value: AnimatedValue, changed: Bool),
        defaultAnimation: Animation?,
        environment: Attribute<EnvironmentValues>
    ) {
        update(
            value: &value,
            defaultAnimation: defaultAnimation,
            environment: environment,
            sampleCollector: { _, _ in }
        )
    }

    mutating func removeListeners() {
        animatorState?.removeListeners()
    }

    mutating func finishAndClearAnimatorState() {
        animatorState?.removeListeners()
        animatorState = nil
    }

    private mutating func checkReset() -> Bool {
        let currentResetSeed = _phase.value.resetSeed
        guard currentResetSeed != resetSeed else {
            return false
        }
        animatorState?.removeListeners()
        animatorState = nil
        previousModelData = nil
        resetSeed = currentResetSeed
        return true
    }

    private static var finishingDefinition:
        (any AnimationFinishingDefinition<
            AnimatedValue.AnimatableData
        >.Type)? {
        AnimatedValue.self as?
            any AnimationFinishingDefinition<
                AnimatedValue.AnimatableData
            >.Type
    }
}
