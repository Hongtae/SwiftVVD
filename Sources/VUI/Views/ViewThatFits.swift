//
//  File: ViewThatFits.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Selects the first child whose natural size fits the proposed dimensions.
public struct ViewThatFits<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_SizeFittingRoot, Content>
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        _tree = .init(root: _SizeFittingRoot(axes: axes), content: content())
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_SizeFittingRoot, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension ViewThatFits: PrimitiveView, UnaryView {
}

/// Bridges a variadic child list into retained fitting candidates and indirect outputs.
public struct _SizeFittingRoot: _VariadicView.UnaryViewRoot {
    var axes: Axis.Set
    init(axes: Axis.Set) { self.axes = axes }

    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        guard let parentSubgraph = AGSubgraph.current else {
            fatalError("\(self)._makeView requires a current parent subgraph.")
        }

        let childListOutputs = body(_Graph(), inputs)
        let viewList = childListOutputs.makeAttribute(inputs: inputs.listInputs)

        // The returned channels remain indirect so selecting a candidate only
        // rewires targets. Candidate materialization still receives the original
        // request bits and therefore produces its own layout computer.
        var placeholderInputs = inputs
        placeholderInputs.requestsLayoutComputer = false
        var outputs = placeholderInputs.makeIndirectOutputs()
        let state = SizeFittingState(
            root: root._attribute,
            list: viewList,
            inputs: inputs,
            outputs: outputs,
            parentSubgraph: parentSubgraph
        )

        let mux: Attribute<()> = graph.makeStatefulRule(
            SizeFittingMux(state: state)
        )
        outputs.setIndirectDependency(mux.identifier)

        if inputs.requestsLayoutComputer {
            let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                SizeFittingLayoutComputer(state: state)
            )
            outputs._layoutComputer = OptionalAttribute(layoutComputer)
        }
        return outputs
    }

    public typealias Body = Never
}

/// Owns fitting-candidate subgraphs and connects the selected child's outputs.
private final class SizeFittingState {
    /// Retains one materialized candidate and its current traversal state.
    struct Child {
        var subgraph: AGSubgraph
        var release: _ViewList_SubgraphRelease?
        var outputs: _ViewOutputs
        var seed: UInt32
        var order: UInt32
        var isInserted: Bool
    }

    var _root: Attribute<_SizeFittingRoot>
    var _list: Attribute<any ViewList>
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var parentSubgraph: AGSubgraph
    var children: [_ViewList_ID.Canonical: Child]
    var seed: UInt32

    init(
        root: Attribute<_SizeFittingRoot>,
        list: Attribute<any ViewList>,
        inputs: _ViewInputs,
        outputs: _ViewOutputs,
        parentSubgraph: AGSubgraph
    ) {
        self._root = root
        self._list = list
        self.inputs = inputs
        self.outputs = outputs
        self.parentSubgraph = parentSubgraph
        self.children = [:]
        self.seed = 0
    }

    /// Reconciles candidate identities and optionally commits the first match.
    ///
    /// Traversal continues after a match so an already-inserted later candidate
    /// remains live until the commit pass removes it. Detached or unmaterialized
    /// later candidates are skipped and generation pruning releases them.
    func applyChildren(selectLast: Bool, to body: (_ViewOutputs, Bool) -> Bool) {
        guard _AGGraph.current != nil else {
            fatalError("SizeFittingState.applyChildren called outside AG context.")
        }

        seed &+= 1
        let currentSeed = seed
        let currentList = _list.value
        let count = currentList.count(style: _ViewList_IteratorStyle())
        var from = 0
        var order: UInt32 = 0
        var selectedOrder: UInt32?

        _ = _applySublists(in: currentList, from: &from, listAttribute: _list) { sublist in
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex).canonicalID

                // Once a candidate matches, only the branch that is currently
                // inserted is refreshed. This allows a later displayed branch
                // to survive until commit without materializing every fallback.
                let existing = children[id]
                if existing?.isInserted == true || selectedOrder == nil {
                    var child = existing ?? makeChild(
                        sublist: sublist,
                        offset: offset
                    )
                    child.seed = currentSeed
                    child.order = order
                    children[id] = child

                    if selectedOrder == nil {
                        let isLast = Int(order) == count - 1
                        if body(child.outputs, isLast) {
                            selectedOrder = order
                        }
                    }
                }
                order &+= 1
            }
            return true
        }

        let staleIDs = children.compactMap { id, child in
            child.seed == currentSeed ? nil : id
        }
        for id in staleIDs {
            eraseChild(id, invalidating: true)
        }

        // Measurement and preference folds use selectLast == false. They may
        // populate the cache but must not retarget the displayed output.
        if selectLast, let selectedOrder {
            commitSelection(selectedOrder)
        }
    }

    func invalidate() {
        guard _AGGraph.current != nil else {
            fatalError("SizeFittingState.invalidate called outside AG context.")
        }
        outputs.detachIndirectOutputs()
        for id in Array(children.keys) {
            eraseChild(id, invalidating: true)
        }
    }

    /// Applies the selected order to each retained child and rewires outputs.
    private func commitSelection(_ selectedOrder: UInt32) {
        for id in Array(children.keys) {
            guard var child = children[id] else {
                continue
            }
            let shouldInsert = child.order == selectedOrder
            guard child.isInserted != shouldInsert else {
                continue
            }

            child.isInserted = shouldInsert
            children[id] = child
            if shouldInsert {
                parentSubgraph.addSecondaryChild(child.subgraph)
                child.subgraph.didReinsert()
                child.outputs.attachIndirectOutputs(to: outputs)
            } else {
                child.subgraph.willRemove()
                child.subgraph.removeFromParent()
            }
        }
    }

    /// Materializes one candidate in a detached subgraph for later selection.
    private func makeChild(
        sublist: _ViewList_Sublist,
        offset: Int
    ) -> Child {
        // Candidate nodes are born detached. Only the chosen candidate is added
        // to the parent subgraph; detached candidates remain measurable.
        let subgraph = AGSubgraph(parent: nil)
        let release = sublist.elements.retain()
        var childInputs = inputs
        childInputs.copyCaches()
        let outputs = AGSubgraph.withCurrent(subgraph) {
            sublist.elements.makeOneElement(at: offset, inputs: childInputs) { elementInputs, makeView in
                makeView(elementInputs)
            }
        }
        guard let outputs else {
            fatalError("ViewThatFits requires each fitting candidate to materialize one element.")
        }

        return Child(
            subgraph: subgraph,
            release: release,
            outputs: outputs,
            seed: seed,
            order: 0,
            isInserted: false
        )
    }

    private func eraseChild(
        _ id: _ViewList_ID.Canonical,
        invalidating: Bool
    ) {
        guard var child = children.removeValue(forKey: id) else {
            return
        }
        if child.isInserted {
            child.subgraph.willRemove()
            child.subgraph.removeFromParent()
            child.isInserted = false
        }
        if invalidating, AGSubgraphIsValid(child.subgraph) {
            child.subgraph.invalidate()
        }
        child.release = nil
    }
}

/// Observes the outer proposal and selects the rendered fitting candidate.
private struct SizeFittingMux: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = ()
    var state: SizeFittingState

    mutating func updateValue() {
        let proposal = state.inputs.size.value.proposal
        state.applyChildren(selectLast: true) { outputs, isLast in
            let layoutComputer = sizeFittingLayoutComputer(in: outputs)
            let axes = state._root.value.axes
            let measured = layoutComputer.sizeThatFits(
                sizeFittingNaturalProposal(proposal, axes: axes)
            )
            return sizeFittingMeasurement(
                measured,
                fits: proposal,
                axes: axes,
                orIsLast: isLast
            )
        }
        _AGGraph.setStatefulOutput(())
    }

    mutating func destroy() {
        state.invalidate()
    }
}

/// Publishes the proposal-cached layout engine for a size-fitting root.
private struct SizeFittingLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer
    var state: SizeFittingState

    /// Measures candidates and forwards spacing/alignment from the selected one.
    struct Engine: LayoutEngine {
        var root: _SizeFittingRoot
        var ctx: RuleContext<LayoutComputer>
        var state: SizeFittingState
        var sizeCache: ViewSizeCache

        mutating func spacing() -> Spacing {
            var result = Spacing()
            ctx.update {
                state.applyChildren(selectLast: false) { outputs, _ in
                    result = sizeFittingLayoutComputer(in: outputs).spacing()
                    return true
                }
            }
            return result
        }

        mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            var result = CGSize.zero
            ctx.update {
                result = sizeCache.get(proposal) {
                    var measured = CGSize.zero
                    state.applyChildren(selectLast: false) { outputs, isLast in
                        let computer = sizeFittingLayoutComputer(in: outputs)
                        measured = computer.sizeThatFits(
                            sizeFittingNaturalProposal(proposal, axes: root.axes)
                        )
                        return sizeFittingMeasurement(
                            measured,
                            fits: proposal,
                            axes: root.axes,
                            orIsLast: isLast
                        )
                    }
                    return measured
                }
            }
            return result
        }

        mutating func explicitAlignment(
            _ key: AlignmentKey,
            at size: ViewSize
        ) -> CGFloat? {
            var result: CGFloat?
            ctx.update {
                let proposal = size.proposal
                state.applyChildren(selectLast: false) { outputs, isLast in
                    let computer = sizeFittingLayoutComputer(in: outputs)
                    let measured = computer.sizeThatFits(
                        sizeFittingNaturalProposal(proposal, axes: root.axes)
                    )
                    let fits = sizeFittingMeasurement(
                        measured,
                        fits: proposal,
                        axes: root.axes,
                        orIsLast: isLast
                    )
                    if fits {
                        result = computer.explicitAlignment(key, at: size)
                    }
                    return fits
                }
            }
            return result
        }
    }

    mutating func updateValue() {
        update(
            to: Engine(
                root: state._root.value,
                ctx: context,
                state: state,
                sizeCache: ViewSizeCache()
            )
        )
    }
}

private func sizeFittingLayoutComputer(
    in outputs: _ViewOutputs
) -> LayoutComputer {
    outputs._layoutComputer.attribute?.value ?? LayoutComputer.defaultValue
}

private func sizeFittingNaturalProposal(
    _ proposal: _ProposedSize,
    axes: Axis.Set
) -> _ProposedSize {
    var result = proposal
    if axes.contains(.horizontal) {
        result.width = nil
    }
    if axes.contains(.vertical) {
        result.height = nil
    }
    return result
}

private func sizeFittingMeasurement(
    _ size: CGSize,
    fits proposal: _ProposedSize,
    axes: Axis.Set,
    orIsLast isLast: Bool
) -> Bool {
    if isLast {
        return true
    }
    if axes.contains(.horizontal),
       let width = proposal.width,
       size.width > width {
        return false
    }
    if axes.contains(.vertical),
       let height = proposal.height,
       size.height > height {
        return false
    }
    return true
}
