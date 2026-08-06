//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _VariadicView_Root {
    static var _viewListOptions: Int { get }
}

extension _VariadicView_Root {
    public static var _viewListOptions: Int { 0 }

    static var viewListOptions: _ViewListInputs.Options {
        _ViewListInputs.Options(rawValue: _viewListOptions)
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

public struct _VariadicView_Children: View {
    public typealias Body = Never

    /// Child AG rule that materializes `ForEach<_VariadicView_Children, AnyHashable, Element>`.
    private struct Child: Rule, AsyncAttribute {
        typealias Value = ForEach<_VariadicView_Children, AnyHashable, Element>
        var attribute: Attribute<_VariadicView_Children>

        var value: Value {
            let children = attribute.value
            return ForEach(children, id: \.id) { $0 }
        }
    }

    /// Returns a staticList of all elements as merged outputs.
    /// Called when _VariadicView_Children itself appears in a view list
    /// (e.g. inside a _VariadicView_MultiViewRoot body).
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let childAttr: Attribute<ForEach<Self, AnyHashable, Element>> = graph.makeRule(
            Child(attribute: view._attribute)
        )
        return ForEach<Self, AnyHashable, Element>._makeViewList(
            view: _GraphValue(_attribute: childAttr),
            inputs: inputs
        )
    }

    var list: any ViewList
    var contentSubgraph: AGSubgraph?
    var transform: _ViewList_SublistTransform
    var content: _ViewList_Backing { _ViewList_Backing(list: list) }

    init(
        list: any ViewList,
        contentSubgraph: AGSubgraph?,
        transform: _ViewList_SublistTransform = _ViewList_SublistTransform()
    ) {
        self.list = list
        self.contentSubgraph = contentSubgraph
        self.transform = transform
    }

    /// Build children storage from a `_ViewListOutputs` produced during the body wiring pass.
    fileprivate static func makeChildren(from outputs: _ViewListOutputs) -> Self {
        switch outputs.views {
        case .staticList(let elements):
            return Self(list: BaseViewList(elements: elements), contentSubgraph: nil)
        case .dynamicList(let viewListAttr, _):
            return Self(list: viewListAttr.value, contentSubgraph: nil)
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
        case .unaryElements: return false
        case .merged(let outputs): return outputs.contains { containsDynamicList($0) }
        case .modified(let mod):
            guard let base = mod.base as? ViewListElements else { return false }
            return containsDynamicList(base)
        }
    }
}

extension _VariadicView_Children: MultiView {}

extension _VariadicView_Children: RandomAccessCollection {
    public struct Element: View, Identifiable {
        public var id: AnyHashable { view.viewID }

        public func id<ID>(as _: ID.Type = ID.self) -> ID? where ID: Hashable {
            view.id.primaryExplicitID?.base as? ID
        }

        public subscript<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
            get { traits[key] }
            set { traits[key] = newValue }
        }

        /// Element rendering routes through _ViewList_View._makeView.
        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            _ViewList_View._makeView(view: view[\.view], inputs: inputs)
        }

        /// Returns a single-element static list for this element.
        /// Rendering routes through `_ViewList_View._makeView`.
        /// It does not extract TypedUnaryViewGenerator values from the element.
        public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
            let generator = BodyUnaryViewGenerator(
                body: { viewInputs in
                    _ViewList_View._makeView(view: view[\.view], inputs: viewInputs)
                },
                viewType: Self.self
            )
            let elements = UnaryElements(
                body: generator,
                baseInputs: inputs.base
            )
            return _ViewListOutputs(
                views: .staticList(.unaryElements(elements)),
                nextImplicitID: 1,
                staticCount: 1
            )
        }

        public typealias ID = AnyHashable
        public typealias Body = Never

        var view: _ViewList_View
        var traits: ViewTraitCollection
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int {
        Self.withCollectionUpdate {
            list.count(style: _ViewList_IteratorStyle())
        }
    }
    public subscript(index: Int) -> Element {
        Self.withCollectionUpdate {
            let elements = elements
            guard elements.indices.contains(index) else {
                return fallbackElement(at: index)
            }
            return elements[index]
        }
    }

    private static func withCollectionUpdate<Result>(_ body: () -> Result) -> Result {
        Update.begin()
        defer { Update.end() }
        return body()
    }

    private func fallbackElement(at index: Int) -> Element {
        let view = _ViewList_View(
            elements: _ViewList_SubgraphElements(base: EmptyViewListElements()),
            id: _ViewList_ID(),
            index: index,
            count: 0,
            contentSubgraph: contentSubgraph
        )
        return Element(view: view, traits: ViewTraitCollection())
    }

    private var elements: [Element] {
        var built: [Element] = []
        _ = _forEachSublist(in: list, sublistTransform: transform) { sublist in
            let sharedElements = sublist.elements
            let traitsCollection = sublist.traits
            for offset in 0..<sublist.count {
                let view = _ViewList_View(
                    elements: sharedElements,
                    id: sublist.id,
                    index: offset,
                    count: sublist.count,
                    contentSubgraph: contentSubgraph
                )
                built.append(Element(view: view, traits: traitsCollection))
            }
            return true
        }
        return built
    }

    public typealias Index = Int
    public typealias Iterator = IndexingIterator<_VariadicView_Children>
    public typealias SubSequence = Slice<_VariadicView_Children>
    public typealias Indices = Range<Int>
}

@available(*, unavailable)
extension _VariadicView_Children: Sendable {
}

extension _VariadicView_Children: PrimitiveView {
}

extension _VariadicView_Children.Element: PrimitiveView, UnaryView {
}

public protocol _VariadicView_ViewRoot: _VariadicView_Root {
    associatedtype Body: View
    @ViewBuilder func body(children: _VariadicView.Children) -> Self.Body

    static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs
    static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
    static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int?
}

extension _VariadicView_ViewRoot where Body == Never {
    public func body(children: _VariadicView.Children) -> Never {
        neverBody()
    }
}

extension _VariadicView_ViewRoot {
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        _viewListCount(inputs: inputs, body: { _ in nil })
    }
}

public protocol _VariadicView_UnaryViewRoot: _VariadicView_ViewRoot {
}

public protocol _VariadicView_MultiViewRoot: _VariadicView_ViewRoot {
}

protocol _VariadicView_AnyImplicitRoot {
    static func visitType<Visitor>(
        visitor: inout Visitor
    ) where Visitor: _VariadicView_ImplicitRootVisitor
}

protocol _VariadicView_ImplicitRootVisitor {
    mutating func visit<Root>(
        type: Root.Type
    ) where Root: _VariadicView_ImplicitRoot
}

protocol _VariadicView_ImplicitRoot:
    _VariadicView_ViewRoot,
    _VariadicView_AnyImplicitRoot
{
    static var implicitRoot: Self { get }
}

extension _VariadicView_ImplicitRoot {
    static func visitType<Visitor>(
        visitor: inout Visitor
    ) where Visitor: _VariadicView_ImplicitRootVisitor {
        visitor.visit(type: Self.self)
    }
}

private struct ImplicitRootType: PropertyKey {
    typealias Value = any _VariadicView_AnyImplicitRoot.Type

    static var defaultValue: Value {
        _VStackLayout.self
    }

    static func valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension _ViewInputs {
    var implicitRootType: any _VariadicView_AnyImplicitRoot.Type {
        get {
            base.customInputs.value(forKey: ImplicitRootType.self)
        }
        set {
            base.customInputs.setValue(
                newValue,
                forKey: ImplicitRootType.self
            )
        }
    }

    fileprivate mutating func formUnionViewListOptions(
        _ options: _ViewListInputs.Options
    ) {
        var value = base.customInputs.value(
            forKey: ViewListOptionsInput.self
        )
        value.formUnion(options)
        base.customInputs.setValue(
            value,
            forKey: ViewListOptionsInput.self
        )
    }
}

extension _ViewListInputs {
    var implicitRootType: any _VariadicView_AnyImplicitRoot.Type {
        get {
            base.customInputs.value(forKey: ImplicitRootType.self)
        }
        set {
            base.customInputs.setValue(
                newValue,
                forKey: ImplicitRootType.self
            )
        }
    }
}

private struct MakeViewRoot: _VariadicView_ImplicitRootVisitor {
    var inputs: _ViewInputs
    var body: (_Graph, _ViewInputs) -> _ViewListOutputs
    var outputs: _ViewOutputs?

    mutating func visit<Root>(
        type: Root.Type
    ) where Root: _VariadicView_ImplicitRoot {
        let root = inputs.intern(
            Root.implicitRoot,
            id: .implicitViewRoot
        )
        var rootInputs = inputs
        rootInputs.formUnionViewListOptions(Root.viewListOptions)
        outputs = Root._makeView(
            root: _GraphValue(_attribute: root),
            inputs: rootInputs,
            body: body
        )
    }
}

extension View {
    static func makeImplicitRoot(
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        var visitor = MakeViewRoot(
            inputs: inputs,
            body: body,
            outputs: nil
        )
        inputs.implicitRootType.visitType(visitor: &visitor)
        guard let outputs = visitor.outputs else {
            fatalError(
                "\(Self.self).makeImplicitRoot did not produce view outputs."
            )
        }
        return outputs
    }

    static func makeImplicitRoot(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        makeImplicitRoot(inputs: inputs) { _, inputs in
            Self._makeViewList(
                view: view,
                inputs: inputs.listInputs
            )
        }
    }
}

extension MultiView {
    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        makeImplicitRoot(view: view, inputs: inputs)
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs
    ) -> Int? {
        nil
    }
}

protocol UnaryViewGenerator {
    func makeView(
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?
    ) -> _ViewOutputs

    func tryToReuse(
        by other: Self,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool
}

/// UnaryViewRoot-specific generator for unary variadic roots.
struct BodyUnaryViewGenerator {
    var body: (_ViewInputs) -> _ViewOutputs
    var viewType: Any.Type
}

extension BodyUnaryViewGenerator: UnaryViewGenerator {
    func makeView(
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?
    ) -> _ViewOutputs {
        body(inputs)
    }

    func tryToReuse(
        by other: BodyUnaryViewGenerator,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        _AGCompareValues(
            body,
            other.body,
            options: AGComparisonOptions(rawValue: 0x103)
        )
    }
}

extension _VariadicView_ViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        if Body.self is Never.Type {
            // Body = Never roots must provide a concrete layout/root entry path.
            // The generic ViewRoot body path must not silently replace the root
            // with VStackLayout.
            neverBody("\(Self.self)._makeView used the generic ViewRoot path with Body == Never.")
        }

        let childListOutputs = body(_Graph(), inputs)

        // Body != Never: create children AG input node + body(children:) rule.
        let initialChildren = _VariadicView_Children.makeChildren(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: initialChildren
        )

        // Register a reactive rule to keep childrenAttr in sync whenever any nested
        // ViewList changes (top-level dynamicList OR nested dynamicLists from _TraitWritingModifier).
        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                // makeElements re-reads all nested viewListAttr.value (registering AG dependencies)
                // so this rule re-fires whenever any child's ViewList changes.
                let children = _VariadicView_Children.makeChildren(from: childListOutputs)
                childrenAttr.setValue(children)
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
            // Body = Never. Forward the body outputs directly.
            return childListOutputs
        }

        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        // Body != Never: build children + body rule, then wrap in dynamicList.
        let initialChildren = _VariadicView_Children.makeChildren(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: initialChildren
        )

        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                let children = _VariadicView_Children.makeChildren(from: childListOutputs)
                childrenAttr.setValue(children)
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
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                let _ = bodyAttr.value   // re-evaluate when body changes
                return BaseViewList(elements: elements)
            }
            return _ViewListOutputs(views: .dynamicList(viewListAttr, nil), nextImplicitID: 0, staticCount: nil)
        case .dynamicList(let innerViewListAttr, let modifier):
            return _ViewListOutputs(views: .dynamicList(innerViewListAttr, modifier), nextImplicitID: 0, staticCount: nil)
        }
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        nil
    }

    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(viewType: Self.self, inputs: inputs) { viewInputs in
            Self._makeView(root: root, inputs: viewInputs) { _, childInputs in
                body(_Graph(), childInputs.listInputs)
            }
        }
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }

    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        // Delegate to the generic ViewRoot _makeView which handles both Body = Never and Body != Never.
        // For Body = Never, fall back to VStackLayout.
        // For Body != Never, build children AG input, body(children:) rule, and Body._makeView.
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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

        // Dynamic MultiViewGenerator with Proxy, same routing as the Body != Never ViewRoot path.
        let initialChildren = _VariadicView_Children.makeChildren(from: childListOutputs)
        let childrenAttr: Attribute<_VariadicView_Children> = graph.makeInput(
            value: initialChildren
        )

        if _VariadicView_Children.containsDynamicList(childListOutputs) {
            let _ = graph.makeRule {
                let children = _VariadicView_Children.makeChildren(from: childListOutputs)
                childrenAttr.setValue(children)
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
            var listInputs = inputs.listInputs
            listInputs.formUnion(
                viewListOptions: Root.viewListOptions
            )
            return Content._makeViewList(view: view[\.content], inputs: listInputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        // `view.isRoot` can be true when body/list traversal materializes this
        // Tree from a rule attribute, such as a Body._makeViewList body node or
        // a TupleView child node. That is distinct from an app/scene root view
        // entering through _makeViewList. Restore the non-root assertion only
        // after the Tree._makeViewList root invariant is fully modeled.
        var rootInputs = inputs
        rootInputs.formUnion(
            viewListOptions: Root.viewListOptions
        )
        return Root._makeViewList(root: view[\.root], inputs: rootInputs) { _, inputs in
            var listInputs = inputs
            listInputs.formUnion(
                viewListOptions: Root.viewListOptions
            )
            return Content._makeViewList(view: view[\.content], inputs: listInputs)
        }
    }
}

@available(*, unavailable)
extension _VariadicView.Tree: Sendable {
}

extension _VariadicView.Tree: PrimitiveView, UnaryView where Self: View {
}
