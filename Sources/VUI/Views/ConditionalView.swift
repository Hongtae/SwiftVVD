//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// File-scope state class
private final class _ConditionalBranchState {
    var isTrue: Bool? = nil
    var activeSubgraph: AGSubgraph? = nil
    var activeLCAttr: Attribute<LayoutComputer>? = nil
    /// Full preferences output of the currently active branch's _makeView result.
    /// Each relay rule reads its key's node(s) from here and forwards the value.
    var activeOutputs: PreferencesOutputs? = nil
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never

    /// Dynamic-subgraph implementation.
    ///
    /// Relay structure:
    ///   At _makeView time, iterates inputs.preferences.keys.keys and creates
    ///   one relay Attribute per key. Relay node IDs are fixed for the lifetime
    ///   of the view; only the rule re-evaluates (and forwards a different value)
    ///   when the branch switches.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let state = _ConditionalBranchState()
        state.activeSubgraph = AGSubgraph()

        // Master branch rule: detects branch changes and replaces the active subgraph.
        // All relay rules depend on this node, ensuring state.activeOutputs is
        // updated before any relay rule evaluates.
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            guard AttributeGraph.current != nil else {
                fatalError("_ConditionalContent rule evaluated outside an active AttributeGraph context.")
            }

            let nowTrue: Bool
            if case .trueContent = view._attribute.value.storage { nowTrue = true }
            else { nowTrue = false }

            if state.isTrue != nowTrue {
                state.isTrue = nowTrue
                state.activeSubgraph?.invalidate()

                let outputs: _ViewOutputs
                if nowTrue {
                    outputs = AGSubgraph.$current.withValue(state.activeSubgraph) {
                        TrueContent._makeView(view: view[\.._trueContent], inputs: inputs)
                    }
                } else {
                    outputs = AGSubgraph.$current.withValue(state.activeSubgraph) {
                        FalseContent._makeView(view: view[\._falseContent], inputs: inputs)
                    }
                }
                state.activeLCAttr = outputs._layoutComputer.attribute
                // Store the full branch preferences so relay rules can read from it.
                state.activeOutputs = outputs.preferences
            }

            return state.activeLCAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        // Create one relay node per key in inputs.preferences.keys.keys.
        //
        // SE-0352 implicit existential opening:
        //   Each element of inputs.preferences.keys.keys has type `any PreferenceKey.Type`.
        //   Passing it to addRelay(_:) causes Swift to implicitly open the existential
        //   and bind the concrete type to K.
        var outPrefs = PreferencesOutputs()
        for key in inputs.preferences.keys.keys {
            func addRelay<K: PreferenceKey>(_ k: K.Type) {
                let relayAttr: Attribute<K.Value> = graph.makeRule {
                    // Depend on lcAttr to guarantee state.activeOutputs is up-to-date.
                    _ = lcAttr.value
                    guard let prefs = state.activeOutputs else { return K.defaultValue }
                    // Reduce all nodes for K from the branch outputs directly inside
                    // this rule — no extra AG node needed for the intermediate reduce.
                    var combined = K.defaultValue
                    for kv in prefs.preferences {
                        guard ObjectIdentifier(kv.key) == ObjectIdentifier(k) else { continue }
                        let val = Attribute<K.Value>(kv.value).value
                        K.reduce(value: &combined) { val }
                    }
                    return combined
                }
                outPrefs.append(k, node: relayAttr.identifier)
            }
            addRelay(key)
        }

        return _ViewOutputs(preferences: outPrefs, layoutComputer: OptionalAttribute(lcAttr))
    }

    /// Returns a single-item static list containing a proxy for this view.
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }

    var _trueContent: TrueContent {
        if case let .trueContent(content) = storage { return content }
        fatalError()
    }
    var _falseContent: FalseContent {
        if case let .falseContent(content) = storage { return content }
        fatalError()
    }
}

extension _ConditionalContent: _PrimitiveView where Self: View {
}
