//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _VariadicView_Root {
}

public struct _VariadicView_Children: View {
    public typealias Body = Never
    public var body: Never { neverBody() }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }

    let elements: [Element]
}

extension _VariadicView_Children: RandomAccessCollection {
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
            var inputs = inputs
            inputs.modifiers.merge(view.value.modifiers) { $1 }
            inputs.traits.merge(view.value.traits) { $1 }
            return view.value.view.makeView(graph: _Graph(), inputs: inputs)
        }

        public typealias ID = AnyHashable
        public typealias Body = Never

        let view: AnyView
        var modifiers: [ObjectIdentifier: any ViewModifier]
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

    init(_ content: _ViewListOutputs) {
        var index = 0
        self.elements = content.views.map {
            let element = Element(view: $0.view,
                                  modifiers: $0.inputs.modifiers,
                                  traits: $0.inputs.traits,
                                  viewID: AnyHashable(index))
            index += 1
            return element
        }
    }
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
        let content = root.value.body(children: _VariadicView_Children(body(_Graph(), inputs)))
        return Self.Body._makeView(view: _GraphValue(content), inputs: inputs)
    }
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let content = root.value.body(children: _VariadicView.Children(body(_Graph(), inputs)))
        return Self.Body._makeViewList(view: _GraphValue(content), inputs: inputs)
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let content = root.value.body(children: _VariadicView_Children(body(_Graph(), inputs)))
        return Self.Body._makeViewList(view: _GraphValue(content), inputs: inputs)
    }
}

extension _VariadicView_ViewRoot where Self: Layout, Body == Never {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        return _ViewOutputs(item: .layout(root.value, body(_Graph(), inputs)))
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let content = root.value.body(children: _VariadicView_Children(body(_Graph(), inputs)))
        return Self.Body._makeView(view: _GraphValue(content), inputs: inputs)
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

        init(root: Root, content: Content) {
            self.root = root
            self.content = content
        }
        public init(_ root: Root, @ViewBuilder content: () -> Content) {
            self.root = root
            self.content = content()
        }
    }
}

extension _VariadicView.Tree: View where Root: _VariadicView_ViewRoot, Content: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let root = view[\.root]
        let content = view[\.content]

        let outputs = Root._makeView(root: root, inputs: inputs) {
            graph, inputs in
            if _isPrimitiveView(content.value) {
                return _ViewListOutputs(item: .view(.init(view: AnyView(content.value), inputs: inputs)))
            }
            return Content._makeViewList(view: content, inputs: _ViewListInputs(inputs: inputs))
        }

        if case let .layout(layout, content) = outputs.item {
            let view = ViewContext(view: view, inputs: inputs, outputs: content, layout: layout)
            return _ViewOutputs(item: .view(view))
        }
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Root._makeViewList(root: view[\.root], inputs: inputs) { graph, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }
}

extension _VariadicView.Tree: _PrimitiveView where Self: View {
}
