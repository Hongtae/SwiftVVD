//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _VariadicView_Root {
}

public struct _VariadicView_Children: View {
    public typealias Body = Never

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(views: ChildrenViewListGenerator(graph: view, baseInputs: inputs.base))
    }

    let elements: [Element]
}

extension _VariadicView_Children: RandomAccessCollection {
    public struct Element: View, Identifiable {
        public var id: AnyHashable {
            viewID
        }
        public func id<ID>(as _: ID.Type = ID.self) -> ID? where ID: Hashable {
            return nil
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
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                ChildrenElementViewContext(graph: graph, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }

        public typealias ID = AnyHashable
        public typealias Body = Never

        let view: any ViewGenerator
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

    init(list: [any ViewGenerator]) {
        self.elements = list.enumerated().map { index, view in
            Element(view: view, traits: [:], viewID: index)
        }
    }
}

extension _VariadicView_Children: _PrimitiveView {
}

extension _VariadicView_Children.Element: _PrimitiveView {
}

public protocol _VariadicView_ViewRoot: _VariadicView_Root {
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

public protocol _VariadicView_UnaryViewRoot: _VariadicView_ViewRoot {
}

public protocol _VariadicView_MultiViewRoot: _VariadicView_ViewRoot {
}

extension _VariadicView_ViewRoot {
    fileprivate var _proxy: ViewRootProxy<Self> {
        .init(root: self)
    }

    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let body = body(_Graph(), inputs)
        let baseInputs = inputs.base

        if Body.self is Never.Type { // No proxy is required.
            typealias _UnaryViewRoot_Layout = _VariadicView_UnaryViewRoot & Layout
            if let layoutType = self as? any _UnaryViewRoot_Layout.Type {
                if let staticLsit = body.views as? StaticViewList {
                    let views = staticLsit.views.map { $0.makeView() }
                    func makeView<L: _UnaryViewRoot_Layout>(_: L.Type, inputs: _GraphInputs) -> any ViewGenerator {
                        let graph = root.unsafeCast(to: L.self)
                        return UnaryViewGenerator(graph: graph, baseInputs: baseInputs) { graph, inputs in
                            UnaryViewRootLayoutStaticViewGroupContext(graph: graph,
                                                                      subviews: views,
                                                                      inputs: inputs)
                        }
                    }
                    let view = makeView(layoutType, inputs: baseInputs)
                    return _ViewOutputs(view: view)
                } else {
                    func makeView<L: _UnaryViewRoot_Layout>(_: L.Type, inputs: _GraphInputs) -> any ViewGenerator {
                        let graph = root.unsafeCast(to: L.self)
                        return UnaryViewGenerator(graph: graph, baseInputs: baseInputs) { graph, inputs in
                            UnaryViewRootLayoutDynamicViewGroupContext(graph: graph,
                                                                       body: body.views,
                                                                       inputs: inputs)
                        }
                    }
                    let view = makeView(layoutType, inputs: baseInputs)
                    return _ViewOutputs(view: view)
                }
            } else {    // non-layout root
                if let staticLsit = body.views as? StaticViewList {
                    let views = staticLsit.views.map { $0.makeView() }
                    let view = UnaryViewGenerator(graph: root, baseInputs: baseInputs) { graph, inputs in
                        StaticViewGroupContext(graph: graph, subviews: views, inputs: inputs)
                    }
                    return _ViewOutputs(view: view)
                } else {
                    let view = UnaryViewGenerator(graph: root, baseInputs: baseInputs) { graph, inputs in
                        DynamicViewGroupContext(graph: graph, body: body.views, inputs: inputs)
                    }
                    return _ViewOutputs(view: view)
                }
            }
        }

        let proxy = root[\._proxy]
        let proxyBody = proxy[\.body]
        let outputs = Body._makeViewList(view: proxyBody, inputs: inputs.listInputs)

        if let staticList = outputs.views as? StaticViewListGenerator {
            let subviews = staticList.views.map { $0.makeView() }
            let view = UnaryViewGenerator(graph: proxy, baseInputs: baseInputs) { graph, inputs in
                ViewRootProxyStaticGroupContext(children: body.views, graph: graph, subviews: subviews, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        } else {
            let view = UnaryViewGenerator(graph: proxy, baseInputs: baseInputs) { graph, inputs in
                ViewRootProxyDynamicGroupContext(children: body.views, graph: graph, body: outputs.views, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
    }

    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let body = body(_Graph(), inputs)

        if Body.self is Never.Type { // No proxy is required.
            return body
        }

        let proxy = root[\._proxy]
        let proxyBody = proxy[\.body]
        let outputs = Body._makeViewList(view: proxyBody, inputs: inputs)
        let baseInputs = inputs.base

        if let staticList = outputs.views as? StaticViewListGenerator {
            let subviews = staticList.views.map {
                let view = $0.makeView()
                return UnaryViewGenerator(graph: proxy, baseInputs: baseInputs) { graph, inputs in
                    ViewElementProxyWrapper(children: body.views, graph: graph, body: view, inputs: inputs)
                }
            }
            return _ViewListOutputs(views: StaticMultiViewGenerator(graph: root,
                                                                    baseInputs: baseInputs,
                                                                    views: subviews))
        } else {
            let view = ViewRootProxyDynamicMultiViewGenerator(graph: proxy,
                                                              baseInputs: baseInputs,
                                                              children: body.views,
                                                              body: outputs.views)
            return _ViewListOutputs(views: view)
        }
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let outputs = Self._makeView(root: root, inputs: inputs.inputs) { graph, inputs in
            body(graph, inputs.listInputs)
        }
        return _ViewListOutputs(views: .staticList(outputs.view))
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let body = body(_Graph(), inputs)
        let baseInputs = inputs.base

        if Body.self is Never.Type { // No proxy is required.
            if let staticLsit = body.views as? StaticViewList {
                return _ViewOutputs(view: StaticMultiViewGenerator(graph: root,
                                                                   baseInputs: baseInputs,
                                                                   views: staticLsit.views))
            } else {
                return _ViewOutputs(view: DynamicMultiViewGenerator(graph: root,
                                                                    baseInputs: baseInputs,
                                                                    body: body.views))
            }
        }

        let proxy = root[\._proxy]
        let proxyBody = proxy[\.body]
        let outputs = Body._makeViewList(view: proxyBody, inputs: inputs.listInputs)

        if let staticList = outputs.views as? StaticViewListGenerator {
            let subviews = staticList.views.map {
                let view = $0.makeView()
                return UnaryViewGenerator(graph: proxy, baseInputs: baseInputs) { graph, inputs in
                    ViewElementProxyWrapper(children: body.views, graph: graph, body: view, inputs: inputs)
                }
            }
            return _ViewOutputs(view: StaticMultiViewGenerator(graph: root,
                                                               baseInputs: baseInputs,
                                                               views: subviews))
        } else {
            let view = ViewRootProxyDynamicMultiViewGenerator(graph: proxy,
                                                              baseInputs: baseInputs,
                                                              children: body.views,
                                                              body: outputs.views)
            return _ViewOutputs(view: view)
        }
    }
}

public enum _VariadicView {
    public typealias Root = _VariadicView_Root
    public typealias ViewRoot = _VariadicView_ViewRoot
    public typealias Children = _VariadicView_Children
    public typealias UnaryViewRoot = _VariadicView_UnaryViewRoot
    public typealias MultiViewRoot = _VariadicView_MultiViewRoot

    public struct Tree<Root, Content> where Root: _VariadicView_Root {
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

extension _VariadicView.Tree: View where Root: _VariadicView_ViewRoot, Content: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Root._makeView(root: view[\.root], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs.listInputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        assert(view.isRoot == false)
        return Root._makeViewList(root: view[\.root], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }
}

extension _VariadicView.Tree: _PrimitiveView where Self: View {
}

// [ViewGenerators, ViewContext types]
//
// 1. _VariadicView_Children._makeViewList (dynamic ViewListGenerator)
// 2. _VariadicView_Children.ElementContext.makeView (static ViewGenerator)
// 3. _VariadicView_ViewRoot._makeView
//      a. Body == Never
//          1. Root == Layout      (static ViewGenerator with Layout)
//          2. Root != Layout      (static ViewGenerator with default layout)
//      b. Body != Never           (dynamic ViewGenerator with Proxy)
// 4. _VariadicView_ViewRoot._makeViewList
//      a. Body == Never           (forward body)
//      b. Body != Never           (dynamic ViewListGenerator with Proxy)
//          - Requires ProxyWrapper for MultiView.
//          - Same as 6.b
// 5. _VariadicView_UnaryViewRoot._makeViewList (return Self._makeView)
// 6. _VariadicView_MultiViewRoot._makeView
//      a. Body == Never           (static MultiViewGenerator)
//      b. Body != Never           (dynamic MultiViewGenerator with Proxy)
//          - Requires ProxyWrapper for MultiView.
//          - Same as 4.b (ViewGenerator, ViewListGenerator both capable)

// ViewListGenerator for _VariadicView_Children (1)
private struct ChildrenViewListGenerator: ViewListGenerator {
    let graph: _GraphValue<_VariadicView_Children>
    var baseInputs: _GraphInputs

    func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
        if let value = containerView.value(atPath: graph) {
            return value.elements.map {
                var view = $0.view
                view.mergeInputs(baseInputs)
                return view
            }
        }
        fatalError("Unable to recover _VariadicView_Children")
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        baseInputs.mergedInputs.append(inputs)
    }
}

// ViewContext for _VariadicView_Children.Element (2)
private class ChildrenElementViewContext: DynamicViewContext<_VariadicView_Children.Element> {
    override func updateContent() {
        let oldView = self.view?.view
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let view = self.view?.view {
            func isEqual<T: ViewGenerator>(_ lhs: T, _ rhs: (any ViewGenerator)?) -> Bool {
                if let rhs {
                    return lhs == rhs
                }
                return false
            }
            if self.body == nil || isEqual(view, oldView) == false {
                self.body = view.makeView(sharedContext: self.sharedContext)
            }
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
        self.sharedContext.needsLayout = true
    }
}

// Static View Group Context for _VariadicView_ViewRoot._makeView (3.a.1)
private class UnaryViewRootLayoutStaticViewGroupContext<Root>: StaticViewGroupContext<Root> where Root: _VariadicView_UnaryViewRoot & Layout {
    init(graph: _GraphValue<Root>, subviews: [ViewContext], inputs: _GraphInputs) {
        let layout = DefaultLayoutProperty.defaultValue
        super.init(graph: graph, subviews: subviews, layout: layout, inputs: inputs)

        self.layoutProperties = Root.layoutProperties
        self.setLayoutProperties(self.layoutProperties)
    }

    override func updateRoot(_ root: inout Root) {
        super.updateRoot(&root)
        self.layout = AnyLayout(root)
    }
}

// Dynamic View Group Context for _VariadicView_ViewRoot._makeView (3.a.1)
private class UnaryViewRootLayoutDynamicViewGroupContext<Root>: DynamicViewGroupContext<Root> where Root: _VariadicView_UnaryViewRoot & Layout {
    init(graph: _GraphValue<Root>, body: any ViewListGenerator, inputs: _GraphInputs) {
        let layout = DefaultLayoutProperty.defaultValue
        super.init(graph: graph, body: body, layout: layout, inputs: inputs)

        self.layoutProperties = Root.layoutProperties
        self.setLayoutProperties(self.layoutProperties)
    }
    
    override func updateRoot(_ root: inout Root) {
        super.updateRoot(&root)
        self.layout = AnyLayout(root)
    }
}

// Proxy for _VariadicView_ViewRoot.Body subviews
private struct ViewRootProxy<Root> where Root: _VariadicView_ViewRoot {
    let root: Root
    var children = _VariadicView.Children(list: [])
    var body: Root.Body {
        root.body(children: children)
    }
}

// Static View Group with Proxy for 3.b
private class ViewRootProxyStaticGroupContext<Root>: StaticViewGroupContext<ViewRootProxy<Root>> where Root: _VariadicView_ViewRoot {
    typealias Proxy = ViewRootProxy<Root>
    let children: any ViewListGenerator

    init(children: any ViewListGenerator, graph: _GraphValue<Proxy>, subviews: [ViewContext], layout: (any Layout)? = nil, inputs: _GraphInputs) {
        self.children = children
        super.init(graph: graph, subviews: subviews, layout: layout, inputs: inputs)
    }

    override func updateRoot(_ root: inout ViewRootProxy<Root>) {
        super.updateRoot(&root)
        let views = children.makeViewList(containerView: self)
        root.children = _VariadicView_Children(list: views)
    }
}

// Dynamic View Group with Proxy for 3.b
private class ViewRootProxyDynamicGroupContext<Root>: DynamicViewGroupContext<ViewRootProxy<Root>> where Root: _VariadicView_ViewRoot {
    typealias Proxy = ViewRootProxy<Root>
    let children: any ViewListGenerator

    init(children: any ViewListGenerator, graph: _GraphValue<Proxy>, body: any ViewListGenerator, layout: (any Layout)? = nil, inputs: _GraphInputs) {
        self.children = children
        super.init(graph: graph, body: body, layout: layout, inputs: inputs)
    }

    override func updateRoot(_ root: inout ViewRootProxy<Root>) {
        super.updateRoot(&root)
        let views = children.makeViewList(containerView: self)
        root.children = _VariadicView_Children(list: views)
    }
}

// Element Wrapper with Proxy for 4.b, 6.b
private class ViewElementProxyWrapper<Root>: GenericViewContext<ViewRootProxy<Root>> where Root: _VariadicView_ViewRoot {
    typealias Proxy = ViewRootProxy<Root>
    let children: any ViewListGenerator

    init(children: any ViewListGenerator, graph: _GraphValue<Proxy>, body: ViewContext, inputs: _GraphInputs) {
        self.children = children
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateContent() {
        self.view = nil
        // resolve proxy and replace proxy.children for its descendants.
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if var proxy = self.view {
            let views = children.makeViewList(containerView: self)
            proxy.children = _VariadicView_Children(list: views)
            self.view = proxy
            self.body.updateContent()
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }
}

// Dynamic Multi-View Context with Proxy for 4.b, 6.b
private class ViewRootProxyDynamicMultiViewContext<Root>: DynamicMultiViewContext<ViewRootProxy<Root>> where Root: _VariadicView_ViewRoot {
    typealias Proxy = ViewRootProxy<Root>
    let children: any ViewListGenerator

    init(children: any ViewListGenerator, graph: _GraphValue<Proxy>, body: any ViewListGenerator, inputs: _GraphInputs) {
        self.children = children
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateRoot(_ root: inout ViewRootProxy<Root>) {
        super.updateRoot(&root)
        let views = children.makeViewList(containerView: self)
        root.children = _VariadicView_Children(list: views)
    }
}

// Dynamic Multi-View Generator with Proxy for 4.b, 6.b
private struct ViewRootProxyDynamicMultiViewGenerator<Root>: MultiViewGenerator where Root: _VariadicView_ViewRoot {
    typealias Proxy = ViewRootProxy<Root>
    var graph: _GraphValue<Proxy>
    var baseInputs: _GraphInputs
    let children: any ViewListGenerator
    var body: any ViewListGenerator

    func makeView() -> ViewContext {
        ViewRootProxyDynamicMultiViewContext(children: children, graph: graph, body: body, inputs: baseInputs)
    }

    func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
        let multiView = makeView() as! MultiViewContext
        multiView.superview = containerView
        multiView.updateContent()
        let subviews = multiView.subviews
        multiView.subviews = []
        multiView.activeSubviews = []
        multiView.superview = nil

        return subviews.map { view in
            view.superview = nil
            return UnaryViewGenerator(graph: graph, baseInputs: baseInputs) { graph, inputs in
                ViewElementProxyWrapper(children: children,
                                        graph: graph,
                                        body: view,
                                        inputs: inputs)
            }
        }
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        body.mergeInputs(inputs)
        baseInputs.mergedInputs.append(inputs)
    }
}
