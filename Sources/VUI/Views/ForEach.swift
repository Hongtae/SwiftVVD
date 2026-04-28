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
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
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
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        let state = ForEachState<Data, ID, Content>(inputs: inputs)

        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            guard let graph = AttributeGraph.current else {
                fatalError("ForEach viewList rule evaluated outside an active AttributeGraph context.")
            }
            let forEach = view._attribute.value   // dep: data / content changes

            // Collect current IDs in data order.
            var newOrder: [AnyHashable] = []
            var newIDs: Set<AnyHashable> = []
            var dataIdx = forEach.data.startIndex
            while dataIdx != forEach.data.endIndex {
                let element = forEach.data[dataIdx]
                let id = AnyHashable(element[keyPath: forEach.id])
                newOrder.append(id)
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
            dataIdx = forEach.data.startIndex
            for id in newOrder {
                let element = forEach.data[dataIdx]
                dataIdx = forEach.data.index(after: dataIdx)

                if state.items[id] == nil {
                    let subgraph = AGSubgraph()
                    let contentAttr: Attribute<Content> = AGSubgraph.$current.withValue(subgraph) {
                        graph.makeRule {
                            let fe = view._attribute.value
                            var si = fe.data.startIndex
                            while si != fe.data.endIndex {
                                let e = fe.data[si]
                                if AnyHashable(e[keyPath: fe.id]) == id {
                                    return fe.content(e)
                                }
                                si = fe.data.index(after: si)
                            }
                            return forEach.content(element)  // stale fallback if ID removed
                        }
                    }
                    let generator = TypedUnaryViewGenerator(
                        _GraphValue(_attribute: contentAttr),
                        inputs: inputs
                    )
                    var elements = _ViewList_SubgraphElements(base: UnaryElements(generator: generator))
                    elements.wrap(subgraph: _ViewList_Subgraph(subgraph: subgraph))
                    state.items[id] = ForEachState<Data, ID, Content>.Item(
                        elements: elements,
                        subgraph: subgraph,
                        traitListAttr: generator.traitListAttr
                    )
                }
            }

            state.order = newOrder
            state.seed &+= 1
            return ForEachList(state: state, seed: state.seed)
        }

        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }
}

// MARK: - ForEachState

/// Per-ForEach state class. Holds per-item subgraph elements.
final class ForEachState<Data, ID, Content>
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    struct Item {
        var elements: _ViewList_SubgraphElements
        var subgraph: AGSubgraph
        var traitListAttr: OptionalAttribute<ViewTraitCollection>

        var traits: ViewTraitCollection {
            traitListAttr.attribute?.value ?? ViewTraitCollection()
        }

        func invalidate() {
            subgraph.invalidate()
            subgraph.removeFromParent()
        }
    }

    var inputs: _ViewListInputs
    var items: [AnyHashable: Item] = [:]
    var order: [AnyHashable] = []
    var seed: UInt32 = 0

    init(inputs: _ViewListInputs) {
        self.inputs = inputs
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
        for (offset, id) in state.order.enumerated() {
            guard let item = state.items[id] else { continue }
            if from > 0 { from -= 1; continue }
            let sublist = _ViewList_Sublist(
                start: offset,
                count: 1,
                id: _ViewList_ID(implicitID: 0),
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

extension ForEach: _PrimitiveView where ForEach: View {
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

extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    // requires_constant_range
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension ForEach: DynamicViewContent where Content: View {
}

public protocol DynamicViewContent: View {
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
