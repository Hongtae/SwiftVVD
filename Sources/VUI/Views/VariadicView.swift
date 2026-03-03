//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _VariadicView_Root {
}

public struct _VariadicView_Children: View {
    public typealias Body = Never

    /// Returns a staticList of all element generators as merged outputs.
    /// Called when _VariadicView_Children itself appears in a view list
    /// (e.g. inside a _VariadicView_MultiViewRoot body).
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let children = view._attribute.value
        let generators = children.elements.map(\.generator)
        let merged = generators.map { gen in
            _ViewListOutputs(views: .staticList(.unary(gen)), nextImplicitID: 1, staticCount: 1)
        }
        return _ViewListOutputs(
            views: .staticList(.merged(merged)),
            nextImplicitID: generators.count,
            staticCount: generators.count
        )
    }

    let elements: [Element]

    /// Build Elements from a _ViewListOutputs produced during the body wiring pass.
    /// staticList: extract generators from ViewListElements.
    /// dynamicList: read current generators from the ViewList attribute (registers AG dependency).
    fileprivate static func makeElements(from outputs: _ViewListOutputs) -> [Element] {
        switch outputs.views {
        case .staticList(let elements):
            return extractGenerators(from: elements).enumerated().map { i, gen in
                Element(generator: gen, traits: gen.traitListAttr.attribute?.value ?? ViewTraitCollection(), viewID: AnyHashable(i))
            }
        case .dynamicList(let viewListAttr, _):
            return viewListAttr.value.generators.enumerated().map { i, gen in
                Element(generator: gen, traits: gen.traitListAttr.attribute?.value ?? ViewTraitCollection(), viewID: AnyHashable(i))
            }
        }
    }

    static func extractGenerators(from elements: ViewListElements) -> [TypedUnaryViewGenerator] {
        switch elements {
        case .unary(let gen):
            return [gen]
        case .merged(let outputs):
            return outputs.flatMap { output -> [TypedUnaryViewGenerator] in
                switch output.views {
                case .staticList(let els):
                    return extractGenerators(from: els)
                case .dynamicList(let viewListAttr, _):
                    // _TraitWritingModifier produces single-element dynamicLists.
                    // Reading .value registers an AG dependency when called inside a rule.
                    return viewListAttr.value.generators
                }
            }
        case .modified(let base, _):
            return extractGenerators(from: base)
        }
    }

    /// Returns true if `outputs` contains any `.dynamicList` at any nesting level.
    /// Used to decide whether to register a reactive `childrenAttr` update rule.
    static func containsDynamicList(_ outputs: _ViewListOutputs) -> Bool {
        switch outputs.views {
        case .dynamicList: return true
        case .staticList(let elements): return containsDynamicList(elements)
        }
    }

    private static func containsDynamicList(_ elements: ViewListElements) -> Bool {
        switch elements {
        case .unary: return false
        case .merged(let outputs): return outputs.contains { containsDynamicList($0) }
        case .modified(let base, _): return containsDynamicList(base)
        }
    }
}

extension _VariadicView_Children: RandomAccessCollection {
    public struct Element: View, Identifiable {
        public var id: AnyHashable { viewID }

        public func id<ID>(as _: ID.Type = ID.self) -> ID? where ID: Hashable {
            return nil
        }

        public subscript<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
            get { traits[key] }
            set { traits[key] = newValue }
        }

        /// Delegate to the original view's _makeView via the stored generator.
        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            view._attribute.value.generator.makeView(inputs: inputs) ?? _ViewOutputs()
        }

        /// Returns a single-element static list for this element's generator.
        public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
            let gen = view._attribute.value.generator
            return _ViewListOutputs(views: .staticList(.unary(gen)), nextImplicitID: 1, staticCount: 1)
        }

        public typealias ID = AnyHashable
        public typealias Body = Never

        var generator: TypedUnaryViewGenerator
        var traits: ViewTraitCollection
        var viewID: AnyHashable
    }

    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public subscript(index: Int) -> Element { elements[index] }

    public typealias Index = Int
    public typealias Iterator = IndexingIterator<_VariadicView_Children>
    public typealias SubSequence = Slice<_VariadicView_Children>
    public typealias Indices = Range<Int>
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
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let childListOutputs = body(_Graph(), inputs)

        if Body.self is Never.Type {
            // Body == Never: no proxy required. Wire children directly.
            // Layout root (e.g. _LayoutRoot) overrides this to call _makeLayoutView.
            // For non-Layout roots with Body == Never we fall back to VStackLayout.
            let layoutAttr: Attribute<VStackLayout> = graph.makeInput(value: VStackLayout())
            return VStackLayout._makeLayoutView(root: _GraphValue(_attribute: layoutAttr),
                                               inputs: inputs,
                                               body: { _, _ in childListOutputs })
        }

        // Body != Never: create children AG input node + body(children:) rule.
        let initialElements = _VariadicView_Children.makeElements(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: _VariadicView_Children(elements: initialElements)
        )

        // Register a reactive rule to keep childrenAttr in sync whenever any nested
        // ViewList changes (top-level dynamicList OR nested dynamicLists from _TraitWritingModifier).
        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                // makeElements re-reads all nested viewListAttr.value (registering AG dependencies)
                // so this rule re-fires whenever any child's ViewList changes.
                let elements = _VariadicView_Children.makeElements(from: childListOutputs)
                childrenAttr.setValue(_VariadicView_Children(elements: elements))
            }
        }

        let bodyAttr: Attribute<Body> = graph.makeRule {
            let children = childrenAttr.value   // AG dependency
            let rootCopy = root._attribute.value
            return rootCopy.body(children: children)
        }

        return Body._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
    }

    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let childListOutputs = body(_Graph(), inputs)

        if Body.self is Never.Type {
            // Body == Never: forward the body outputs directly.
            return childListOutputs
        }

        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        // Body != Never: build children + body rule, then wrap in dynamicList.
        let initialElements = _VariadicView_Children.makeElements(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: _VariadicView_Children(elements: initialElements)
        )

        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                let elements = _VariadicView_Children.makeElements(from: childListOutputs)
                childrenAttr.setValue(_VariadicView_Children(elements: elements))
            }
        }

        let bodyAttr: Attribute<Body> = graph.makeRule {
            let children = childrenAttr.value
            let rootCopy = root._attribute.value
            return rootCopy.body(children: children)
        }

        let bodyListOutputs = Body._makeViewList(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)

        switch bodyListOutputs.views {
        case .staticList(let elements):
            // Wrap static elements into a ViewList AG rule so the dynamicList contract is satisfied.
            let generators = _VariadicView_Children.extractGenerators(from: elements)
            let viewListAttr: Attribute<ViewList> = graph.makeRule {
                let _ = bodyAttr.value   // re-evaluate when body changes
                return ViewList(generators: generators)
            }
            return _ViewListOutputs(views: .dynamicList(viewListAttr, nil), nextImplicitID: 0, staticCount: nil)
        case .dynamicList(let innerViewListAttr, let modifier):
            return _ViewListOutputs(views: .dynamicList(innerViewListAttr, modifier), nextImplicitID: 0, staticCount: nil)
        }
    }
}

// File-scope helper: captures the body closure so _UnaryViewRootWrapper can call
// Root._makeView(root:inputs:body:) at layout time.
private final class _UnaryViewBodyClosure<Root: _VariadicView_UnaryViewRoot> {
    let root: _GraphValue<Root>
    let body: (_Graph, _ViewListInputs) -> _ViewListOutputs

    init(root: _GraphValue<Root>,
         body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) {
        self.root = root
        self.body = body
    }
}

// Synthetic leaf view that wraps a UnaryViewRoot + body closure.
// Stored as an AG input node so a ViewProxy can be created for it.
// When the parent Layout calls proxy.makeView, _makeView below fires
// and delegates to Root._makeView(root:inputs:body:).
private struct _UnaryViewRootWrapper<Root: _VariadicView_UnaryViewRoot>: View, _PrimitiveView {
    typealias Body = Never

    let closure: _UnaryViewBodyClosure<Root>

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let cls = view._attribute.value.closure
        return Root._makeView(root: cls.root, inputs: inputs) { _, viewInputs in
            cls.body(_Graph(), viewInputs.listInputs)
        }
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        let closure = _UnaryViewBodyClosure(root: root, body: body)
        let wrapperAttr: Attribute<_UnaryViewRootWrapper<Self>> = graph.makeInput(
            value: _UnaryViewRootWrapper(closure: closure)
        )
        let wrapperGraph = _GraphValue<_UnaryViewRootWrapper<Self>>(_attribute: wrapperAttr)
        return _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(wrapperGraph, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        // Delegate to the generic ViewRoot _makeView which handles both Body==Never and Body!=Never.
        // For Body == Never: falls back to VStackLayout (like _VariadicView_ViewRoot default).
        // For Body != Never: children AG input + body(children:) rule + Body._makeView.
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        _ = graph

        let childListOutputs = body(_Graph(), inputs)

        if Body.self is Never.Type {
            // static MultiViewGenerator: merge children into a Layout.
            let layoutAttr: Attribute<VStackLayout> = graph.makeInput(value: VStackLayout())
            return VStackLayout._makeLayoutView(root: _GraphValue(_attribute: layoutAttr),
                                               inputs: inputs,
                                               body: { _, _ in childListOutputs })
        }

        // dynamic MultiViewGenerator with Proxy — same as _VariadicView_ViewRoot._makeView Body!=Never.
        let initialElements = _VariadicView_Children.makeElements(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: _VariadicView_Children(elements: initialElements)
        )

        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                let elements = _VariadicView_Children.makeElements(from: childListOutputs)
                childrenAttr.setValue(_VariadicView_Children(elements: elements))
            }
        }

        let bodyAttr: Attribute<Body> = graph.makeRule {
            let children = childrenAttr.value
            let rootCopy = root._attribute.value
            return rootCopy.body(children: children)
        }

        return Body._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
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
