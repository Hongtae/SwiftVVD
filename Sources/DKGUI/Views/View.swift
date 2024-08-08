//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

extension View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = inputs.environmentValues._resolve(view)
        if let provider = view.value as? _ViewProxyProvider {
            let proxy = provider.makeViewProxy(inputs: inputs)
            return _ViewOutputs(item: .view(proxy))
        }
        
        let body = view[\.body]
        if body.value is _ViewProxyProvider {
            let output = Self.Body._makeView(view: body, inputs: inputs)
            if Self._hasDynamicProperty {
                let viewProxy = TypedViewProxy(view: view.value,
                                               inputs: inputs,
                                               body: output.view)
                return _ViewOutputs(item: .view(viewProxy))
            }
            return output
        }

        let listInputs = _ViewListInputs(inputs: inputs)
        let listOutputs = Self.Body._makeViewList(view: body, inputs: listInputs)
        let subviews = listOutputs.viewProxies
        let viewProxy = ViewGroupProxy(view: view.value,
                                       inputs: inputs,
                                       subviews: subviews,
                                       layout: inputs.defaultLayout)
        return _ViewOutputs(item: .view(viewProxy))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = inputs.inputs.environmentValues._resolve(view)
        if view.value is _ViewProxyProvider {
            let inputs = inputs.inputs
            return _ViewListOutputs(item: .view(.init(view: AnyView(view.value), inputs: inputs)))
        }
        let body = view[\.body]
        if body.value is _ViewProxyProvider {
            let inputs = inputs.inputs
            return _ViewListOutputs(item: .view(.init(view: AnyView(body.value), inputs: inputs)))
        }
        return Self.Body._makeViewList(view: body, inputs: inputs)
    }
}

/*
extension View where Body == Never {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("\(Self.self) may not have Body == Never")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("\(Self.self) may not have Body == Never")
    }

    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}
*/

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
        if case let .some(wrapped) = view.value {
            return Wrapped._makeView(view: _GraphValue<Wrapped>(wrapped), inputs: inputs)
        }
        fatalError("\(Self.self) is nil")
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if case let .some(wrapped) = view.value {
            return Wrapped._makeViewList(view: _GraphValue<Wrapped>(wrapped), inputs: inputs)
        }
        fatalError("\(Self.self) is nil")
    }
}

extension Optional: _PrimitiveView where Self: View {
}

//MARK: - View with ID
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
    public func id<ID>(_ id: ID) -> some View where ID : Hashable {
        return IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Content._makeView(view: view[\.content], inputs: inputs)
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}
