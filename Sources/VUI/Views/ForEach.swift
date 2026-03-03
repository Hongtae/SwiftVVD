//
//  File: ForEach.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//


public struct ForEach<Data, ID, Content> where Data: RandomAccessCollection, ID: Hashable {
    public var data: Data
    public var content: (Data.Element) -> Content
    let id: KeyPath<Data.Element, ID>
}

extension ForEach: View where Content: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<ForEach<Data, ID, Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
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

