//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

extension View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

// _PrimitiveView is a View type that does not have a body. (body = Never)
protocol _PrimitiveView {
}

extension _PrimitiveView {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension Never: View {
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension Optional: _PrimitiveView where Self: View {
}

struct IDView<Content, ID>: View where Content: View, ID: Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Never
    var body: Never { neverBody() }
}

extension View {
    public func id<ID>(_ id: ID) -> some View where ID: Hashable {
        IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

func makeView<V: View>(view: _GraphValue<V>, inputs: _ViewInputs) -> _ViewOutputs {
    V._makeView(view: view, inputs: inputs)
}

struct ViewProxy: Hashable {
    let type: any View.Type
    let graph: _GraphValue<Any>

    init<V: View>(_ graph: _GraphValue<V>) {
        self.type = V.self
        self.graph = graph.unsafeCast(to: Any.self)
    }

    func makeView(_:_Graph, inputs: _ViewInputs) -> _ViewOutputs {
        func make<T: View>(_ type: T.Type) -> _ViewOutputs {
            T._makeView(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    func makeViewList(_:_Graph, inputs: _ViewListInputs) -> _ViewListOutputs {
        func make<T: View>(_ type: T.Type) -> _ViewListOutputs {
            T._makeViewList(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.graph == rhs.graph
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(graph)
    }
}


// Placeholder — AG 기반으로 재작성 예정
public struct _ViewInputs {
    var base: _GraphInputs
}

// Placeholder — AG 기반으로 재작성 예정
public struct _ViewListInputs {
    var base: _GraphInputs
}

// Placeholder — AG 기반으로 재작성 예정
public struct _ViewOutputs {
}

// Placeholder — AG 기반으로 재작성 예정
public struct _ViewListOutputs {
}
