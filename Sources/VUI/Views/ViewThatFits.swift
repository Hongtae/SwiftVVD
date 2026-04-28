//
//  File: ViewThatFits.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

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

extension ViewThatFits: _PrimitiveView {
}

public struct _SizeFittingRoot: _VariadicView.UnaryViewRoot {
    var axes: Axis.Set
    init(axes: Axis.Set) { self.axes = axes }

    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let childListOutputs = body(_Graph(), inputs)
        let viewListAttr: Attribute<any ViewList>
        switch childListOutputs.views {
        case .staticList(let elements):
            viewListAttr = graph.makeInput(value: BaseViewList(elements: elements))
        case .dynamicList(let dynamicListAttr, _):
            viewListAttr = dynamicListAttr
        }

        let state = SizeFittingState(root: root._attribute, list: viewListAttr, inputs: inputs)
        let layoutComputerAttr: Attribute<LayoutComputer> = graph.makeStatefulRule(
            SizeFittingLayoutComputer(state: state)
        )

        return _ViewOutputs(
            preferences: PreferencesOutputs(),
            layoutComputer: OptionalAttribute(layoutComputerAttr)
        )
    }

    public typealias Body = Never
}

private final class SizeFittingState {
    let root: Attribute<_SizeFittingRoot>
    let list: Attribute<any ViewList>
    let inputs: _ViewInputs
    var children: [_ViewList_ID.Canonical: Child] = [:]

    // FIXME: SizeFittingState may need to retain placeholder _ViewOutputs once
    // PlatformViewThatFitsRepresentable is added.
    init(root: Attribute<_SizeFittingRoot>, list: Attribute<any ViewList>, inputs: _ViewInputs) {
        self.root = root
        self.list = list
        self.inputs = inputs
    }

    final class Child {
        let subgraph: AGSubgraph
        var releaseElements: _ViewList_SubgraphRelease?
        var outputs: _ViewOutputs
        var layoutComputer: Attribute<LayoutComputer>?

        init(
            subgraph: AGSubgraph,
            releaseElements: _ViewList_SubgraphRelease?,
            outputs: _ViewOutputs,
            layoutComputer: Attribute<LayoutComputer>?
        ) {
            self.subgraph = subgraph
            self.releaseElements = releaseElements
            self.outputs = outputs
            self.layoutComputer = layoutComputer
        }
    }

    // FIXME: Revisit the callback shape when Engine callbacks are wired.
    func applyChildren(selectLast: Bool, to body: (_ViewOutputs, Bool) -> Bool) {
        let children = materializedChildren()
        guard !children.isEmpty else { return }
        for (index, child) in children.enumerated() {
            let isLast = index == children.index(before: children.endIndex)
            let selected = body(child.outputs, isLast)
            if selected && !selectLast { return }
        }
    }

    func materializedChildren() -> [Child] {
        guard let graph = AttributeGraph.current else {
            fatalError("SizeFittingState.materializedChildren called outside AG context.")
        }

        var from = 0
        var ordered: [Child] = []
        var liveIDs = Set<_ViewList_ID.Canonical>()
        let currentList = list.value
        _ = _applySublists(in: currentList, from: &from, listAttribute: list) { sublist in
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex).canonicalID
                liveIDs.insert(id)
                let child = children[id] ?? makeChild(
                    id: id,
                    sublist: sublist,
                    offset: offset,
                    in: graph
                )
                children[id] = child
                ordered.append(child)
            }
            return true
        }

        let staleIDs = children.keys.filter { !liveIDs.contains($0) }
        for id in staleIDs {
            guard let child = children[id] else { continue }
            child.subgraph.invalidate()
            child.subgraph.removeFromParent()
            children.removeValue(forKey: id)
        }
        return ordered
    }

    func invalidate() {
        for child in children.values {
            child.subgraph.invalidate()
            child.subgraph.removeFromParent()
        }
        children.removeAll()
    }

    private func makeChild(
        id: _ViewList_ID.Canonical,
        sublist: _ViewList_Sublist,
        offset: Int,
        in graph: AttributeGraph
    ) -> Child {
        let subgraph = AGSubgraph()
        let posAttr = graph.makeInput(value: CGPoint.zero)
        let sizeAttr = graph.makeInput(value: ViewSize(.zero))
        let release = (sublist.elements as? _ViewList_SubgraphElements)?.retain()
        var baseInputs = inputs
        baseInputs.copyCaches()

        let outputs = AGSubgraph.$current.withValue(subgraph) {
            sublist.elements.makeOneElement(at: offset, inputs: baseInputs) { elementInputs, makeView in
                var childInputs = elementInputs
                childInputs.position = posAttr
                childInputs.size = sizeAttr
                childInputs.transform = inputs.transform
                childInputs.containerPosition = inputs.position
                childInputs.safeAreaInsets = inputs.safeAreaInsets
                childInputs.containerSize = OptionalAttribute(inputs.size)
                return makeView(childInputs)
            }
        } ?? _ViewOutputs()

        let wrappedLC: Attribute<LayoutComputer>?
        if let lcAttr = outputs._layoutComputer.attribute {
            wrappedLC = graph.makeRule {
                let innerLC = lcAttr.value
                return LayoutComputer(
                    sizeThatFits: { innerLC.sizeThatFits($0) },
                    spacing: innerLC.spacing,
                    place: { position, anchor, proposal in
                        let resolvedSize = innerLC.sizeThatFits(proposal)
                        let origin = CGPoint(
                            x: position.x - resolvedSize.width * anchor.x,
                            y: position.y - resolvedSize.height * anchor.y
                        )
                        posAttr.setValue(origin)
                        sizeAttr.setValue(ViewSize(resolvedSize))
                        innerLC.place(at: position, anchor: anchor, proposal: proposal)
                    },
                    explicitAlignment: { innerLC.explicitAlignment($0, at: $1) }
                )
            }
        } else {
            wrappedLC = nil
        }

        var wrappedOutputs = outputs
        if let wrappedLC {
            wrappedOutputs._layoutComputer = OptionalAttribute(wrappedLC)
        }
        _ = id
        return Child(
            subgraph: subgraph,
            releaseElements: release,
            outputs: wrappedOutputs,
            layoutComputer: wrappedLC
        )
    }
}

private struct SizeFittingLayoutComputer: StatefulRule {
    typealias Value = LayoutComputer
    var state: SizeFittingState

    mutating func updateValue() {
        let capturedState = state
        let axes = capturedState.root.value.axes
        let computer = LayoutComputer(
            sizeThatFits: { proposal in
                guard let child = SizeFittingLayoutComputer.selectChild(state: capturedState, axes: axes, proposal: proposal),
                      let lc = child.layoutComputer?.value else { return .zero }
                return lc.sizeThatFits(proposal)
            },
            spacing: {
                capturedState.materializedChildren().first?.layoutComputer?.value.spacing ?? ViewSpacing()
            }(),
            place: { position, anchor, proposal in
                guard let child = SizeFittingLayoutComputer.selectChild(state: capturedState, axes: axes, proposal: proposal),
                      let lc = child.layoutComputer?.value else { return }
                lc.place(at: position, anchor: anchor, proposal: proposal)
            },
            explicitAlignment: { key, size in
                guard let child = SizeFittingLayoutComputer.selectChild(state: capturedState, axes: axes, proposal: size.proposal),
                      let lc = child.layoutComputer?.value else { return nil }
                return lc.explicitAlignment(key, at: size)
            }
        )
        AttributeGraph.setStatefulOutput(computer)
    }

    private static func selectChild(
        state: SizeFittingState,
        axes: Axis.Set,
        proposal: ProposedViewSize
    ) -> SizeFittingState.Child? {
        let children = state.materializedChildren()
        guard !children.isEmpty else { return nil }
        var naturalProposal = proposal
        if axes.contains(.horizontal) { naturalProposal.width = nil }
        if axes.contains(.vertical) { naturalProposal.height = nil }

        for child in children {
            guard let lc = child.layoutComputer?.value else { continue }
            let size = lc.sizeThatFits(naturalProposal)
            var fits = true
            if axes.contains(.horizontal), let width = proposal.width, size.width > width + 1e-6 {
                fits = false
            }
            if axes.contains(.vertical), let height = proposal.height, size.height > height + 1e-6 {
                fits = false
            }
            if fits { return child }
        }
        return children.last
    }
}
