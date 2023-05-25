//
//  File: VariadicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol _VariadicView_Root {
}

public protocol _ViewTraitKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct _VariadicView_Children: View {
    public typealias Body = Never
    public var body: Never { neverBody() }
}

extension _VariadicView_Children: RandomAccessCollection {
    public struct Element: View, Identifiable {
        public var body: Never

        public var id: AnyHashable {
            get {
                fatalError()
            }
        }
        public func id<ID>(as _: ID.Type = ID.self) -> ID? where ID: Hashable {
            fatalError()
        }
        public subscript<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
            get {
                fatalError()
            }
            set {
                fatalError()
            }
        }
        public static func _makeView(view: _GraphValue<_VariadicView_Children.Element>, inputs: _ViewInputs) -> _ViewOutputs {
            fatalError()
        }
        public typealias ID = AnyHashable
        public typealias Body = Never
    }
    public var startIndex: Int {
        get {
            fatalError()
        }
    }
    public var endIndex: Int {
        get {
            fatalError()
        }
    }
    public subscript(index: Int) -> _VariadicView_Children.Element {
        get {
            fatalError()
        }
    }
    public typealias Index = Int
    public typealias Iterator = IndexingIterator<_VariadicView_Children>
    public typealias SubSequence = Slice<_VariadicView_Children>
    public typealias Indices = Range<Int>
}

public protocol _VariadicView_ViewRoot: _VariadicView_Root {
    associatedtype Body: View
    func body(children: _VariadicView.Children) -> Self.Body
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
    public var body: Never { neverBody() }
    public typealias Body = Never
}
