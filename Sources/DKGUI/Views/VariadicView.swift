//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _VariadicView_Root {
}

public struct _VariadicView_Children : View {
    public typealias Body = Never

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {

        struct Generator : ViewListGenerator {
            let graph: _GraphValue<_VariadicView_Children>
            let inputs: _ViewListInputs

            func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
                if let view = graph.value(atPath: self.graph, from: encloser) {
                    let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                    return (0..<view.elements.count).map { index in
                        Element._makeView(view: self.graph[\.elements[index]], inputs: inputs).view
                    }
                }
                fatalError("Unable to recover view")
                //return []
            }

            func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
                if let view = graph.value(atPath: self.graph, from: encloser) {
                    let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                    var viewList: [_ViewOutputs] = []
                    for index in 0..<view.elements.count {
                        let outputs = Element._makeView(view: self.graph[\.elements[index]], inputs: inputs)
                        viewList.append(outputs)
                    }
                    return viewList.compactMap {
                        $0.view.makeView(encloser: view, graph: self.graph)
                    }
                }
                fatalError("Unable to recover view")
                //return []
            }
        }
        return _ViewListOutputs(viewList: Generator(graph: view, inputs: inputs), preferences: .init(preferences: []))
    }

    let elements: [Element]
}

extension _VariadicView_Children : RandomAccessCollection {
    public struct Element: View, Identifiable {
        public var id: AnyHashable {
            viewID
        }
        public func id<ID>(as _: ID.Type = ID.self) -> ID? where ID: Hashable {
            nil
        }
        public subscript<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
            get {
                if let value = traits[ObjectIdentifier(key)] {
                    return value as! Trait.Value
                }
                return Trait.defaultValue
            }
            set {
                traits[ObjectIdentifier(key)] = newValue
            }
        }
        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            struct Generator : ViewGenerator {
                let graph: _GraphValue<Element>
                var inputs: _ViewInputs
                func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                    if let element = graph.value(atPath: self.graph, from: encloser) {
                        let view = element.view
                        view.merge(graphInputs: self.inputs.base)
                        return view
                    }
                    fatalError("Unable to recover element")
                    //return nil
                }
                mutating func mergeInputs(_ inputs: _GraphInputs) {
                    self.inputs.base.mergedInputs.append(inputs)
                }
            }
            let generator = Generator(graph: view, inputs: inputs)
            return _ViewOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
        }

        public typealias ID = AnyHashable
        public typealias Body = Never

        let view: ViewContext
        var traits: [ObjectIdentifier: Any]
        var viewID: AnyHashable
    }
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public subscript(index: Int) -> Element { elements[index] }

    public typealias Index = Int
    public typealias Iterator = IndexingIterator<_VariadicView_Children>
    public typealias SubSequence = Slice<_VariadicView_Children>
    public typealias Indices = Range<Int>

    init(_ viewList: [ViewContext]) {
        self.elements = viewList.indices.map { index in
            Element(view: viewList[index],  traits: [:], viewID: index)
        }
    }
}

extension _VariadicView_Children : _PrimitiveView {
}

extension _VariadicView_Children.Element : _PrimitiveView {
}

public protocol _VariadicView_ViewRoot : _VariadicView_Root {
    associatedtype Body: View
    @ViewBuilder func body(children: _VariadicView.Children) -> Self.Body

    static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs
    static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
}

extension _VariadicView_ViewRoot where Body == Never {
    public func body(children: _VariadicView.Children) -> Never {
        neverBody()
    }
}

public protocol _VariadicView_UnaryViewRoot : _VariadicView_ViewRoot {
}

public protocol _VariadicView_MultiViewRoot : _VariadicView_ViewRoot {
}

private protocol _VariadicView_ViewRoot_MakeChildren {
    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext]
}

private struct _VariadicView_ViewRoot_MakeChildrenProxy<Root> : _VariadicView_ViewRoot_MakeChildren where Root : _VariadicView_ViewRoot {
    let graph: _GraphValue<Root>
    let body: _ViewListOutputs
    let inputs: _ViewListInputs

    struct Proxy {
        let root: Root
        let views: [ViewContext]
        var children:  _VariadicView.Children {
            _VariadicView.Children(views)
        }
        var body: Root.Body {
            root.body(children: children)
        }
    }

    private struct ProxyGenerator<Generator> : ViewGenerator where Generator : ViewGenerator {
        let proxy: Proxy
        let proxyGraph: _GraphValue<Proxy>
        var generator: Generator
        var graph: _GraphValue<Generator.Content> { generator.graph }
        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            generator.makeView(encloser: proxy, graph: proxyGraph)
        }
        mutating func mergeInputs(_ inputs: _GraphInputs) {
            generator.mergeInputs(inputs)
        }
    }

    func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        let views = body.viewList.makeViewList(encloser: encloser, graph: graph)
        if let root = graph.value(atPath: self.graph, from: encloser) {
            let proxy = Proxy(root: root, views: views)
            let proxyGraph = _GraphValue<Proxy>.root()
            if Root.Body.self is Never.Type {
                let listOutputs = _VariadicView_Children._makeViewList(view: proxyGraph[\.children], inputs: inputs)
                return listOutputs.viewList.makeViewGenerators(encloser: proxy, graph: proxyGraph).map {
                    func makeGenerator<G: ViewGenerator>(gen: G) -> any ViewGenerator {
                        ProxyGenerator(proxy: proxy, proxyGraph: proxyGraph, generator: gen)
                    }
                    return makeGenerator(gen: $0)
                }
            } else {
                let listOutputs = Root.Body._makeViewList(view: proxyGraph[\.body], inputs: inputs)
                return listOutputs.viewList.makeViewGenerators(encloser: proxy, graph: proxyGraph).map {
                    func makeGenerator<G: ViewGenerator>(gen: G) -> any ViewGenerator {
                        ProxyGenerator(proxy: proxy, proxyGraph: proxyGraph, generator: gen)
                    }
                    return makeGenerator(gen: $0)
                }
            }
        }
        fatalError("Unable to recover _VariadicView_ViewRoot")
    }

    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
        makeViewList(encloser: encloser, graph: graph).compactMap {
            $0.makeView(encloser: encloser, graph: graph)
        }
    }
}

extension _VariadicView_ViewRoot_MakeChildrenProxy : ViewGenerator {
    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        fatalError("This method should not be called.")
    }
    func mergeInputs(_: _GraphInputs) {
    }
}

extension _VariadicView_ViewRoot_MakeChildrenProxy : ViewListGenerator {
    func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        makeViewList(encloser: encloser, graph: graph)
    }
    func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
        makeChildren(encloser: encloser, graph: graph)
    }
}

private protocol _VariadicView_ViewRoot_MakeChildren_UnaryViewRoot : ViewListGenerator {
    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext]
}

struct _VariadicView_ViewRoot_MakeChildren_UnaryViewRootProxy<Root> : _VariadicView_ViewRoot_MakeChildren_UnaryViewRoot where Root : _VariadicView_UnaryViewRoot {
    private let proxy: _VariadicView_ViewRoot_MakeChildrenProxy<Root>
    var graph: _GraphValue<Root> { proxy.graph }

    init(graph: _GraphValue<Root>, body: _ViewListOutputs, inputs: _ViewListInputs) {
        self.proxy = .init(graph: graph, body: body, inputs: inputs)
    }

    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
        proxy.makeChildren(encloser: encloser, graph: graph)
    }

    func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        proxy.makeViewGenerators(encloser: encloser, graph: graph)
    }
} 

private protocol _VariadicView_ViewRoot_MakeChildren_MultiViewRoot : ViewGenerator {
    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext]
    func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator]
}

struct _VariadicView_ViewRoot_MakeChildren_MultiViewRootProxy<Root> : _VariadicView_ViewRoot_MakeChildren_MultiViewRoot where Root : _VariadicView_MultiViewRoot {
    private let proxy: _VariadicView_ViewRoot_MakeChildrenProxy<Root>
    var graph: _GraphValue<Root> { proxy.graph }

    init(graph: _GraphValue<Root>, body: _ViewListOutputs, inputs: _ViewListInputs) {
        self.proxy = .init(graph: graph, body: body, inputs: inputs)
    }

    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
        proxy.makeChildren(encloser: encloser, graph: graph)
    }

    func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        proxy.makeViewGenerators(encloser: encloser, graph: graph)
    }

    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        fatalError("This method should not be called.")
    }

    func mergeInputs(_: _GraphInputs) {
    }
}

private protocol _VariadicView_ViewRoot_MakeChildren_LayoutRoot : _VariadicView_ViewRoot_MakeChildren, ViewGenerator {
    func makeLayout<T>(encloser: T, graph: _GraphValue<T>) -> any Layout
    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext]
}

struct _VariadicView_ViewRoot_MakeChildren_LayoutRootProxy<Root> : _VariadicView_ViewRoot_MakeChildren_LayoutRoot where Root :  _VariadicView.UnaryViewRoot {
    private let proxy: _VariadicView_ViewRoot_MakeChildrenProxy<Root>
    var graph: _GraphValue<Root> { proxy.graph }
    let layout: (Root) -> any Layout

    init(graph: _GraphValue<Root>, body: _ViewListOutputs, inputs: _ViewListInputs, layout: @escaping (Root)-> any Layout) {
        self.proxy = .init(graph: graph, body: body, inputs: inputs)
        self.layout = layout
    }

    func makeLayout<T>(encloser: T, graph: _GraphValue<T>) -> any Layout {
        if let root = graph.value(atPath: self.graph, from: encloser) {
            return layout(root)
        }
        fatalError("Unable to recover LayoutRoot")
    }

    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
        proxy.makeChildren(encloser: encloser, graph: graph)
    }

    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        fatalError("This method should not be called.")
    }

    func mergeInputs(_: _GraphInputs) {
    }
}


extension _VariadicView_ViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let body = body(_Graph(), inputs)
        let inputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)
        let generator = _VariadicView_ViewRoot_MakeChildrenProxy(graph: root, body: body, inputs: inputs)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let body = body(_Graph(), inputs)
        let generator = _VariadicView_ViewRoot_MakeChildrenProxy(graph: root, body: body, inputs: inputs)
        return _ViewListOutputs(viewList: generator, preferences: .init(preferences: []))
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let body = body(_Graph(), inputs)
        let generator = _VariadicView_ViewRoot_MakeChildren_UnaryViewRootProxy(graph: root, body: body, inputs: inputs)
        return _ViewListOutputs(viewList: generator, preferences: .init(preferences: []))
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let body = body(_Graph(), inputs)
        let inputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)
        let generator = _VariadicView_ViewRoot_MakeChildren_MultiViewRootProxy(graph: root, body: body, inputs: inputs)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }
}

public enum _VariadicView {
    public typealias Root = _VariadicView_Root
    public typealias ViewRoot = _VariadicView_ViewRoot
    public typealias Children = _VariadicView_Children
    public typealias UnaryViewRoot = _VariadicView_UnaryViewRoot
    public typealias MultiViewRoot = _VariadicView_MultiViewRoot

    public struct Tree<Root, Content> where Root : _VariadicView_Root {
        public var root: Root
        public var content: Content

        @inlinable init(root: Root, content: Content) {
            self.root = root
            self.content = content
        }

        @inlinable public init(_ root: Root, @ViewBuilder content: () -> Content) {
            self.root = root
            self.content = content()
        }
    }
}

protocol _VariadicView_MultiViewRootViewGenerator : ViewGenerator {
    func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext]
    func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator]
}

extension _VariadicView.Tree : View where Root : _VariadicView_ViewRoot, Content : View {
    public typealias Body = Never

    private struct _ViewGenerator : ViewGenerator {
        let graph: _GraphValue<_VariadicView.Tree<Root, Content>>
        var baseInputs: _GraphInputs
        let children: any _VariadicView_ViewRoot_MakeChildren

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                let subviews = self.children.makeChildren(encloser: view, graph: self.graph)

                var layout: any Layout = DefaultLayoutPropertyItem.default
                if let layoutRoot = children as? any _VariadicView_ViewRoot_MakeChildren_LayoutRoot {
                    layout = layoutRoot.makeLayout(encloser: encloser, graph: graph)
                } else if let layoutRoot = view.root as? any Layout {
                    layout = layoutRoot
                } else if let layoutItem = baseInputs.properties.find(type: DefaultLayoutPropertyItem.self) {
                    layout = layoutItem.layout
                }

                return ViewGroupContext(view: view,
                                        subviews: subviews,
                                        layout: layout,
                                        inputs: baseInputs,
                                        graph: self.graph)
            }
            fatalError("Unable to recover _VariadicView.Tree")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.baseInputs.mergedInputs.append(inputs)
        }
    }

    struct _MultiViewRootViewGenerator : _VariadicView_MultiViewRootViewGenerator {
        let graph: _GraphValue<_VariadicView.Tree<Root, Content>>
        var baseInputs: _GraphInputs
        var makeView: ((ViewContext) -> ViewContext)?

        fileprivate let children: any _VariadicView_ViewRoot_MakeChildren_MultiViewRoot

        func makeChildren<T>(encloser: T, graph: _GraphValue<T>) -> [ViewContext] {
            children.makeChildren(encloser: encloser, graph: graph)
        }

        func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
            children.makeViewGenerators(encloser: encloser, graph: graph)
        }

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                let subviews = self.makeChildren(encloser: view, graph: self.graph)

                var layout: any Layout = DefaultLayoutPropertyItem.default
                if let layoutRoot = children as? any _VariadicView_ViewRoot_MakeChildren_LayoutRoot {
                    layout = layoutRoot.makeLayout(encloser: encloser, graph: graph)
                } else if let layoutRoot = view.root as? any Layout {
                    layout = layoutRoot
                } else if let layoutItem = baseInputs.properties.find(type: DefaultLayoutPropertyItem.self) {
                    layout = layoutItem.layout
                }

                return ViewGroupContext(view: view,
                                        subviews: subviews,
                                        layout: layout,
                                        inputs: baseInputs,
                                        graph: self.graph)
            }
            fatalError("Unable to recover _VariadicView.Tree")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.baseInputs.mergedInputs.append(inputs)
        }
    }

    struct _UnaryViewRootViewListGenerator : ViewListGenerator {
        let graph: _GraphValue<_VariadicView.Tree<Root, Content>>
        let baseInputs: _GraphInputs
        var preferences: PreferenceInputs
        fileprivate let children: any _VariadicView_ViewRoot_MakeChildren_UnaryViewRoot

        func makeViewGenerators<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
            let subviews = children.makeViewGenerators(encloser: encloser, graph: graph)
            let generator = ViewGroupContext<_VariadicView.Tree<Root, Content>>.Generator(
                graph: self.graph,
                subviews: subviews,
                baseInputs: self.baseInputs,
                preferences: self.preferences)
            return [generator]
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Root._makeView(root: view[\.root], inputs: inputs) { graph, inputs in
            let inputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)
            return Content._makeViewList(view: view[\.content], inputs: inputs)
        }

        if let multiView = outputs.view as? any _VariadicView_ViewRoot_MakeChildren_MultiViewRoot {
            let generator = _MultiViewRootViewGenerator(graph: view, baseInputs: inputs.base, children: multiView)
            return _ViewOutputs(view: generator, preferences: .init(preferences: []))
        }
        if let children = outputs.view as? _VariadicView_ViewRoot_MakeChildren {
            let generator = _ViewGenerator(graph: view, baseInputs: inputs.base, children: children)
            return _ViewOutputs(view: generator, preferences: .init(preferences: []))
        }
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let outputs = Root._makeViewList(root: view[\.root], inputs: inputs) { graph, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
        if let unaryView = outputs.viewList as? any _VariadicView_ViewRoot_MakeChildren_UnaryViewRoot {
            let generator = _UnaryViewRootViewListGenerator(graph: view,
                                                            baseInputs: inputs.base,
                                                            preferences: inputs.preferences,
                                                            children: unaryView)
            return _ViewListOutputs(viewList: generator, preferences: .init(preferences: []))
        }
        return outputs
    }
}

extension _VariadicView.Tree : _PrimitiveView where Self: View {
}
