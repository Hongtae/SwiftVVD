//
//  File: GestureModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureCallbacks

/// Protocol for gesture callback containers.
///
/// Requirements:
///   - associatedtype Value — gesture value type.
///   - associatedtype StateType — mutable state kept during recognition.
///   - static var initialState: StateType — initial state.
///   - func dispatch(phase:state:) -> Optional<() -> ()>
///       Invokes callbacks based on the current phase. May return an animation
///       completion closure.
///   - func cancel(state:) -> Optional<() -> ()>
///       Cleanup callback for reset.
protocol GestureCallbacks {
    associatedtype Value
    associatedtype StateType
    static var initialState: StateType { get }
    func dispatch(phase: GesturePhase<Value>, state: inout StateType) -> (() -> ())?
    func cancel(state: StateType) -> (() -> ())?
}

/// .onEnded { } callback container.
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

/// .onChanged { } callback container.
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

/// Container for .onEnded, .onChanged, and optional .onFailed callbacks.
struct FullGestureCallbacks<Value>: GestureCallbacks {
    var changed: ((Value) -> ())?
    var ended: ((Value) -> ())?
    var failed: (() -> ())?
    typealias StateType = Void
    static var initialState: Void { () }
    func dispatch(phase: GesturePhase<Value>, state: inout Void) -> (() -> ())? {
        switch phase {
        case .active(let v): changed?(v)
        case .ended(let v):  ended?(v)
        case .failed:        failed?()
        default: break
        }
        return nil
    }
    func cancel(state: Void) -> (() -> ())? { nil }
}

/// Container for failure callbacks.
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

/// LongPressGesture callback container.
struct PressableGestureCallbacks<Value>: GestureCallbacks {
    let pressing: ((Value) -> Void)?
    let pressed: (() -> Void)?
    typealias StateType = Void
    static var initialState: Void { () }
    func dispatch(phase: GesturePhase<Value>, state: inout Void) -> (() -> ())? {
        switch phase {
        case .active(let v): pressing?(v)
        case .ended:         pressed?()
        default: break
        }
        return nil
    }
    func cancel(state: Void) -> (() -> ())? { nil }
}

// GestureModifier

/// Protocol for modifier gestures — gestures that wrap another gesture and transform
/// its inputs or output. Inherits Gesture so conformers have associated Value/Body.
///
/// `ModifierGesture._makeGesture` dispatches to `Modifier.makeGesture(modifier:inputs:body:)`,
/// passing a closure that calls `Body._makeGesture` for the inner gesture.
protocol GestureModifier: Gesture {
    associatedtype BodyValue
    static func makeGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs,
        body: (_GestureInputs) -> _GestureOutputs<BodyValue>
    ) -> _GestureOutputs<Value>
}

extension GestureModifier {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError("\(Self.self) is a GestureModifier — use it as Modifier inside ModifierGesture, not standalone")
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
        // Placeholder: body(inputs) pass-through. Callback firing not yet implemented.
        let outputs = body(inputs)
        return outputs
    }
}

// ModifierGesture

/// Applies a GestureModifier to a Gesture, producing a combined gesture whose Value
/// is the modifier's output type.
///
/// _makeGesture dispatches to Modifier.makeGesture(modifier:inputs:body:), passing a
/// closure that calls Body._makeGesture for the inner gesture.
struct ModifierGesture<Modifier: GestureModifier, Body: Gesture>: Gesture
    where Modifier.BodyValue == Body.Value
{
    var modifier: Modifier
    var body: Body

    typealias Value = Modifier.Value

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Modifier.Value> {
        Modifier.makeGesture(
            modifier: gesture[\.modifier],
            inputs: inputs,
            body: { modifiedInputs in
                Body._makeGesture(gesture: gesture[\.body], inputs: modifiedInputs)
            }
        )
    }
}

// _EndedGesture

/// Wraps a gesture to fire a callback when it ends.
///
/// Body = ModifierGesture<CallbacksGesture<EndedCallbacks<Content.Value>>, Content>,
/// so Value == Body.Value and the default Gesture._makeGesture delegate is used:
///   gesture[\.body] → ModifierGesture._makeGesture → CallbacksGesture.makeGesture
public struct _EndedGesture<Content: Gesture>: Gesture {
    public typealias Value = Content.Value
    public typealias Body = Never

    // Internal storage
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
        // HighPriority swaps first/second so the added gesture becomes
        // ExclusiveGesture's first child, giving it recognition priority.
        _MapGesture(content: ExclusiveGesture(second, first), transform: { _ in () })
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
    var gestureMask: GestureMask { get }
    static func makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs

    /// Produces `_GestureOutputs<()>` for one gesture session.
    /// Called by `GestureResponder<Self>.makeGesture(inputs:)` at touch time.
    /// The modifier is passed as a `_GraphValue` so the gesture type's `_makeGesture`
    /// can subscript into it to get the inner gesture attribute.
    static func _makeSessionGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<()>
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

// AddGestureModifier _makeSessionGesture + GestureFilter

extension AddGestureModifier {
    /// Creates the gesture graph for one active session.
    /// Maps the raw `_GestureOutputs<T.Value>` to `_GestureOutputs<()>` so the session
    /// only needs to track terminal state, not the concrete value type.
    static func _makeSessionGesture(
        modifier: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<()> {
        guard let graph = AttributeGraph.current else {
            fatalError("AddGestureModifier._makeSessionGesture requires AG context")
        }
        let rawOutputs = T._makeGesture(gesture: modifier[\.gesture], inputs: inputs)
        let mappedPhase: Attribute<GesturePhase<()>> = graph.makeRule {
            rawOutputs.phase.value.map { _ in () }
        }
        return rawOutputs.withPhase(mappedPhase)
    }
}

/// StatefulRule that lazily creates a GestureResponder<M> inside a dedicated AGSubgraph
/// and keeps it updated whenever the modifier or inner view responders change.
///
/// AGSubgraph ownership:
///   GestureFilter owns a separate AGSubgraph in which GestureResponder<M> is born.
///   On first updateValue() the responder is created inside self.subgraph context.
///   On subsequent evaluations: mask and inner responders updated in place (same instance).
struct GestureFilter<M: GestureViewModifier>: StatefulRule {
    typealias Value = [any ViewResponder]

    var modifierAttr: Attribute<M>
    var innerRespondersAttr: Attribute<[any ViewResponder]>
    var viewInputs: _ViewInputs
    var exclusionPolicy: GestureResponderExclusionPolicy
    var subgraph: AGSubgraph
    var _responder: GestureResponder<M>? = nil

    mutating func updateValue() {
        let currentModifier = modifierAttr.value
        if _responder == nil {
            AGSubgraph.$current.withValue(subgraph) {
                _responder = GestureResponder<M>(
                    modifierAttr: modifierAttr,
                    exclusionPolicy: exclusionPolicy,
                    mask: currentModifier.gestureMask,
                    inputs: viewInputs
                )
            }
            AttributeGraph.setStatefulOutput([_responder!])
        }
        _responder!.mask = currentModifier.gestureMask
        _responder!.responders = innerRespondersAttr.value
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

        // If ViewRespondersKey is not in the preference keys, there is no gesture host collecting
        // responders — skip GestureFilter creation entirely.
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else { return outputs }

        let capturedViewInputs = inputs

        // Collect inner ViewRespondersKey nodes from the inner body outputs.
        // These represent gesture responders from sub-views (e.g. Buttons inside this view).
        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        // Build a single Attribute<[any ViewResponder]> for inner responders.
        // If there are multiple inner nodes, reduce them via ViewRespondersKey.reduce.
        let innerRespondersAttr: Attribute<[any ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[any ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let val = Attribute<[any ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { val }
                }
                return combined
            }
        }

        // GestureFilter StatefulRule: lazily creates GestureResponder<Self> on first evaluation
        // inside its own dedicated AGSubgraph, then updates mask/responders in place.
        let responderSubgraph = AGSubgraph()
        let gestureFilter = GestureFilter<Self>(
            modifierAttr: modifier._attribute,
            innerRespondersAttr: innerRespondersAttr,
            viewInputs: capturedViewInputs,
            exclusionPolicy: Combiner.exclusionPolicy,
            subgraph: responderSubgraph
        )
        let respondersAttr = graph.makeStatefulRule(gestureFilter)

        // Remove inner ViewRespondersKey entries from outputs — they are now consumed
        // as GestureResponder.children. The outer preference is the GestureFilter output.
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        return outputs
    }
}
