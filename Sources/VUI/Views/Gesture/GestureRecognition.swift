//
//  File: GestureRecognition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - DependentGesture
// ─────────────────────────────────────────────────────────────────────────────

// DependentGesture<E>._makeGesture -> DependentPhase<E>: Rule
// DependentPhase reads GestureDependency.Key preference to determine priority
struct DependentGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // GestureDependency handling is not implemented because ExclusiveGesture handles it separately.
        // DependentGesture acts as pass-through.
        body(inputs)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EventFilter
// ─────────────────────────────────────────────────────────────────────────────

// EventFilter<E>._makeGesture -> EventFilterEvents<E>: Rule + filtered events attr
struct EventFilter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    // EventFilter is used to filter events before they reach the body gesture.
    // currently pass-through without predicate because type filtering happens in EventListenerPhase
    var predicate: ((E) -> Bool)?

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // predicate filtering happens at EventListenerPhase level, so pass through
        body(inputs)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CategoryGesture
// ─────────────────────────────────────────────────────────────────────────────

// CategoryGesture<E>: calls body as-is, then injects GestureCategory.Key preference
struct CategoryGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var category: GestureCategory

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // inject GestureCategory.Key preference into outputs
        // preference injection is not implemented yet, so pass through
        body(inputs)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RepeatGesture / RepeatResetSeed / RepeatPhase
// ─────────────────────────────────────────────────────────────────────────────

// RepeatGesture<E>: handles multi-tap recognition
// RepeatResetSeed: Rule -> Value=UInt32 (sum of two attrs)
// RepeatPhase<E>: StatefulRule -> tap count tracking

struct RepeatGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var count: Int
    var maximumDelay: Double  // maximum allowed interval between taps

    init(count: Int, maximumDelay: Double = 0.5) {
        self.count = count
        self.maximumDelay = maximumDelay
    }

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = AttributeGraph.current else {
            fatalError("RepeatGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let self_ = modifier._attribute.value

        // RepeatResetSeed: sum of global resetSeed + local tap-count modifier attr
        let tapCountAttr: Attribute<UInt32> = graph.makeInput(value: 0)
        let repeatResetSeed = RepeatResetSeed(
            globalSeedAttr: inputs.resetSeed,
            localCountAttr: tapCountAttr
        )
        let seedAttr = graph.makeRule { repeatResetSeed.value }

        let repeatPhase = RepeatPhase<E>(
            childPhaseAttr: bodyOutputs.phase,
            timeAttr: inputs.time,
            resetSeedAttr: seedAttr,
            tapCountAttr: tapCountAttr,
            requiredCount: self_.count,
            maximumDelay: self_.maximumDelay
        )
        let resultAttr = graph.makeStatefulRule(repeatPhase)
        return bodyOutputs.withPhase(resultAttr)
    }
}

// RepeatResetSeed: Rule -> Value=UInt32 (globalSeed + localCount)
struct RepeatResetSeed {
    var globalSeedAttr: Attribute<UInt32>
    var localCountAttr: Attribute<UInt32>

    var value: UInt32 {
        globalSeedAttr.value &+ localCountAttr.value
    }
}

// RepeatPhase<E>: StatefulRule, ResettableGestureRule
struct RepeatPhase<E: EventType>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<E>

    let childPhaseAttr: Attribute<GesturePhase<E>>
    let timeAttr: Attribute<Time>
    let resetSeedAttr: Attribute<UInt32>
    var tapCountAttr: Attribute<UInt32>

    let requiredCount: Int
    let maximumDelay: Double

    var lastResetSeed: UInt32 = 0
    var lastTapTime: Double = 0        // timestamp of last completed tap
    var isFirstTap: Bool = true        // true = waiting for first tap
    var completedTaps: Int = 0
    var lastActivePhase: GesturePhase<E> = .possible(nil)

    // ResettableGestureRule conformance
    typealias PhaseValue = E
    var resetSeed: UInt32 { resetSeedAttr.value }
    // Value == GesturePhase<E> == GesturePhase<PhaseValue>, so default phaseValue applies.

    mutating func resetPhase() {
        lastTapTime = 0
        isFirstTap = true
        completedTaps = 0
        AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let now = timeAttr.value.seconds
        let childPhase = childPhaseAttr.value

        // Check inter-tap timeout (maximumDelay exceeded since last tap)
        if !isFirstTap && lastTapTime > 0 && (now - lastTapTime) > maximumDelay {
            // tap interval exceeded, fail
            isFirstTap = true
            completedTaps = 0
            AttributeGraph.setStatefulOutput(GesturePhase<E>.failed)
            return
        }

        switch childPhase {
        case .possible:
            if completedTaps == 0 {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
            // keep possible while a tap sequence is in progress
        case .active(let v):
            lastActivePhase = childPhase
            if completedTaps == 0 {
                isFirstTap = false
            }
            // count==1: become active immediately
            if requiredCount == 1 {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.active(v))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .ended(let v):
            completedTaps += 1
            lastTapTime = now

            if completedTaps >= requiredCount {
                // required tap count reached, succeed
                completedTaps = 0
                isFirstTap = true
                // increment tapCountAttr to signal RepeatResetSeed
                let newCount = tapCountAttr.value &+ 1
                tapCountAttr.setValue(newCount)
                AttributeGraph.setStatefulOutput(GesturePhase<E>.ended(v))
            } else {
                // more taps needed, stay possible
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .failed:
            completedTaps = 0
            isFirstTap = true
            AttributeGraph.setStatefulOutput(GesturePhase<E>.failed)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RequiredTapCountKey / RequiredTapCountWriter
// ─────────────────────────────────────────────────────────────────────────────

// RequiredTapCountKey: PreferenceKey propagates required tap count up the view tree
enum RequiredTapCountKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? { nil }
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}

// RequiredTapCountWriter<E>._makeGesture writes RequiredTapCountKey preference
struct RequiredTapCountWriter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var count: Int

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = AttributeGraph.current else {
            fatalError("RequiredTapCountWriter.makeGesture requires AG context")
        }
        var bodyOutputs = body(inputs)

        let countAttr: Attribute<Int?> = graph.makeInput(value: modifier._attribute.value.count)
        bodyOutputs.appendPreference(key: RequiredTapCountKey.self, value: countAttr)
        return bodyOutputs
    }
}
