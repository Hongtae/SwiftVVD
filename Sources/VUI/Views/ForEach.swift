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

    // ForEach always returns .dynamicList(Attribute<ViewList>, nil).
    // Per-element state class — holds content-Attribute generator and Subgraph for each ID.
    // Each item's AG nodes are owned by its Subgraph; invalidating it on removal
    // batch-removes all nodes so the graph doesn't accumulate zombie entries.
    private final class _ItemState {
        var generators: [AnyHashable: TypedUnaryViewGenerator] = [:]
        var subgraphs:  [AnyHashable: Subgraph] = [:]
        var order: [AnyHashable] = []
    }

    public static func _makeViewList(view: _GraphValue<ForEach<Data, ID, Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        let state = _ItemState()

        let viewListAttr: Attribute<ViewList> = graph.makeRule {
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
            // Invalidating the item's Subgraph removes all its AG nodes at once.
            for id in state.order where !newIDs.contains(id) {
                state.subgraphs[id]?.invalidate()
                state.subgraphs[id]?.removeFromParent()
                state.subgraphs.removeValue(forKey: id)
                state.generators.removeValue(forKey: id)
            }

            // Create content Attributes for newly seen IDs.
            // Each item's nodes are registered to a dedicated Subgraph so they can
            // be cleanly removed when the item disappears from the data source.
            dataIdx = forEach.data.startIndex
            for id in newOrder {
                let element = forEach.data[dataIdx]
                dataIdx = forEach.data.index(after: dataIdx)

                if state.generators[id] == nil {
                    let subgraph = Subgraph()
                    let contentAttr: Attribute<Content> = Subgraph.$current.withValue(subgraph) {
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
                    state.subgraphs[id] = subgraph
                    state.generators[id] = TypedUnaryViewGenerator(
                        _GraphValue(_attribute: contentAttr),
                        inputs: inputs
                    )
                }
            }

            state.order = newOrder
            return ViewList(generators: newOrder.compactMap { state.generators[$0] })
        }

        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
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

