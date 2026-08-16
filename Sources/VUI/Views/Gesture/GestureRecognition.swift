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

    static func _makeGesture(
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

    var value: GesturePhase<E> {
        _phase.value.applyingDependency(
            _modifier.value.dependency,
            inheritedPhase: _inheritedPhase.value
        )
    }
}

extension GesturePhase {
    func paused() -> GesturePhase<V> {
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
            content: self,
            modifier: DependentGesture(dependency: dependency)
        )
    }
}

// MARK: - TruePreferenceWritingGestureModifier

struct TruePreferenceWritingGestureModifier<K: PreferenceKey, V>: GestureModifier
where K.Value == Bool {
    typealias BodyValue = V
    typealias Value = V
    typealias Body = Never

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<V>
    ) -> _GestureOutputs<V> {
        var childInputs = inputs
        childInputs.preferences.remove(K.self)
        var outputs = body(childInputs)
        outputs.preferences.makePreferenceWriter(
            inputs: inputs.preferences,
            key: K.self,
            value: GraphHost.currentHost.intern(
                true,
                for: Bool.self,
                id: .trueValue
            )
        )
        return outputs
    }
}

extension Gesture {
    func truePreference<K: PreferenceKey>(
        _ key: K.Type
    ) -> ModifierGesture<TruePreferenceWritingGestureModifier<K, Value>, Self>
    where K.Value == Bool {
        ModifierGesture(
            content: self,
            modifier: TruePreferenceWritingGestureModifier<K, Value>()
        )
    }

    func cancellable()
        -> ModifierGesture<
            TruePreferenceWritingGestureModifier<IsCancellableGestureKey, Value>,
            Self
        > {
        truePreference(IsCancellableGestureKey.self)
    }
}

// MARK: - EventFilter

struct FilteredEvents {
    var events: [EventID: any EventType]
    var didFilter: Bool
}

struct EventFilterEvents<V>: Rule {
    var modifier: Attribute<EventFilter<V>>
    var events: Attribute<[EventID: any EventType]>

    var value: FilteredEvents {
        let source = events.value
        let predicate = modifier.value.predicate
        let filtered = source.filter { predicate($0.value) }
        return FilteredEvents(
            events: filtered,
            didFilter: filtered.count != source.count
        )
    }
}

struct EventFilterPhase<V>: Rule {
    var phase: Attribute<GesturePhase<V>>
    var filteredEvents: Attribute<FilteredEvents>

    var value: GesturePhase<V> {
        filteredEvents.value.didFilter ? .failed : phase.value
    }
}

struct EventFilter<V>: GestureModifier {
    typealias BodyValue = V
    typealias Value = V
    typealias Body = Never

    var predicate: (any EventType) -> Bool

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<V>
    ) -> _GestureOutputs<V> {
        guard let graph = _AGGraph.current else {
            fatalError("EventFilter.makeGesture requires AG context")
        }
        let filteredEvents = graph.makeRule(EventFilterEvents(
            modifier: modifier._attribute,
            events: inputs.events
        ))
        var childInputs = inputs
        childInputs._events = filteredEvents[offset: { filtered in
            PointerOffset.of(&filtered.events)
        }]
        var outputs = body(childInputs)
        outputs.phase = graph.makeRule(EventFilterPhase(
            phase: outputs.phase,
            filteredEvents: filteredEvents
        ))
        return outputs
    }
}

extension Gesture {
    func eventFilter<E: EventType>(
        _ type: E.Type,
        allowOtherTypes: Bool,
        _ predicate: @escaping (E) -> Bool
    ) -> ModifierGesture<EventFilter<Value>, Self> {
        ModifierGesture(
            content: self,
            modifier: EventFilter { event in
                guard let typedEvent = E(event) else {
                    return allowOtherTypes
                }
                return predicate(typedEvent)
            }
        )
    }

    func eventFilter<E: EventType>(
        forType type: E.Type,
        _ predicate: @escaping (E) -> Bool
    ) -> ModifierGesture<EventFilter<Value>, Self> {
        eventFilter(type, allowOtherTypes: true, predicate)
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
    var includeChildren: Bool

    struct Combiner<T>: Rule {
        var _modifier: Attribute<CategoryGesture<T>>
        var _existingCategory: OptionalAttribute<GestureCategory>

        var value: GestureCategory {
            let modifier = _modifier.value
            guard modifier.includeChildren,
                  let existing = _existingCategory.attribute?.value else {
                return modifier.category
            }
            return modifier.category.union(existing)
        }
    }

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<V>
    ) -> _GestureOutputs<V> {
        guard let graph = _AGGraph.current else {
            fatalError("CategoryGesture.makeGesture requires AG context")
        }
        var outputs = body(inputs)
        let existing: OptionalAttribute<GestureCategory>
        if let identifier = outputs.preferences.value(for: GestureCategory.Key.self) {
            existing = OptionalAttribute(Attribute(identifier))
        } else {
            existing = OptionalAttribute()
        }
        let category = graph.makeRule(
            Combiner<V>(
                _modifier: modifier._attribute,
                _existingCategory: existing
            )
        )
        outputs.preferences.setValue(
            category.identifier,
            for: GestureCategory.Key.self
        )
        return outputs
    }
}

// Gesture.category(_:includeChildren:) -> ModifierGesture<CategoryGesture<Value>, Self>
// DragGesture uses .drag, LongPressGesture uses .longPress, TapGesture uses .select.
extension Gesture {
    func category(
        _ cat: GestureCategory,
        includeChildren: Bool = false
    ) -> ModifierGesture<CategoryGesture<Value>, Self> {
        ModifierGesture(
            content: self,
            modifier: CategoryGesture(
                category: cat,
                includeChildren: includeChildren
            )
        )
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

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = _AGGraph.current else {
            fatalError("RepeatGesture.makeGesture requires AG context")
        }
        let resetDelta: Attribute<UInt32> = graph.makeInput(value: 0)
        let childResetSeed = graph.makeRule(RepeatResetSeed(
            _resetSeed: inputs.resetSeed,
            _delta: resetDelta
        ))
        var childInputs = inputs
        childInputs._resetSeed = childResetSeed
        var outputs = body(childInputs)
        outputs.phase = graph.makeStatefulRule(RepeatPhase<E>(
            _modifier: modifier._attribute,
            _phase: outputs.phase,
            _time: inputs.time,
            _resetSeed: inputs.resetSeed,
            _resetDelta: resetDelta,
            useGestureGraph: inputs.options.contains(.gestureGraph),
            deadline: nil,
            index: 0,
            lastResetSeed: 0
        ))
        return outputs
    }
}

struct RepeatResetSeed: Rule {
    typealias Value = UInt32

    var _resetSeed: Attribute<UInt32>
    var _delta: Attribute<UInt32>

    var value: UInt32 {
        _resetSeed.value &+ _delta.value
    }
}

struct RepeatMutation: GraphMutation {
    var _resetDelta: Attribute<UInt32>
    var index: UInt32

    func apply() {
        _resetDelta.setValue(index)
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? RepeatMutation,
              _resetDelta == mutation._resetDelta else {
            return false
        }
        index = mutation.index
        return true
    }
}

struct RepeatPhase<E: EventType>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<E>

    var _modifier: Attribute<RepeatGesture<E>>
    var _phase: Attribute<GesturePhase<E>>
    var _time: Attribute<Time>
    var _resetSeed: Attribute<UInt32>
    var _resetDelta: Attribute<UInt32>
    var useGestureGraph: Bool
    var deadline: Time?
    var index: UInt32
    var lastResetSeed: UInt32

    typealias PhaseValue = E
    var resetSeed: UInt32 { _resetSeed.value }

    mutating func resetPhase() {
        index = 0
        deadline = nil
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let time = _time.value
        if let deadline, deadline < time {
            _AGGraph.setStatefulOutput(GesturePhase<E>.failed)
            return
        }

        let childPhase = _phase.value
        switch childPhase {
        case .possible:
            _AGGraph.setStatefulOutput(childPhase)
        case .active(let value):
            deadline = nil
            if _modifier.value.count - 1 > Int(index) {
                _AGGraph.setStatefulOutput(GesturePhase<E>.possible(value))
            } else {
                _AGGraph.setStatefulOutput(childPhase)
            }
        case .ended(let value):
            index &+= 1
            let modifier = _modifier.value
            if modifier.count > Int(index) {
                deadline = time + modifier.maximumDelay
                _AGGraph.setStatefulOutput(GesturePhase<E>.possible(value))
                GraphHost.currentHost.continueTransaction(RepeatMutation(
                    _resetDelta: _resetDelta,
                    index: index
                ))
            } else {
                deadline = nil
                _AGGraph.setStatefulOutput(childPhase)
            }
        case .failed:
            _AGGraph.setStatefulOutput(childPhase)
        }

        if let deadline {
            if useGestureGraph {
                let graph = GraphHost.currentHost as! GestureGraph
                graph.scheduleGestureUpdate(at: deadline)
            } else {
                let graph = GraphHost.currentHost as! ViewGraph
                graph.nextUpdate.gestures.at(deadline)
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
        guard let current = value else {
            value = nextValue()
            return
        }
        guard let next = nextValue() else { return }

        let prefersMinimum: Bool
#if os(iOS)
        prefersMinimum = GestureContainerFeature.isEnabled
#else
        prefersMinimum = isLinkedOnOrAfter(.v6)
#endif
        value = prefersMinimum
            ? min(current, next)
            : max(current, next)
    }
}

// RequiredTapCountWriter<E> writes RequiredTapCountKey preference.
struct RequiredTapCountWriter<E: EventType>: GestureModifier {
    typealias BodyValue = E
    typealias Value = E
    typealias Body = Never

    var count: Int?

    struct Child: Rule {
        typealias Value = (inout Int?) -> Void

        var _modifier: Attribute<RequiredTapCountWriter<E>>

        var value: Value {
            let count = _modifier.value.count
            return { value in
                value = count
            }
        }
    }

    static func _makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<E>
    ) -> _GestureOutputs<E> {
        guard let graph = _AGGraph.current else {
            fatalError("RequiredTapCountWriter.makeGesture requires AG context")
        }
        var outputs = body(inputs)
        let child = graph.makeRule(Child(_modifier: modifier._attribute))
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: RequiredTapCountKey.self,
            transform: child
        )
        return outputs
    }
}

// MARK: - SizeGesture / SizeGestureChild

// Wraps an inner gesture with the current reactive size from inputs.size.
// The content closure is called with the latest CGSize to produce the child gesture.
struct SizeGesture<T: Gesture>: Gesture, PrimitiveGesture {
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

    static func _makeGesture(
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
