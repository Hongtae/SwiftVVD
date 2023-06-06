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
        let listInputs = _ViewListInputs(inputs: inputs)
        let listOutputs = Self._makeViewList(view: view, inputs: listInputs)
        let makeView: _ViewOutputs.MakeView = {
            ViewContext(view: view, inputs: inputs, outputs: listOutputs)
        }
        return _ViewOutputs(makeView: makeView)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let body = view[\.body]
        if body.value is _PrimitiveView {
            let makeView: _ViewListOutputs.MakeView = { graph, inputs in
                Self.Body._makeView(view: body, inputs: inputs)
            }
            return _ViewListOutputs(item: .makeView(makeView))
        }
        return Self.Body._makeViewList(view: body, inputs: inputs)
    }
}

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

protocol _PrimitiveView {
}

extension _PrimitiveView {
    public typealias Body = Never
}

//MARK: - View with ID
struct IDView<Content, ID>: View where Content: View, ID: Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Swift.Never
    var body: Swift.Never { neverBody() }
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
