//
//  File: GestureViewAttachment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureResponderExclusionPolicy

/// Controls how a gesture responder interacts with others during hit testing.
enum GestureResponderExclusionPolicy: Equatable, CustomStringConvertible {
    /// No special exclusion, default gesture priority.
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
// Adding MultiViewModifier here makes the ModifiedContent._makeViewList check unified.
protocol GestureViewModifier: MultiViewModifier where Body == Never {
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
    // _makeViewList: inherited from MultiViewModifier (creates ModifiedElements).
    // ModifiedElements materialization calls _makeView per child.
}

// AddGestureModifier

/// Single modifier type for all gesture-attaching view modifiers.
/// The `Combiner` type parameter distinguishes priority:
///   - `DefaultGestureCombiner`              -> `.gesture(_:including:)`
///   - `HighPriorityGestureCombiner`         -> `.highPriorityGesture(_:including:)`
///   - `SimultaneousGestureCombiner`         -> `.simultaneousGesture(_:including:)`
///   - `GloballySimultaneousGestureCombiner` -> globally simultaneous
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
        let gestureGV = modifier[\.gesture]
        let rawOutputs = T._makeGesture(gesture: gestureGV, inputs: inputs)
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
///   GestureFilter owns a separate AGSubgraph where GestureResponder<M> is created.
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
            // First evaluation: create the GestureResponder inside the dedicated subgraph.
            // The responder is born in ViewGraph's AG context (GestureFilter runs in ViewGraph's AG).
            AGSubgraph.$current.withValue(subgraph) {
                _responder = GestureResponder<M>(
                    modifierAttr: modifierAttr,
                    currentModifier: currentModifier,
                    exclusionPolicy: exclusionPolicy,
                    mask: currentModifier.gestureMask,
                    inputs: viewInputs
                )
            }
            AttributeGraph.setStatefulOutput([_responder!])
        } else {
            // Subsequent evaluation: modifier may have changed.
            // Update the snapshot and flag the gesture chain for rebuild.
            _responder!.currentModifier = currentModifier
            _responder!.needsRebuild = true
        }
        // Refresh geometry snapshots (used for synchronous hit-testing in GestureGraph context).
        // Also store the raw ViewGraph AG attributes so createSession can wire cross-graph refs
        // and gesture coordinate-transform nodes always read the latest ViewGraph geometry.
        _responder!.snapshotTransform = viewInputs.transform.value
        _responder!.snapshotSize = viewInputs.size.value
        _responder!.snapshotPreferenceKeys = viewInputs.preferences.hostKeys.value
        _responder!.transformAttr = viewInputs.transform
        _responder!.sizeAttr = viewInputs.size
        _responder!.mask = currentModifier.gestureMask
        let innerResponders = innerRespondersAttr.value
        _responder!.responders = innerResponders
        // Wire nextResponder so that isDescendant() can traverse the chain upward.
        // isDescendant walks nextResponder, not parent.
        for r in innerResponders where r.nextResponder == nil {
            r.nextResponder = _responder!
        }
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
        // responders, so skip GestureFilter creation entirely.
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

        // Remove inner ViewRespondersKey entries from outputs. They are now consumed
        // as GestureResponder.children. The outer preference is the GestureFilter output.
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        return outputs
    }
}
