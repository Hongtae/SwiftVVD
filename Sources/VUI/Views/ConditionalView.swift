//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// File-scope state class: cannot be nested inside a generic function in Swift.
private final class _ConditionalBranchState {
    var isTrue: Bool? = nil
    var isUpdating = false
    var lastTrueContent: Any? = nil
    var lastFalseContent: Any? = nil
    var activeSubgraph: AGSubgraph? = nil
    var activeLCAttr: Attribute<LayoutComputer>? = nil
    /// Full preferences output of the currently active branch's _makeView result.
    /// Each relay rule reads its key's node(s) from here and forwards the value.
    var activeOutputs: PreferencesOutputs? = nil
}

private final class _ConditionalListBranchState {
    var isTrue: Bool? = nil
    var isUpdating = false
    var lastTrueContent: Any? = nil
    var lastFalseContent: Any? = nil
    var activeSubgraph: AGSubgraph? = nil
    var activeManagedSubgraph: _ViewList_Subgraph? = nil
    var activeListOutputs: _ViewListOutputs? = nil
    // Branch identities stay stable for the lifetime of the conditional list. A branch
    // that re-enters while its outgoing item is retained must recover that item instead
    // of materializing a second subtree at the new presentation position.
    let trueID = UniqueID()
    let falseID = UniqueID()
}

private struct _ConditionalIdentityViewList: ViewList {
    var base: any ViewList
    var id: UniqueID
    var owner: AGAttribute
    var isUnary: Bool
    var reuseID: Int
    var subgraph: _ViewList_Subgraph

    func count(style: _ViewList_IteratorStyle) -> Int {
        base.count(style: style)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        base.estimatedCount(style: style)
    }

    var traitKeys: ViewTraitKeys? { base.traitKeys }
    var traits: ViewTraitCollection { base.traits }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        base.applyNodes(
            from: &from,
            style: style,
            list: list,
            transform: transform.withPushedItem(
                _ConditionalIdentityTransform(
                    id: id,
                    owner: owner,
                    isUnary: isUnary,
                    reuseID: reuseID,
                    subgraph: subgraph
                )
            ),
            to: to
        )
    }
}

private struct _ConditionalIdentityTransform: _ViewList_SublistTransform_Item {
    var id: UniqueID
    var owner: AGAttribute
    var isUnary: Bool
    var reuseID: Int
    var subgraph: _ViewList_Subgraph

    func apply(to sublist: inout _ViewList_Sublist) {
        bindID(&sublist.id)
        sublist.traits[CanTransitionTraitKey.self] = true
        if var elements = sublist.elements as? _ViewList_SubgraphElements {
            elements.wrap(subgraph: subgraph)
            sublist.elements = elements
        } else {
            var elements = _ViewList_SubgraphElements(base: sublist.elements)
            elements.wrap(subgraph: subgraph)
            sublist.elements = elements
        }
    }

    func bindID(_ id: inout _ViewList_ID) {
        id.bind(
            explicitID: self.id,
            owner: owner,
            isUnary: isUnary,
            reuseID: reuseID
        )
    }
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never

    /// Dynamic-subgraph implementation.
    ///
    /// At _makeView time, this iterates inputs.preferences.keys.keys and creates
    /// one relay Attribute per key. Relay node IDs are fixed for the lifetime of
    /// the view; only the rule re-evaluates and forwards a different value when
    /// the branch switches.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let state = _ConditionalBranchState()
        state.activeSubgraph = AGSubgraph()

        func trueBranchValue() -> TrueContent {
            if case let .trueContent(content) = view._attribute.value.storage {
                state.lastTrueContent = content
                return content
            }
            guard let snapshot = state.lastTrueContent as? TrueContent else {
                fatalError("_ConditionalContent lost true branch value during teardown.")
            }
            return snapshot
        }

        func falseBranchValue() -> FalseContent {
            if case let .falseContent(content) = view._attribute.value.storage {
                state.lastFalseContent = content
                return content
            }
            guard let snapshot = state.lastFalseContent as? FalseContent else {
                fatalError("_ConditionalContent lost false branch value during teardown.")
            }
            return snapshot
        }

        func makeTrueBranchView() -> _GraphValue<TrueContent> {
            let attr: Attribute<TrueContent> = AGSubgraph.withCurrent(state.activeSubgraph) {
                graph.makeRule { trueBranchValue() }
            }
            return _GraphValue(_attribute: attr)
        }

        func makeFalseBranchView() -> _GraphValue<FalseContent> {
            let attr: Attribute<FalseContent> = AGSubgraph.withCurrent(state.activeSubgraph) {
                graph.makeRule { falseBranchValue() }
            }
            return _GraphValue(_attribute: attr)
        }

        // Evaluate the initial branch outside any rule to avoid a cycle.
        // If we call _makeView inside the lcAttr rule and then immediately read
        // state.activeLCAttr?.value, the newly created LayoutComputer attribute
        // has no cached value yet, triggering "cycle detected with no cached value".
        do {
            let initialIsTrue: Bool
            if case .trueContent = view._attribute.value.storage { initialIsTrue = true }
            else { initialIsTrue = false }
            state.isTrue = initialIsTrue

            let outputs: _ViewOutputs
            if initialIsTrue {
                _ = trueBranchValue()
                outputs = AGSubgraph.withCurrent(state.activeSubgraph) {
                    TrueContent._makeView(view: makeTrueBranchView(), inputs: inputs)
                }
            } else {
                _ = falseBranchValue()
                outputs = AGSubgraph.withCurrent(state.activeSubgraph) {
                    FalseContent._makeView(view: makeFalseBranchView(), inputs: inputs)
                }
            }
            state.activeLCAttr = outputs._layoutComputer.attribute
            state.activeOutputs = outputs.preferences
        }

        func updateActiveBranchIfNeeded(nowTrue: Bool) {
            guard _AGGraph.current != nil else {
                fatalError("_ConditionalContent branch update evaluated outside an active _AGGraph context.")
            }
            guard state.isTrue != nowTrue else { return }
            guard !state.isUpdating else { return }
            state.isUpdating = true
            state.activeLCAttr = nil
            state.activeOutputs = nil
            state.activeSubgraph?.invalidate()

            let outputs: _ViewOutputs
            if nowTrue {
                _ = trueBranchValue()
                outputs = AGSubgraph.withCurrent(state.activeSubgraph) {
                    TrueContent._makeView(view: makeTrueBranchView(), inputs: inputs)
                }
            } else {
                _ = falseBranchValue()
                outputs = AGSubgraph.withCurrent(state.activeSubgraph) {
                    FalseContent._makeView(view: makeFalseBranchView(), inputs: inputs)
                }
            }
            state.activeLCAttr = outputs._layoutComputer.attribute
            state.activeOutputs = outputs.preferences
            state.isTrue = nowTrue
            state.isUpdating = false
        }

        // Master branch rule: detects branch changes and replaces the active subgraph.
        // On first evaluation state.isTrue == nowTrue, so no _makeView is called here
        // and state.activeLCAttr is already set.
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            guard _AGGraph.current != nil else {
                fatalError("_ConditionalContent rule evaluated outside an active _AGGraph context.")
            }

            let nowTrue: Bool
            if case .trueContent = view._attribute.value.storage { nowTrue = true }
            else { nowTrue = false }

            updateActiveBranchIfNeeded(nowTrue: nowTrue)

            return state.activeLCAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        // Create one relay node per requested preference key.
        // Relay output count follows the input preference key count.
        //
        // SE-0352 implicit existential opening:
        //   Each element of inputs.preferences.keys.keys has type `any PreferenceKey.Type`.
        //   Passing it to addRelay(_:) causes Swift to implicitly open the existential
        //   and bind the concrete type to K.
        var outPrefs = PreferencesOutputs()
        for key in inputs.preferences.keys.keys {
            func addRelay<K: PreferenceKey>(_ k: K.Type) {
                let relayAttr: Attribute<K.Value> = graph.makeRule {
                    let nowTrue: Bool
                    if case .trueContent = view._attribute.value.storage { nowTrue = true }
                    else { nowTrue = false }
                    updateActiveBranchIfNeeded(nowTrue: nowTrue)
                    guard let prefs = state.activeOutputs else { return K.defaultValue }
                    var combined = K.defaultValue
                    for kv in prefs.preferences {
                        guard ObjectIdentifier(kv.key) == ObjectIdentifier(k) else { continue }
                        guard let weakNode = graph.weakAttributeIfValid(for: kv.value),
                              weakNode.isValid(in: graph) else { continue }
                        let val = Attribute<K.Value>(weakNode.toStrong()).value
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

    /// Builds a dynamic list that forwards the currently active branch's list.
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        let state = _ConditionalListBranchState()
        let initialSubgraph = AGSubgraph()
        state.activeSubgraph = initialSubgraph
        state.activeManagedSubgraph = _ViewList_Subgraph(subgraph: initialSubgraph)

        func trueBranchValue() -> TrueContent {
            if case let .trueContent(content) = view._attribute.value.storage {
                state.lastTrueContent = content
                return content
            }
            guard let snapshot = state.lastTrueContent as? TrueContent else {
                fatalError("_ConditionalContent lost true list branch value during teardown.")
            }
            return snapshot
        }

        func falseBranchValue() -> FalseContent {
            if case let .falseContent(content) = view._attribute.value.storage {
                state.lastFalseContent = content
                return content
            }
            guard let snapshot = state.lastFalseContent as? FalseContent else {
                fatalError("_ConditionalContent lost false list branch value during teardown.")
            }
            return snapshot
        }

        func makeTrueBranchView() -> _GraphValue<TrueContent> {
            let attr: Attribute<TrueContent> = AGSubgraph.withCurrent(state.activeSubgraph) {
                graph.makeRule { trueBranchValue() }
            }
            return _GraphValue(_attribute: attr)
        }

        func makeFalseBranchView() -> _GraphValue<FalseContent> {
            let attr: Attribute<FalseContent> = AGSubgraph.withCurrent(state.activeSubgraph) {
                graph.makeRule { falseBranchValue() }
            }
            return _GraphValue(_attribute: attr)
        }

        func makeBranchOutputs(isTrue: Bool) -> _ViewListOutputs {
            if isTrue {
                _ = trueBranchValue()
                return AGSubgraph.withCurrent(state.activeSubgraph) {
                    TrueContent._makeViewList(view: makeTrueBranchView(), inputs: inputs)
                }
            } else {
                _ = falseBranchValue()
                return AGSubgraph.withCurrent(state.activeSubgraph) {
                    FalseContent._makeViewList(view: makeFalseBranchView(), inputs: inputs)
                }
            }
        }

        do {
            let initialIsTrue: Bool
            if case .trueContent = view._attribute.value.storage { initialIsTrue = true }
            else { initialIsTrue = false }
            state.isTrue = initialIsTrue
            state.activeListOutputs = makeBranchOutputs(isTrue: initialIsTrue)
        }

        func updateActiveBranchIfNeeded(nowTrue: Bool) {
            guard _AGGraph.current != nil else {
                fatalError("_ConditionalContent list branch update evaluated outside an active _AGGraph context.")
            }
            guard state.isTrue != nowTrue else { return }
            guard !state.isUpdating else { return }
            state.isUpdating = true
            state.activeListOutputs = nil
            state.activeManagedSubgraph?.release()
            let nextSubgraph = AGSubgraph()
            state.activeSubgraph = nextSubgraph
            state.activeManagedSubgraph = _ViewList_Subgraph(subgraph: nextSubgraph)
            state.activeListOutputs = makeBranchOutputs(isTrue: nowTrue)
            state.isTrue = nowTrue
            state.isUpdating = false
        }

        func resolvedList(from outputs: _ViewListOutputs) -> any ViewList {
            switch outputs.views {
            case .staticList(let elements):
                return BaseViewList(elements: elements)
            case .dynamicList(let listAttr, _):
                return listAttr.value
            }
        }

        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            let nowTrue: Bool
            if case .trueContent = view._attribute.value.storage { nowTrue = true }
            else { nowTrue = false }

            updateActiveBranchIfNeeded(nowTrue: nowTrue)

            guard let outputs = state.activeListOutputs else {
                return EmptyViewList()
            }
            guard let activeManagedSubgraph = state.activeManagedSubgraph else {
                fatalError("_ConditionalContent lost its active list subgraph.")
            }
            let activeType: Any.Type = nowTrue ? TrueContent.self : FalseContent.self
            return _ConditionalIdentityViewList(
                base: resolvedList(from: outputs),
                id: nowTrue ? state.trueID : state.falseID,
                owner: view._attribute.identifier,
                isUnary: outputs.staticCount == 1,
                reuseID: Int(bitPattern: ObjectIdentifier(activeType)),
                subgraph: activeManagedSubgraph
            )
        }

        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: 0,
            staticCount: nil
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

extension _ConditionalContent: PrimitiveView where Self: View {
}
