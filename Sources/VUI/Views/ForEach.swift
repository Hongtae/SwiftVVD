//
//  File: ForEach.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//


public struct ForEach<Data, ID, Content> where Data: RandomAccessCollection, ID: Hashable {
    public var data: Data
    public var content: (Data.Element) -> Content
    let id: KeyPath<Data.Element, ID>
}

extension ForEach: View where Content: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let rootAttr: Attribute<VStackLayout> = graph.makeRule { VStackLayout() }
        return VStackLayout._makeLayoutView(
            root: _GraphValue(_attribute: rootAttr),
            inputs: inputs
        ) { _, _ in
            Self._makeViewList(view: view, inputs: _ViewListInputs(from: inputs))
        }
    }

    // ForEach returns .dynamicList(Attribute<any ViewList>, nil) wrapping a ForEachList.
    // ForEachList.applyNodes calls `to` once per data item (per-item sublist).
    public static func _makeViewList(view: _GraphValue<ForEach<Data, ID, Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        if view._attribute.value.data is any _ForEachSectionCollectionViewListProducing {
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                guard let sectionData = view._attribute.value.data as? any _ForEachSectionCollectionViewListProducing else {
                    return EmptyViewList() as any ViewList
                }
                let outputs = sectionData.makeViewList(inputs: inputs, graph: graph)
                switch outputs.views {
                case .staticList(let elements):
                    return BaseViewList(elements: elements) as any ViewList
                case .dynamicList(let attribute, _):
                    return attribute.value
                }
            }
            return _ViewListOutputs(
                views: .dynamicList(viewListAttr, nil),
                nextImplicitID: 0,
                staticCount: nil
            )
        }

        let state = ForEachState<Data, ID, Content>(inputs: inputs)
        let infoAttr: Attribute<ForEachState<Data, ID, Content>.Info> = graph.makeRule(
            ForEachState<Data, ID, Content>.Info.Init(
                _view: view._attribute,
                state: state
            )
        )
        state.info = infoAttr

        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            guard let graph = _AGGraph.current else {
                fatalError("ForEach viewList rule evaluated outside an active _AGGraph context.")
            }
            let info = infoAttr.value
            guard let forEach = info.state.view else {
                return EmptyViewList() as any ViewList
            }

            // Collect current IDs in data order.
            var newOrder: [(id: ID, index: Data.Index)] = []
            var newIDs: Set<ID> = []
            var dataIdx = forEach.data.startIndex
            while dataIdx != forEach.data.endIndex {
                let element = forEach.data[dataIdx]
                let id = element[keyPath: forEach.id]
                newOrder.append((id, dataIdx))
                newIDs.insert(id)
                dataIdx = forEach.data.index(after: dataIdx)
            }

            // Drop entries that are no longer present.
            // Invalidating the item's AGSubgraph removes all its AG nodes at once.
            for id in state.order where !newIDs.contains(id) {
                state.items[id]?.invalidate()
                state.items.removeValue(forKey: id)
            }

            // Create content Attributes for newly seen IDs.
            // Each item's nodes are registered to a dedicated AGSubgraph so they can
            // be cleanly removed when the item disappears from the data source.
            for (id, index) in newOrder {
                if state.items[id] == nil {
                    let subgraph = AGSubgraph()
                    let managedSubgraph = _ViewList_Subgraph(subgraph: subgraph)
                    let item = ForEachState<Data, ID, Content>.Item(
                        id: id,
                        index: index,
                        seed: info.seed,
                        elements: _ViewList_SubgraphElements(
                            base: EmptyViewListElements()
                        ),
                        subgraph: managedSubgraph,
                        traitListAttr: inputs._traits
                    )
                    // The child source rule may be evaluated while its view-list
                    // output is being built, so identity/index/generation must be
                    // visible before constructing that output.
                    state.items[id] = item
                    let contentAttr: Attribute<Content> = AGSubgraph.withCurrent(subgraph) {
                        graph.makeStatefulRule(
                            ForEachChild<Data, ID, Content>(
                                _info: infoAttr,
                                id: id
                            )
                        )
                    }
                    let contentView = _GraphValue(_attribute: contentAttr)
                    let traitListAttr = AGSubgraph.withCurrent(subgraph) {
                        Self.makeContentTraitListAttr(
                            view: contentView,
                            inputs: inputs,
                            graph: graph
                        )
                    }
                    let generator = TypedUnaryViewGenerator(
                        contentView,
                        inputs: inputs
                    )
                    var elements = _ViewList_SubgraphElements(base: UnaryElements(generator: generator))
                    elements.wrap(subgraph: managedSubgraph)
                    item.elements = elements
                    item.traitListAttr = traitListAttr
                }
            }

            state.order = newOrder.map(\.id)
            return ForEachList(state: state, seed: info.seed)
        }

        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }

    private static func makeContentTraitListAttr(
        view: _GraphValue<Content>,
        inputs: _ViewListInputs,
        graph: _AGGraph
    ) -> OptionalAttribute<ViewTraitCollection> {
        let outputs = Content._makeViewList(view: view, inputs: inputs)
        guard case .dynamicList(let listAttr, _) = outputs.views else {
            return inputs._traits
        }

        // Dynamic trait writers publish their child traits through a ViewList.
        let traitsAttr: Attribute<ViewTraitCollection> = graph.makeRule {
            let list = listAttr.value
            var traits = list.traits
            _ = _forEachSublist(in: list, listAttribute: listAttr) { sublist in
                traits = sublist.traits
                return false
            }
            return traits
        }
        return OptionalAttribute(traitsAttr)
    }
}

extension ForEach: PrimitiveView where ForEach: View {
}

// MARK: - ForEachState

/// Per-ForEach state class. Holds per-item subgraph elements.
/// Stores the per-item elements, subgraph, and trait attribute.
final class ForEachState<Data, ID, Content>
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    struct Info {
        var state: ForEachState
        var seed: UInt32

        struct Init: Rule {
            var _view: Attribute<ForEach<Data, ID, Content>>
            var state: ForEachState

            var value: Info {
                state.update(view: _view.value)
                return Info(state: state, seed: state.seed)
            }
        }
    }

    final class Item {
        let id: ID
        var index: Data.Index
        var seed: UInt32
        var elements: _ViewList_SubgraphElements
        var subgraph: _ViewList_Subgraph
        var traitListAttr: OptionalAttribute<ViewTraitCollection>

        init(
            id: ID,
            index: Data.Index,
            seed: UInt32,
            elements: _ViewList_SubgraphElements,
            subgraph: _ViewList_Subgraph,
            traitListAttr: OptionalAttribute<ViewTraitCollection>
        ) {
            self.id = id
            self.index = index
            self.seed = seed
            self.elements = elements
            self.subgraph = subgraph
            self.traitListAttr = traitListAttr
        }

        var traits: ViewTraitCollection {
            traitListAttr.attribute?.value ?? ViewTraitCollection()
        }

        func invalidate() {
            subgraph.release()
        }
    }

    var inputs: _ViewListInputs
    var info: Attribute<Info>?
    var view: ForEach<Data, ID, Content>?
    var items: [ID: Item] = [:]
    var order: [ID] = []
    var seed: UInt32 = 0

    init(inputs: _ViewListInputs) {
        self.inputs = inputs
    }

    func update(view: ForEach<Data, ID, Content>) {
        self.view = view
        seed &+= 1

        var index = view.data.startIndex
        while index != view.data.endIndex {
            let element = view.data[index]
            let id = element[keyPath: view.id]
            if let item = items[id] {
                item.index = index
                item.seed = seed
            }
            index = view.data.index(after: index)
        }
    }
}

private struct ForEachChild<Data, ID, Content>: StatefulRule
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    typealias Value = Content

    var _info: Attribute<ForEachState<Data, ID, Content>.Info>
    var id: ID

    mutating func updateValue() {
        let info = _info.value
        guard let item = info.state.items[id],
              item.seed == info.seed,
              let forEach = info.state.view else {
            return
        }
        _AGGraph.setStatefulOutput(forEach.content(forEach.data[item.index]))
    }
}

// MARK: - ForEachList

/// ViewList produced by ForEach._makeViewList.
/// applyNodes iterates data items in order and calls `to` callback once per item with
/// _ViewList_Sublist { count=1, elements=_ViewList_SubgraphElements { base=UnaryElements } }.
struct ForEachList<Data, ID, Content>: ViewList
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    var state: ForEachState<Data, ID, Content>
    var seed: UInt32

    func count(style: _ViewList_IteratorStyle) -> Int { state.order.count }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { state.order.count }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for id in state.order {
            guard let item = state.items[id] else { continue }
            if from > 0 {
                from -= 1
                continue
            }
            let sublist = _ViewList_Sublist(
                start: 0,
                count: 1,
                id: _ViewList_ID(explicitID: AnyHashable(id)),
                elements: item.elements,
                traits: item.traits,
                list: list
            )
            let cont = to(&from, style, .sublist(sublist), transform)
            from = 0
            if !cont { return false }
        }
        return true
    }
}

@available(*, unavailable)
extension ForEach: Sendable {
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Content: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.id = id
    }
}

extension ForEach where Content: View {
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable, C.Index: Hashable {
        self.init(data, id: \.id, content: content)
    }

    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection, C: RandomAccessCollection, C.Index: Hashable {
        let elementIDs = data.wrappedValue.indices.lazy.map { index in
            (index, data.wrappedValue[index][keyPath: id])
        }
        self.init(elementIDs, id: \.1) { (index, _) in
            let elementBinding = Binding {
                data.wrappedValue[index]
            } set: {
                data.wrappedValue[index] = $0
            }
            content(elementBinding)
        }
    }
}

extension ForEach where Data == ForEachSectionCollection<Content>, ID == SectionConfiguration.ID, Content: View {
    public init<V>(
        sections view: V,
        @ViewBuilder content: @escaping (SectionConfiguration) -> Content
    ) where V: View {
        self.init(
            ForEachSectionCollection(subviewOf: view, content: content),
            id: \.id,
            content: content
        )
    }
}

extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    // Range-based initializer.
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension ForEach: DynamicViewContent where Content: View {
}

public protocol DynamicViewContent<Data>: View {
    associatedtype Data: Collection
    var data: Self.Data { get }
}

extension ModifiedContent: DynamicViewContent where Content: DynamicViewContent, Modifier: ViewModifier {
    public var data: Content.Data {
        content.data
    }

    public typealias Data = Content.Data
}

private extension ForEach where Content: View {
    struct _Accessor {
        let forEach: ForEach
        subscript(index: Int) -> Content {
            let index = forEach.data.index(forEach.data.startIndex, offsetBy: index)
            return forEach.content(forEach.data[index])
        }
    }
    var _accessor: _Accessor { .init(forEach: self) }
}
