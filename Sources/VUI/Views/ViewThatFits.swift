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

        func extractGenerators(_ elements: ViewListElements) -> [TypedUnaryViewGenerator] {
            switch elements {
            case .unary(let gen): return [gen]
            case .merged(let outputs):
                return outputs.flatMap { output -> [TypedUnaryViewGenerator] in
                    guard case .staticList(let els) = output.views else { return [] }
                    return extractGenerators(els)
                }
            case .modified(let base, _):
                return extractGenerators(base)
            }
        }

        let generators: [TypedUnaryViewGenerator]
        switch childListOutputs.views {
        case .staticList(let elements):
            generators = extractGenerators(elements)
        case .dynamicList(let viewListAttr, _):
            generators = viewListAttr.value.generators
        }

        var layoutPairs: [Attribute<LayoutComputer>] = []
        for gen in generators {
            let posAttr = graph.makeInput(value: CGPoint.zero)
            let sizeAttr = graph.makeInput(value: ViewSize(.zero))
            let childInputs = _ViewInputs(
                base: gen.baseInputs,
                preferences: inputs.preferences,
                transform: inputs.transform,
                position: posAttr,
                containerPosition: inputs.position,
                size: sizeAttr,
                safeAreaInsets: inputs.safeAreaInsets,
                containerSize: OptionalAttribute(inputs.size)
            )
            if let childOutputs = gen.makeView(inputs: childInputs),
               let lcAttr = childOutputs._layoutComputer.attribute {
                
                let wrapperLC: Attribute<LayoutComputer> = graph.makeRule {
                    let innerLC = lcAttr.value
                    return LayoutComputer(
                        sizeThatFits: innerLC._sizeThatFits,
                        spacing: innerLC._spacing,
                        dimensions: innerLC._dimensions,
                        place: { position, anchor, proposal in
                            posAttr.setValue(position)
                            let resolvedSize = innerLC.sizeThatFits(proposal)
                            sizeAttr.setValue(ViewSize(resolvedSize))
                            innerLC.place(at: position, anchor: anchor, proposal: proposal)
                        }
                    )
                }
                layoutPairs.append(wrapperLC)
            }
        }

        let layoutComputerAttr: Attribute<LayoutComputer> = graph.makeRule {
            let fittingRoot = root._attribute.value   // dep: axes
            let axes = fittingRoot.axes
            let childLCs = layoutPairs.map { $0.value }   // dep: all children

            let subviewProxies = layoutPairs.map { lc in
                LayoutSubviewProxy(layoutComputerAttr: lc)
            }
            let subviews = LayoutSubviews(
                subviews: subviewProxies.map { LayoutSubview(proxy: $0) },
                layoutDirection: .leftToRight
            )

            // Returns the index of the first child whose natural size fits within
            // the constrained axes of the proposal, or the last child as a fallback.
            func selectIndex(for proposal: ProposedViewSize) -> Int? {
                guard !childLCs.isEmpty else { return nil }
                for (i, lc) in childLCs.enumerated() {
                    let size = lc.sizeThatFits(proposal)
                    var fits = true
                    if axes.contains(.horizontal) {
                        if let w = proposal.width, size.width > w + 1e-6 { fits = false }
                    }
                    if axes.contains(.vertical) {
                        if let h = proposal.height, size.height > h + 1e-6 { fits = false }
                    }
                    if fits { return i }
                }
                return childLCs.indices.last
            }

            return LayoutComputer(
                sizeThatFits: { proposal in
                    guard let i = selectIndex(for: proposal) else { return .zero }
                    return childLCs[i].sizeThatFits(proposal)
                },
                dimensions: { proposal in
                    guard let i = selectIndex(for: proposal) else {
                        return ViewDimensions(width: 0, height: 0)
                    }
                    return childLCs[i].dimensions(in: proposal)
                },
                place: { position, anchor, proposal in
                    guard let i = selectIndex(for: proposal) else { return }
                    subviews[i].place(at: position, anchor: anchor, proposal: proposal)
                }
            )
        }

        return _ViewOutputs(
            preferences: PreferencesOutputs(),
            layoutComputer: OptionalAttribute(layoutComputerAttr)
        )
    }

    public typealias Body = Never
}
