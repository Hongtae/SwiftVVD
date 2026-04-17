//
//  File: GestureRecognition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - DependentGesture

// DependentGesture reads gesture dependency preferences to determine priority.
struct DependentGesture<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // GestureDependency handling is not implemented yet because ExclusiveGesture handles it separately.
        // DependentGesture acts as pass-through.
        body(inputs)
    }
}

// MARK: - EventFilter

// EventFilter is used to filter events before they reach the body gesture.
struct EventFilter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    // Currently pass-through without predicate because type filtering happens in EventListenerPhase.
    var predicate: ((E) -> Bool)?

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        // Predicate filtering happens at the EventListenerPhase level, so pass through.
        body(inputs)
    }
}

// MARK: - CategoryGesture

// CategoryGesture<V>: pass-through modifier that injects GestureCategory.Key preference.
// No EventType constraint on V, so it works with both EventType values (TapGesture)
// and arbitrary Value types (DragGesture.Value, Bool, etc.).
struct CategoryGesture<V>: GestureModifier {
    typealias BodyValue = V
    typealias Value = V
    typealias Body = Never

    var category: GestureCategory

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<V>
    ) -> _GestureOutputs<V> {
        // Injects GestureCategory.Key preference into outputs.
        // Preference injection is not implemented yet, so pass through.
        body(inputs)
    }
}

// Gesture.category(_:includeChildren:) -> ModifierGesture<CategoryGesture<Value>, Self>.
// DragGesture uses .drag, LongPressGesture uses .longPress, TapGesture uses .select.
extension Gesture {
    func category(
        _ cat: GestureCategory,
        includeChildren: Bool = false
    ) -> ModifierGesture<CategoryGesture<Value>, Self> {
        ModifierGesture(modifier: CategoryGesture(category: cat), body: self)
    }
}

// MARK: - RepeatGesture / RepeatResetSeed / RepeatPhase

// RepeatGesture<E>: handles multi-tap recognition.
// RepeatResetSeed: Rule -> Value=UInt32 (sum of two attrs).
// RepeatPhase<E>: StatefulRule -> tap count tracking.

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

        // RepeatResetSeed: sum of global resetSeed + local tap-count modifier attr.
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

// RepeatResetSeed: Rule -> Value=UInt32 (globalSeed + localCount).
struct RepeatResetSeed {
    var globalSeedAttr: Attribute<UInt32>
    var localCountAttr: Attribute<UInt32>

    var value: UInt32 {
        globalSeedAttr.value &+ localCountAttr.value
    }
}

// RepeatPhase<E>: StatefulRule, ResettableGestureRule.
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
            // Tap interval exceeded, fail.
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
            // Keep possible while a tap sequence is in progress.
        case .active(let v):
            lastActivePhase = childPhase
            if completedTaps == 0 {
                isFirstTap = false
            }
            // count == 1: become active immediately.
            if requiredCount == 1 {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.active(v))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .ended(let v):
            completedTaps += 1
            lastTapTime = now

            if completedTaps >= requiredCount {
                // Required tap count reached, succeed.
                completedTaps = 0
                isFirstTap = true
                // Increment tapCountAttr to signal RepeatResetSeed.
                let newCount = tapCountAttr.value &+ 1
                tapCountAttr.setValue(newCount)
                AttributeGraph.setStatefulOutput(GesturePhase<E>.ended(v))
            } else {
                // More taps needed, stay possible.
                AttributeGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .failed:
            completedTaps = 0
            isFirstTap = true
            AttributeGraph.setStatefulOutput(GesturePhase<E>.failed)
        }
    }
}

// MARK: - RequiredTapCountKey / RequiredTapCountWriter

// RequiredTapCountKey propagates required tap count up the view tree.
enum RequiredTapCountKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? { nil }
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}

// RequiredTapCountWriter<E>._makeGesture writes RequiredTapCountKey preference.
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

// MARK: - SizeGesture / SizeGestureChild

// SizeGesture<T>: wraps inner gesture T with reactive CGSize from inputs.size.
// _makeGesture reads the ViewSize AG attribute, calls content(size), and then
// calls T._makeGesture with the resulting _GraphValue<T>.
struct SizeGesture<T: Gesture>: Gesture {
    typealias Value = T.Value
    typealias Body = Never

    var content: (CGSize) -> T

    public var body: Never { fatalError("SizeGesture.body must not be called") }

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<T.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("SizeGesture._makeGesture requires AG context")
        }
        let sizeAttr = inputs.size
        let contentGV = gesture[\.content]

        // Reactive rule that calls content(currentSize) -> T.
        let contentAttr = contentGV._attribute
        let childAttr: Attribute<T> = graph.makeRule {
            let size = sizeAttr.value.value      // CGSize
            let content = contentAttr.value      // (CGSize) -> T
            return content(size)
        }
        return T._makeGesture(gesture: _GraphValue(_attribute: childAttr), inputs: inputs)
    }
}

// MARK: - DelayedGesture / DelayedPhase

// DelayedGesture<T>: GestureModifier that requires T to be active for `duration` seconds
//   before passing through. Used in PrimitiveButtonGestureCore.body with duration=0.
struct DelayedGesture<T: EventType>: GestureModifier {
    typealias BodyValue = T
    typealias Value = T
    typealias Body = Never

    var duration: Double      // required hold duration (0 = immediate)
    var filter: (T) -> Bool   // event pre-filter

    init(duration: Double = 0.0, filter: @escaping (T) -> Bool = { _ in true }) {
        self.duration = duration
        self.filter = filter
    }

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<T>
    ) -> _GestureOutputs<T> {
        guard let graph = AttributeGraph.current else {
            fatalError("DelayedGesture.makeGesture requires AG context")
        }
        let innerOutputs = body(inputs)
        let delayed = DelayedPhase(
            modifierAttr:   modifier._attribute,
            innerPhaseAttr: innerOutputs.phase,
            resetSeedAttr:  inputs.resetSeed,
            timeAttr:       inputs.time
        )
        let resultAttr = graph.makeStatefulRule(delayed)
        return innerOutputs.withPhase(resultAttr)
    }
}

// DelayedPhase<T>: StatefulRule + ResettableGestureRule
// Holds state: startTimestamp, pendingFlag (0=idle,1=waiting,2=fired), lastResetSeed.
// When duration==0: immediate pass-through (common case for _ButtonGesture).
// When duration>0: waits until elapsed >= duration before becoming .active.
struct DelayedPhase<T: EventType>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<T>
    typealias PhaseValue = T

    let modifierAttr:   Attribute<DelayedGesture<T>>
    let innerPhaseAttr: Attribute<GesturePhase<T>>
    let resetSeedAttr:  Attribute<UInt32>
    let timeAttr:       Attribute<Time>

    var startTimestamp: Double = 0  // delay start time
    var pendingFlag: UInt8 = 0      // 0=idle, 1=waiting, 2=fired
    var lastResetSeed: UInt32 = 0

    // ResettableGestureRule
    var resetSeed: UInt32 { resetSeedAttr.value }
    var phaseValue: GesturePhase<T> {
        AttributeGraph.currentStatefulOutput() ?? .possible(nil)
    }

    mutating func resetPhase() {
        pendingFlag = 0
        startTimestamp = 0
        AttributeGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let modifier = modifierAttr.value
        let inner = innerPhaseAttr.value

        switch inner {
        case .possible(let v):
            pendingFlag = 0
            AttributeGraph.setStatefulOutput(GesturePhase<T>.possible(v))
        case .failed:
            pendingFlag = 0
            AttributeGraph.setStatefulOutput(GesturePhase<T>.failed)
        case .active(let ev):
            // duration=0 or pendingFlag==2: immediate pass-through.
            if modifier.duration <= 0 {
                pendingFlag = 2  // mark fired so .ended passes through correctly
                AttributeGraph.setStatefulOutput(GesturePhase<T>.active(ev))
            } else if pendingFlag == 0 {
                startTimestamp = timeAttr.value.seconds
                pendingFlag = 1
                AttributeGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
                // Re-evaluate on the next event delivery.
            } else if pendingFlag == 1 {
                let elapsed = timeAttr.value.seconds - startTimestamp
                if elapsed >= modifier.duration {
                    AttributeGraph.setStatefulOutput(GesturePhase<T>.active(ev))
                    pendingFlag = 2
                } else {
                    AttributeGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
                }
            } else {  // pendingFlag == 2: already fired
                AttributeGraph.setStatefulOutput(GesturePhase<T>.active(ev))
            }
        case .ended(let ev):
            // End before duration fails; end after duration succeeds.
            if pendingFlag == 2 {
                AttributeGraph.setStatefulOutput(GesturePhase<T>.ended(ev))
            } else {
                AttributeGraph.setStatefulOutput(GesturePhase<T>.failed)
            }
            pendingFlag = 0
        }
    }
}
