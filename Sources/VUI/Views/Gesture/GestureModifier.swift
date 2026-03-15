//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// _GestureInputsModifier

/// A modifier that transforms `_GestureInputs` before passing them to an inner gesture.
/// Used by `EndedCallbacks`, `ChangedCallbacks`, and similar callback-injection types.
protocol _GestureInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs)
}

// Callback Types

struct EndedCallbacks<Value>: _GestureInputsModifier {
    let ended: (Value) -> Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        // Callback registration is handled structurally via ModifierGesture chain;
        // inputs modification is not needed here since callbacks are invoked from
        // the phase-change AG rule.
    }
}

struct ChangedCallbacks<Value>: _GestureInputsModifier {
    let changed: (Value) -> Void
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
    }
}

struct PressableGestureCallbacks<Value>: _GestureInputsModifier {
    let pressing: ((Value) -> Void)?
    let pressed: (() -> Void)?
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
    }
}

struct CallbacksGesture<Callbacks>: _GestureInputsModifier where Callbacks: _GestureInputsModifier {
    let callbacks: Callbacks
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GestureInputs) {
        Callbacks._makeInputs(modifier: modifier[\.callbacks], inputs: &inputs)
    }
}

// ModifierGesture

/// Wraps a gesture with an inputs modifier, threading the modified inputs through.
struct ModifierGesture<Modifier, Content>: Gesture
    where Modifier: _GestureInputsModifier, Content: Gesture
{
    let content: Content
    let modifier: Modifier

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        var inputs = inputs
        Modifier._makeInputs(modifier: gesture[\.modifier], inputs: &inputs)
        return Content._makeGesture(gesture: gesture[\.content], inputs: inputs)
    }

    typealias Body = Never
    typealias Value = Content.Value
}

// _EndedGesture / _ChangedGesture

public struct _EndedGesture<Content> where Content: Gesture {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<EndedCallbacks<Content.Value>>, Content>
    let _body: _Body
}

extension _EndedGesture: Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("_EndedGesture._makeGesture requires AG context")
        }

        // Get the inner gesture outputs
        let inner = _Body._makeGesture(gesture: gesture[\._body], inputs: inputs)

        // Create an AG rule that fires the ended callback when phase becomes .ended
        let endedCallback = gesture._attribute.value._body.modifier.callbacks.ended
        let phaseAttr = inner.phase
        graph.makeSideEffectRule {
            let phase = phaseAttr.value
            if case .ended(let v) = phase {
                AttributeGraph.withoutTracking {
                    endedCallback(v)
                }
            }
        }

        return inner
    }
}

public struct _ChangedGesture<Content> where Content: Gesture, Content.Value: Equatable {
    public typealias Body = Never
    public typealias Value = Content.Value

    typealias _Body = ModifierGesture<CallbacksGesture<ChangedCallbacks<Value>>, Content>
    let _body: _Body
}

extension _ChangedGesture: Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Content.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("_ChangedGesture._makeGesture requires AG context")
        }

        let inner = _Body._makeGesture(gesture: gesture[\._body], inputs: inputs)

        let changedCallback = gesture._attribute.value._body.modifier.callbacks.changed
        let phaseAttr = inner.phase
        graph.makeSideEffectRule {
            let phase = phaseAttr.value
            if case .active(let v) = phase {
                AttributeGraph.withoutTracking {
                    changedCallback(v)
                }
            }
        }

        return inner
    }
}

// Gesture Extensions

extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> {
        .init(_body: ModifierGesture(
            content: self,
            modifier: CallbacksGesture(
                callbacks: EndedCallbacks(ended: action))))
    }
}

extension Gesture where Self.Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> {
        .init(_body: ModifierGesture(
            content: self,
            modifier: CallbacksGesture(
                callbacks: ChangedCallbacks(changed: action))))
    }
}

// GestureResponderExclusionPolicy

/// Controls how a gesture responder interacts with others during hit testing.
enum GestureResponderExclusionPolicy: Equatable, CustomStringConvertible {
    /// No special exclusion — default gesture priority.
    case `default`
    /// This responder takes priority over others.
    case highPriority
    /// This responder runs simultaneously with others under the given constraint.
    case simultaneous(SimultaneityConstraint)

    enum SimultaneityConstraint: Hashable {
        /// Simultaneous with descendant responders only.
        case descendants
        /// Simultaneous with ancestor responders only.
        case ancestors
        /// Simultaneous with all responders in the window.
        case global
    }

    var description: String {
        switch self {
        case .default: return "default"
        case .highPriority: return "highPriority"
        case .simultaneous(let c): return "simultaneous(\(c))"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.default, .default): return true
        case (.highPriority, .highPriority): return true
        case (.simultaneous(let a), .simultaneous(let b)): return a == b
        default: return false
        }
    }
}

// GestureCombiner

/// Determines how two gestures are combined and what exclusion policy applies.
protocol GestureCombiner {
    associatedtype Result: Gesture
    static func combine(_ first: AnyGesture<()>, _ second: AnyGesture<()>) -> Result
    static var exclusionPolicy: GestureResponderExclusionPolicy { get }
}

// GestureCombiner conformances

struct DefaultGestureCombiner: GestureCombiner {
    typealias Result = _MapGesture<ExclusiveGesture<AnyGesture<()>, AnyGesture<()>>, ()>
    static var exclusionPolicy: GestureResponderExclusionPolicy { .default }
    static func combine(_ first: AnyGesture<()>, _ second: AnyGesture<()>) -> Result {
        // First takes exclusive priority over second (default .gesture() stacking).
        _MapGesture(content: ExclusiveGesture(first, second), transform: { _ in () })
    }
}

struct HighPriorityGestureCombiner: GestureCombiner {
    typealias Result = _MapGesture<ExclusiveGesture<AnyGesture<()>, AnyGesture<()>>, ()>
    static var exclusionPolicy: GestureResponderExclusionPolicy { .highPriority }
    static func combine(_ first: AnyGesture<()>, _ second: AnyGesture<()>) -> Result {
        // Same exclusive structure as Default; priority enforcement is via exclusionPolicy.
        _MapGesture(content: ExclusiveGesture(first, second), transform: { _ in () })
    }
}

struct SimultaneousGestureCombiner: GestureCombiner {
    typealias Result = _MapGesture<SimultaneousGesture<AnyGesture<()>, AnyGesture<()>>, ()>
    static func combine(_ first: AnyGesture<()>, _ second: AnyGesture<()>) -> Result {
        _MapGesture(content: SimultaneousGesture(first, second), transform: { _ in () })
    }
    static var exclusionPolicy: GestureResponderExclusionPolicy { .simultaneous(.descendants) }
}

struct GloballySimultaneousGestureCombiner: GestureCombiner {
    typealias Result = _MapGesture<SimultaneousGesture<AnyGesture<()>, AnyGesture<()>>, ()>
    static func combine(_ first: AnyGesture<()>, _ second: AnyGesture<()>) -> Result {
        _MapGesture(content: SimultaneousGesture(first, second), transform: { _ in () })
    }
    static var exclusionPolicy: GestureResponderExclusionPolicy { .simultaneous(.global) }
}

// GestureViewModifier

/// Internal protocol for view modifiers that attach gestures to views.
/// `AddGestureModifier` conforms to this; the protocol provides a default
/// `ViewModifier._makeView` implementation that delegates to `makeView`.
protocol GestureViewModifier: ViewModifier where Body == Never {
    associatedtype Combiner: GestureCombiner
    static func makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs
}

extension GestureViewModifier {
    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeView(modifier: modifier, inputs: inputs, body: body)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

// AddGestureModifier

/// Single modifier type for all gesture-attaching view modifiers.
/// The `Combiner` type parameter distinguishes priority:
///   - `DefaultGestureCombiner`              → `.gesture(_:including:)`
///   - `HighPriorityGestureCombiner`         → `.highPriorityGesture(_:including:)`
///   - `SimultaneousGestureCombiner`         → `.simultaneousGesture(_:including:)`
///   - `GloballySimultaneousGestureCombiner` → internal
struct AddGestureModifier<T: Gesture, Combiner: GestureCombiner>: GestureViewModifier {
    var gesture: T
    var name: String?
    var gestureMask: GestureMask

    init(_ gesture: T, name: String? = nil, gestureMask: GestureMask = .all) {
        self.gesture = gesture
        self.name = name
        self.gestureMask = gestureMask
    }

    typealias Body = Never
}

// View Extensions

extension View {
    public func gesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        modifier(AddGestureModifier<T, DefaultGestureCombiner>(gesture, gestureMask: mask))
    }

    public func highPriorityGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        modifier(AddGestureModifier<T, HighPriorityGestureCombiner>(gesture, gestureMask: mask))
    }

    public func simultaneousGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        modifier(AddGestureModifier<T, SimultaneousGestureCombiner>(gesture, gestureMask: mask))
    }
}

// AddGestureModifier makeView (via GestureViewModifier)

extension AddGestureModifier {
    static func makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("AddGestureModifier.makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard let gestureGraph = GestureGraph._current,
              let eventsAttr = gestureGraph.eventsAttribute,
              let resetSeedAttr = gestureGraph.resetSeedAttribute,
              let inheritedPhaseAttr = gestureGraph.inheritedPhaseAttribute else {
            return outputs
        }

        let gestureResetSeed = graph.makeRule { resetSeedAttr.value }
        let gestureInheritedPhase = graph.makeRule { inheritedPhaseAttr.value }

        let gestureInputs = _GestureInputs(
            inputs,
            viewSubgraph: Subgraph.current,
            events: eventsAttr,
            time: inputs.base.time,
            resetSeed: gestureResetSeed,
            inheritedPhase: gestureInheritedPhase,
            gesturePreferenceKeys: inputs.preferences.hostKeys
        )

        let gestureOutputs = T._makeGesture(gesture: modifier[\.gesture], inputs: gestureInputs)

        let responder = GestureViewResponder(
            position: inputs.position,
            size: inputs.size,
            phaseAttr: gestureOutputs.phase.identifier,
            gestureMask: modifier._attribute.value.gestureMask
        )
        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        for kv in gestureOutputs.preferences.preferences {
            outputs.preferences.preferences.append(kv)
        }

        return outputs
    }
}
