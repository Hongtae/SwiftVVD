//
//  File: GestureCallbacks.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureCallbacks

/// Protocol for gesture callback containers.
///
/// Requirements:
///   - associatedtype Value: gesture value type
///   - associatedtype StateType: mutable state maintained across calls during recognition
///   - static var initialState: StateType: initial state value
///   - func dispatch(phase:state:) -> Optional<() -> ()>
///       Fires callbacks according to the current phase. May return an animation completion closure.
///   - func cancel(state:) -> Optional<() -> ()>
///       Cleanup callback invoked on reset.
protocol GestureCallbacks {
    associatedtype Value
    associatedtype StateType
    static var initialState: StateType { get }
    func dispatch(phase: GesturePhase<Value>, state: inout StateType) -> (() -> ())?
    func cancel(state: StateType) -> (() -> ())?
}

/// Callback container for .onEnded { }.
struct EndedCallbacks<Value>: GestureCallbacks {
    let ended: (Value) -> Void
    typealias StateType = Void
    static var initialState: Void { () }
    func dispatch(phase: GesturePhase<Value>, state: inout Void) -> (() -> ())? {
        if case .ended(let value) = phase { ended(value) }
        return nil
    }
    func cancel(state: Void) -> (() -> ())? { nil }
}

/// Callback container for .onChanged { }.
struct ChangedCallbacks<Value>: GestureCallbacks {
    let changed: (Value) -> Void
    typealias StateType = Void
    static var initialState: Void { () }
    func dispatch(phase: GesturePhase<Value>, state: inout Void) -> (() -> ())? {
        if case .active(let value) = phase { changed(value) }
        return nil
    }
    func cancel(state: Void) -> (() -> ())? { nil }
}

/// State for FullGestureCallbacks.
/// Tracks firing state and last phase for change detection.
struct FullGestureCallbacksState<Value: Equatable> {
    var hasFired:  Bool = false
    var lastPhase: GesturePhase<Value> = .possible(nil)
}

/// Container for .onEnded + .onChanged + (optional) .onFailed + (optional) .onPossible callbacks.
/// cancel() ignores state and returns self.failed.
struct FullGestureCallbacks<Value: Equatable>: GestureCallbacks {
    var possible: ((Optional<Value>) -> ())?
    var changed:  ((Value) -> ())?
    var ended:    ((Value) -> ())?
    var failed:   (() -> ())?

    typealias StateType = FullGestureCallbacksState<Value>
    static var initialState: FullGestureCallbacksState<Value> { .init() }

    func dispatch(phase: GesturePhase<Value>, state: inout FullGestureCallbacksState<Value>) -> (() -> ())? {
        defer { state.lastPhase = phase }
        switch phase {
        case .possible(let v):
            // fire possible only when the value differs from the last possible value
            if case .possible(let prev) = state.lastPhase, prev == v { break }
            possible?(v)
        case .active(let v):
            // fire changed only when entering active or when the value changes
            let shouldFire: Bool
            if case .active(let prev) = state.lastPhase { shouldFire = prev != v }
            else { shouldFire = true }
            if shouldFire { changed?(v) }
        case .ended(let v):
            if !state.hasFired {
                state.hasFired = true
                let cb = ended
                return cb.map { closure in { closure(v) } }
            }
        case .failed:
            if !state.hasFired {
                state.hasFired = true
                return failed.map { closure in { closure() } }
            }
        }
        return nil
    }

    // Cancel ignores state and returns the failure callback.
    func cancel(state: FullGestureCallbacksState<Value>) -> (() -> ())? {
        return failed
    }
}

/// Callback container for failure only.
struct FailedCallbacks<Value>: GestureCallbacks {
    let failed: () -> ()
    typealias StateType = Void
    static var initialState: Void { () }
    func dispatch(phase: GesturePhase<Value>, state: inout Void) -> (() -> ())? {
        if case .failed = phase { failed() }
        return nil
    }
    func cancel(state: Void) -> (() -> ())? { nil }
}

/// Callback container for LongPressGesture / DelayedLongPressGesture.
/// StateType is Bool: true while pressing, false otherwise.
///
/// Dispatch algorithm:
///   - isPressing = phase.isActive
///   - pressing(isPressing) fired only when state changes from previous value
///   - phase==.ended && was pressing: pressed() fires
///
/// Cancel algorithm:
///   - state==false: return nil (was not pressing, nothing to clean up)
///   - state==true: return pressing(false) to clear the pressing UI state
struct PressableGestureCallbacks<Value>: GestureCallbacks {
    var pressing: ((Bool) -> Void)?   // Bool is always isPressing, unrelated to Value
    var pressed:  (() -> Void)?

    typealias StateType = Bool
    static var initialState: Bool { false }

    func dispatch(phase: GesturePhase<Value>, state: inout Bool) -> (() -> ())? {
        let isPressing: Bool
        if case .active = phase { isPressing = true } else { isPressing = false }

        if isPressing != state {
            state = isPressing
            if let cb = pressing {
                let val = isPressing
                return { cb(val) }
            }
        }
        if case .ended = phase {
            return pressed
        }
        return nil
    }

    // Cancel clears the pressing UI state only if it was active.
    func cancel(state: Bool) -> (() -> ())? {
        guard state, let cb = pressing else { return nil }
        return { cb(false) }
    }
}

// CallbacksPhase

/// AG StatefulRule that fires GestureCallbacks when the gesture phase changes.
///
/// pass-through: output phase = inner phase (from phaseAttr).
/// side-effect: calls callbacks.dispatch(phase:state:) on each phase change.
///
struct CallbacksPhase<C: GestureCallbacks>: StatefulRule, ResettableGestureRule {
    typealias Value = GesturePhase<C.Value>

    let modifierAttr:    Attribute<CallbacksGesture<C>>
    let phaseAttr:       Attribute<GesturePhase<C.Value>>
    let resetSeedAttr:   Attribute<UInt32>
    let useGestureGraph: Bool

    // Generic-dependent callback state.
    var state: C.StateType
    var lastResetSeed: UInt32

    // Back-reference for async dispatch (routed through enqueueAction when useGestureGraph=true).
    weak var gestureGraph: GestureGraph?

    // ResettableGestureRule conformance
    typealias PhaseValue = C.Value
    var resetSeed: UInt32 { resetSeedAttr.value }
    // Value == GesturePhase<C.Value> == GesturePhase<PhaseValue>, so default phaseValue applies.

    init(modifierAttr: Attribute<CallbacksGesture<C>>,
         phaseAttr: Attribute<GesturePhase<C.Value>>,
         resetSeedAttr: Attribute<UInt32>,
         useGestureGraph: Bool,
         gestureGraph: GestureGraph?) {
        self.modifierAttr    = modifierAttr
        self.phaseAttr       = phaseAttr
        self.resetSeedAttr   = resetSeedAttr
        self.useGestureGraph = useGestureGraph
        self.gestureGraph    = gestureGraph
        self.state           = C.initialState
        self.lastResetSeed   = 0
    }

    mutating func resetPhase() {
        state = C.initialState
        AttributeGraph.setStatefulOutput(GesturePhase<C.Value>.possible(nil))
    }

    mutating func updateValue() {
        guard resetIfNeeded() else { return }

        let currentPhase = phaseAttr.value
        let callbacks = modifierAttr.value.callbacks

        // Invoke dispatch to fire user callbacks. withoutTracking is required to prevent
        // AG dependency pollution. The return value is an animation completion closure.
        var stateRef = state
        let animCompletion: (() -> Void)? = AttributeGraph.withoutTracking {
            callbacks.dispatch(phase: currentPhase, state: &stateRef)
        }
        state = stateRef

        if let action = animCompletion {
            // Route through GestureGraph so the callback fires in the pendingActions
            // drain phase, outside AG evaluation.
            if let gg = gestureGraph {
                gg.enqueueAction(action)
            } else {
                action()
            }
        }

        AttributeGraph.setStatefulOutput(currentPhase)
    }
}

// CallbacksGesture

/// Wraps a GestureCallbacks value as a GestureModifier.
/// Used as the Modifier type in ModifierGesture by _EndedGesture and _ChangedGesture.
struct CallbacksGesture<Callbacks: GestureCallbacks>: GestureModifier {
    var callbacks: Callbacks

    typealias Value = Callbacks.Value
    typealias BodyValue = Callbacks.Value
    typealias Body = Never

    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<BodyValue>
    ) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("CallbacksGesture.makeGesture requires AG context")
        }
        let outputs = body(inputs)

        // Create CallbacksPhase StatefulRule: phase pass-through + callback firing.
        let useGestureGraph = inputs.options.contains(.gestureGraph)
        // When makeGesture runs inside GestureGraph's AG context (gestureGraph option set),
        // AttributeGraphRef.current?.context is the GestureGraph instance.
        let gg = useGestureGraph ? (AttributeGraphRef.current?.context as? GestureGraph) : nil

        let callbacksPhase = CallbacksPhase<Callbacks>(
            modifierAttr:    modifier._attribute,
            phaseAttr:       outputs.phase,
            resetSeedAttr:   inputs.resetSeed,
            useGestureGraph: useGestureGraph,
            gestureGraph:    gg
        )
        let phaseAttr = graph.makeStatefulRule(callbacksPhase)
        return outputs.withPhase(phaseAttr)
    }
}

// _EndedGesture

/// Wraps a gesture to fire a callback when it ends.
///
/// Body = ModifierGesture<CallbacksGesture<EndedCallbacks<Content.Value>>, Content>,
/// so Value == Body.Value and the default Gesture._makeGesture delegate is used:
///   gesture[\.body] -> ModifierGesture._makeGesture -> CallbacksGesture.makeGesture
public struct _EndedGesture<Content: Gesture>: Gesture {
    public typealias Value = Content.Value
    public typealias Body = Never

    // Internal storage for the modifier/body chain.
    var _body: ModifierGesture<CallbacksGesture<EndedCallbacks<Content.Value>>, Content>

    // body: Never is satisfied by Gesture's default extension (fatalError)

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        type(of: gesture._attribute.value._body)
            ._makeGesture(gesture: gesture[\._body], inputs: inputs)
    }
}

extension _EndedGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(Content.self, eventType: eventType)
    }
}

extension _EndedGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureValueAcceptsEvent(_body.body, eventType: eventType)
    }
}

// _ChangedGesture

/// Wraps a gesture to fire a callback whenever its value changes (while active).
///
/// Sets options.allowsIncompleteEventSequences (bit 5) before delegating to Body._makeGesture.
public struct _ChangedGesture<Content: Gesture>: Gesture where Content.Value: Equatable {
    public typealias Value = Content.Value
    public typealias Body = Never

    var _body: ModifierGesture<CallbacksGesture<ChangedCallbacks<Content.Value>>, Content>

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Content.Value> {
        var modifiedInputs = inputs
        modifiedInputs.options.insert(.allowsIncompleteEventSequences)
        return type(of: gesture._attribute.value._body)
            ._makeGesture(gesture: gesture[\._body], inputs: modifiedInputs)
    }
}

extension _ChangedGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(Content.self, eventType: eventType)
    }
}

extension _ChangedGesture: DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureValueAcceptsEvent(_body.body, eventType: eventType)
    }
}

// Gesture Extensions

extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> {
        _EndedGesture(_body: ModifierGesture(
            modifier: CallbacksGesture(callbacks: EndedCallbacks(ended: action)),
            body: self))
    }
}

extension Gesture where Self.Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
        _ChangedGesture(_body: ModifierGesture(
            modifier: CallbacksGesture(callbacks: ChangedCallbacks(changed: action)),
            body: self))
    }
}
