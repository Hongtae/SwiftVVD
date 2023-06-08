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
                typealias Modifier = _TraitWritingModifier<Trait>
                if let trait = traits[ObjectIdentifier(Modifier.self)] as? Modifier {
                    return trait.value
                }
                return Trait.defaultValue
            }
            set {
                typealias Modifier = _TraitWritingModifier<Trait>
                traits[ObjectIdentifier(Modifier.self)] = Modifier(value: newValue)
            }
        }
        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            var inputs = inputs
            //inputs.modifiers.append(contentsOf: view[\.traits].value)
            return AnyView._makeView(view: view[\.view], inputs: inputs)
        }
        public typealias ID = AnyHashable
        public typealias Body = Never

        let view: AnyView
        var traits: [ObjectIdentifier: any ViewModifier]
        var viewID: AnyHashable
    }
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public subscript(index: Int) -> Element { elements[index] }

    public typealias Index = Int
    public typealias Iterator = IndexingIterator<_VariadicView_Children>
    public typealias SubSequence = Slice<_VariadicView_Children>
    public typealias Indices = Range<Int>

    init(_ content: (_Graph, _ViewInputs)->_ViewListOutputs) {
        fatalError()
    }
    init(_ content: (_Graph, _ViewListInputs)->_ViewListOutputs) {
        fatalError()
    }
}

public protocol _VariadicView_ViewRoot: _VariadicView_Root {
    associatedtype Body: View
    @ViewBuilder func body(children: _VariadicView.Children) -> Self.Body
}

extension _VariadicView_ViewRoot where Self.Body == Never {
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
        let content = root.value.body(children: _VariadicView_Children(body))
        return Self.Body._makeView(view: _GraphValue(content), inputs: inputs)
    }
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let content = root.value.body(children: _VariadicView.Children(body))
        return Self.Body._makeViewList(view: _GraphValue(content), inputs: inputs)
    }
}

extension _VariadicView_UnaryViewRoot {
    public static func _makeViewList(root: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        let content = root.value.body(children: _VariadicView_Children(body))
        return Self.Body._makeViewList(view: _GraphValue(content), inputs: inputs)
    }
}

extension _VariadicView_MultiViewRoot {
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        let content = root.value.body(children: _VariadicView_Children(body))
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
    public var body: Never { neverBody() }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let root = view[\.root]
        let content = view[\.content]

        return Root._makeView(root: root, inputs: inputs) {
            graph, inputs in

            let listInputs = _ViewListInputs(inputs: inputs)
            if content.value is _PrimitiveView {
                let makeView: _ViewListOutputs.MakeView = { graph, inputs in
                    Content._makeView(view: content, inputs: inputs)
                }
                return _ViewListOutputs(item: .makeView(makeView))
            }
            return Content._makeViewList(view: content, inputs: listInputs)
        }
    }
    
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Root._makeViewList(root: view[\.root], inputs: inputs) {
            graph, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }
}

extension _VariadicView {
    class RootViewProxy<Root, Content>: ViewProxy where _VariadicView.Tree<Root, Content>: View {
        var view: _GraphValue<Tree<Root, Content>>
        var modifiers: [ObjectIdentifier: any ViewModifier]
        var environmentValues: EnvironmentValues
        var sharedContext: SharedContext

        var layoutOffset: CGPoint = .zero
        var layoutSize: CGSize = .zero
        var contentScaleFactor: CGFloat = 1

        func modifier<K>(key: K.Type) -> K? where K : ViewModifier {
            modifiers[ObjectIdentifier(key)] as? K
        }

        func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        }

        func updateEnvironment(_ environmentValues: EnvironmentValues) {
        }

        init(view: _GraphValue<Tree<Root, Content>>, inputs: _ViewInputs, outputs: _ViewListOutputs) {
            self.view = view
            self.modifiers = inputs.modifiers
            self.environmentValues = inputs.environmentValues
            self.sharedContext = inputs.sharedContext
        }
    }
}
