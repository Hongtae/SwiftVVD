//
//  File: GestureRecognition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - GestureDependency / DependentGesture

enum GestureDependency: UInt8, Hashable {
    case none
    case pausedWhileActive
    case pausedUntilFailed
    case failIfActive

    enum Key: PreferenceKey {
        static var defaultValue: GestureDependency { .none }

        static func reduce(
            value: inout GestureDependency,
            nextValue: () -> GestureDependency
        ) {
            let next = nextValue()
            if next.rank >= value.rank {
                value = next
            }
        }
    }

    private var rank: UInt8 {
        switch self {
        case .none: 0
        case .pausedWhileActive: 1
        case .pausedUntilFailed: 2
        case .failIfActive: 3
        }
    }
}

struct DependentGesture<E>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var dependency: GestureDependency

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = _AGGraph.current else {
            fatalError("DependentGesture.makeGesture requires AG context")
        }
        var outputs = body(inputs)
        let phase = graph.makeRule(DependentPhase(
            _modifier: modifier._attribute,
            _phase: outputs.phase,
            _inheritedPhase: inputs.inheritedPhase
        ))
        outputs.phase = phase
        if outputs.preferences.value(for: GestureDependency.Key.self) == nil {
            outputs.preferences.setValue(
                modifier[\.dependency]._attribute.identifier,
                for: GestureDependency.Key.self
            )
        }
        return outputs
    }
}

struct DependentPhase<E>: Rule {
    typealias Value = GesturePhase<E>

    var _modifier: Attribute<DependentGesture<E>>
    var _phase: Attribute<GesturePhase<E>>
    var _inheritedPhase: Attribute<_GestureInputs.InheritedPhase>

    func updateValue() -> GesturePhase<E> {
        _phase.value.applyingDependency(
            _modifier.value.dependency,
            inheritedPhase: _inheritedPhase.value
        )
    }
}

extension GesturePhase {
    fileprivate func paused() -> GesturePhase<V> {
        switch self {
        case .active(let value), .ended(let value):
            return .possible(value)
        case .possible, .failed:
            return self
        }
    }

    fileprivate func applyingDependency(
        _ dependency: GestureDependency,
        inheritedPhase: _GestureInputs.InheritedPhase
    ) -> GesturePhase<V> {
        switch dependency {
        case .none:
            return self
        case .pausedWhileActive:
            return inheritedPhase.contains(.active) ? paused() : self
        case .pausedUntilFailed:
            return inheritedPhase.contains(.failed) ? self : paused()
        case .failIfActive:
            if inheritedPhase.contains(.active) {
                return .failed
            }
            return inheritedPhase.contains(.failed) ? self : paused()
        }
    }
}

extension Gesture {
    func dependency(
        _ dependency: GestureDependency
    ) -> ModifierGesture<DependentGesture<Value>, Self> {
        ModifierGesture(
            modifier: DependentGesture(dependency: dependency),
            body: self
        )
    }
}

// MARK: - EventFilter

// EventFilter forwards the shared event stream unchanged.
// Event type filtering is handled in EventListenerPhase.
struct EventFilter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    // Retained for the API shape expected by callers that construct this modifier.
    var predicate: ((E) -> Bool)?

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
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
        // The category is stored on the modifier. makeGesture forwards the body outputs.
        body(inputs)
    }
}

// Gesture.category(_:includeChildren:) -> ModifierGesture<CategoryGesture<Value>, Self>
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

// RepeatGesture<E> handles multi-tap recognition.
// RepeatResetSeed combines the global reset seed with local tap-count changes.
// RepeatPhase tracks tap count state.

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
        guard let graph = _AGGraph.current else {
            fatalError("RepeatGesture.makeGesture requires AG context")
        }
        let bodyOutputs = body(inputs)
        let self_ = modifier._attribute.value

        // RepeatResetSeed combines the global reset seed with the local tap-count attr.
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

// RepeatResetSeed value is globalSeed + localCount.
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
    var lastTapTime: Double = 0        // deadline for the pending inter-tap interval
    var isFirstTap: Bool = true        // true when no inter-tap deadline is pending
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
        _AGGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let now = timeAttr.value.seconds
        let childPhase = childPhaseAttr.value

        // A repeat stores an absolute deadline so graph time can wake it without
        // replaying the previous terminal input as another tap.
        if !isFirstTap && lastTapTime > 0 && now > lastTapTime {
            _AGGraph.setStatefulOutput(GesturePhase<E>.failed)
            return
        }

        switch childPhase {
        case .possible:
            if completedTaps == 0 {
                _AGGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
            // Keep possible while a tap sequence is in progress.
        case .active(let v):
            lastActivePhase = childPhase
            lastTapTime = 0
            isFirstTap = true
            // A later tap becomes active once the preceding completed taps make
            // this input capable of satisfying the configured count.
            if completedTaps >= requiredCount - 1 {
                _AGGraph.setStatefulOutput(GesturePhase<E>.active(v))
            } else {
                _AGGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .ended(let v):
            completedTaps += 1
            lastTapTime = now

            if completedTaps >= requiredCount {
                // Required tap count reached, completing the sequence.
                completedTaps = 0
                isFirstTap = true
                lastTapTime = 0
                // Increment tapCountAttr to signal RepeatResetSeed.
                let newCount = tapCountAttr.value &+ 1
                tapCountAttr.setValue(newCount)
                _AGGraph.setStatefulOutput(GesturePhase<E>.ended(v))
            } else {
                // More taps are needed. Keep the gesture possible and publish
                // the absolute wake-up deadline to the owning gesture host.
                lastTapTime = now + maximumDelay
                isFirstTap = false
                _AGGraph.setStatefulOutput(GesturePhase<E>.possible(nil))
            }
        case .failed:
            completedTaps = 0
            isFirstTap = true
            _AGGraph.setStatefulOutput(GesturePhase<E>.failed)
        }

        if !isFirstTap,
           let context = _AGGraphContext.current,
           let gestureGraph = context.context as? GestureGraph {
            let deadline = Time(seconds: lastTapTime)
            if deadline < gestureGraph.nextGestureUpdateTime {
                gestureGraph.nextGestureUpdateTime = deadline
            }
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

// RequiredTapCountWriter<E> writes RequiredTapCountKey preference.
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
        guard let graph = _AGGraph.current else {
            fatalError("RequiredTapCountWriter.makeGesture requires AG context")
        }
        var bodyOutputs = body(inputs)

        let countAttr: Attribute<Int?> = graph.makeInput(value: modifier._attribute.value.count)
        bodyOutputs.appendPreference(key: RequiredTapCountKey.self, value: countAttr)
        return bodyOutputs
    }
}

// MARK: - SizeGesture / SizeGestureChild

// Wraps an inner gesture with the current reactive size from inputs.size.
// The content closure is called with the latest CGSize to produce the child gesture.
struct SizeGesture<T: Gesture>: Gesture {
    typealias Value = T.Value
    typealias Body = Never

    // Produces the child gesture for the current size.
    var content: (CGSize) -> T

    public var body: Never { fatalError("SizeGesture.body must not be called") }

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<T.Value> {
        guard let graph = _AGGraph.current else {
            fatalError("SizeGesture._makeGesture requires AG context")
        }
        let sizeAttr = inputs.size
        let contentGV = gesture[\.content]

        // Reactive rule that calls content(currentSize).
        let contentAttr = contentGV._attribute
        let childAttr: Attribute<T> = graph.makeRule {
            let size = sizeAttr.value.value      // CGSize
            let content = contentAttr.value      // (CGSize) -> T
            return content(size)
        }
        return T._makeGesture(gesture: _GraphValue(_attribute: childAttr), inputs: inputs)
    }
}

extension SizeGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(T.self, eventType: eventType)
    }
}

extension SizeGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(T.self, eventType: eventType)
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
        guard let graph = _AGGraph.current else {
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

// DelayedPhase<T>: StatefulRule + ResettableGestureRule.
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
        _AGGraph.currentStatefulOutput() ?? .possible(nil)
    }

    mutating func resetPhase() {
        pendingFlag = 0
        startTimestamp = 0
        _AGGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let modifier = modifierAttr.value
        let inner = innerPhaseAttr.value

        switch inner {
        case .possible(let v):
            pendingFlag = 0
            _AGGraph.setStatefulOutput(GesturePhase<T>.possible(v))
        case .failed:
            pendingFlag = 0
            _AGGraph.setStatefulOutput(GesturePhase<T>.failed)
        case .active(let ev):
            // duration=0 or pendingFlag==2 means immediate pass-through.
            if modifier.duration <= 0 {
                pendingFlag = 2  // mark fired so .ended passes through correctly
                _AGGraph.setStatefulOutput(GesturePhase<T>.active(ev))
            } else if pendingFlag == 0 {
                startTimestamp = timeAttr.value.seconds
                pendingFlag = 1
                _AGGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
                // The next event delivery re-evaluates the pending delay.
            } else if pendingFlag == 1 {
                let elapsed = timeAttr.value.seconds - startTimestamp
                if elapsed >= modifier.duration {
                    _AGGraph.setStatefulOutput(GesturePhase<T>.active(ev))
                    pendingFlag = 2
                } else {
                    _AGGraph.setStatefulOutput(GesturePhase<T>.possible(nil))
                }
            } else {  // pendingFlag == 2, already fired
                _AGGraph.setStatefulOutput(GesturePhase<T>.active(ev))
            }
        case .ended(let ev):
            // Ending before duration fails. Ending after firing succeeds.
            if pendingFlag == 2 {
                _AGGraph.setStatefulOutput(GesturePhase<T>.ended(ev))
            } else {
                _AGGraph.setStatefulOutput(GesturePhase<T>.failed)
            }
            pendingFlag = 0
        }
    }
}
