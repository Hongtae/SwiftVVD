//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// File-scope state class
private final class _ConditionalBranchState {
    var isTrue: Bool? = nil
    var activeSubgraph: Subgraph? = nil
    var activeLCAttr: Attribute<LayoutComputer>? = nil
    var activeDisplayListAttr: Attribute<DisplayList>? = nil
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never

    /// Dynamic-subgraph implementation.
    ///
    /// A master LayoutComputer rule watches `storage` and maintains exactly one
    /// live branch Subgraph at a time.  When the branch switches:
    ///   1. The old branch's Subgraph is invalidated (all its AG nodes removed).
    ///   2. A fresh Subgraph is created for the new branch.
    ///   3. The new branch's `_makeView` is called inside the new Subgraph so that
    ///      every node it creates is owned by (and will be cleaned up with) the subgraph.
    ///   4. The master rule returns the new branch's LayoutComputer value.
    ///
    /// Safety note: `view[\._trueContent]` and `view[\._falseContent]` are only
    /// wired (and subsequently evaluated) while the matching branch is active,
    /// so the fatalError guards in those helpers are never triggered.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let state = _ConditionalBranchState()
        state.activeSubgraph = Subgraph() // Created while parent Subgraph is active

        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            // Retrieve the active graph from TaskLocal to avoid a retain cycle
            // (graph -> node -> rule closure -> graph)
            guard let graph = AttributeGraph.current else {
                fatalError("_ConditionalContent rule evaluated outside an active AttributeGraph context.")
            }

            // Reading .storage registers a dependency: when the branch flips this rule re-runs.
            let nowTrue: Bool
            if case .trueContent = view._attribute.value.storage { nowTrue = true }
            else { nowTrue = false }

            if state.isTrue != nowTrue {
                // --- Branch changed ---
                state.isTrue = nowTrue
                // Invalidate clears old nodes/children but keeps this subgraph attached to its parent
                state.activeSubgraph?.invalidate()

                if nowTrue {
                    let outputs = Subgraph.$current.withValue(state.activeSubgraph) {
                        TrueContent._makeView(view: view[\._trueContent], inputs: inputs)
                    }
                    state.activeLCAttr = outputs._layoutComputer.attribute
                    state.activeDisplayListAttr = outputs.preferences.reducedValue(for: DisplayList.Key.self, in: graph)
                } else {
                    let outputs = Subgraph.$current.withValue(state.activeSubgraph) {
                        FalseContent._makeView(view: view[\._falseContent], inputs: inputs)
                    }
                    state.activeLCAttr = outputs._layoutComputer.attribute
                    state.activeDisplayListAttr = outputs.preferences.reducedValue(for: DisplayList.Key.self, in: graph)
                }
            }
            
            return state.activeLCAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        let dlRelayAttr: Attribute<DisplayList> = graph.makeRule {
            // Depend on lcAttr to ensure branch state (activeDisplayListAttr) is updated first.
            _ = lcAttr.value
            return state.activeDisplayListAttr?.value ?? DisplayList()
        }

        var outPrefs = PreferencesOutputs()
        outPrefs.append(DisplayList.Key.self, node: dlRelayAttr.identifier)
        return _ViewOutputs(preferences: outPrefs,
                            layoutComputer: OptionalAttribute(lcAttr))
    }

    /// Returns a single-item static list containing a proxy for this view.
    /// The parent layout will call `_makeView` via the proxy, which handles branching.
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }

    var _trueContent: TrueContent {
        if case let .trueContent(content) = storage {
            return content
        }
        fatalError()
    }
    var _falseContent: FalseContent {
        if case let .falseContent(content) = storage {
            return content
        }
        fatalError()
    }
}

extension _ConditionalContent: _PrimitiveView where Self: View {
}
