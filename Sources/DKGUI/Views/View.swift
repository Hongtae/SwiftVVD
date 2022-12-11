//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol View {
    associatedtype Body: View
    var body: Self.Body { get }
}

protocol _PrimitiveView {
    func makeViewProxy(inputs: _ViewInputs) -> any ViewProxy
    func _makeView(inputs: _ViewInputs) -> _ViewOutputs
}

extension View {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let prim = view as? (any _PrimitiveView) {
            return prim._makeView(inputs: inputs)
        }
        return Self.Body._makeView(view: view.body, inputs: inputs)
        //return _ViewOutputs()
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if Self.Body.self == Never.self {
            return Self.Body._makeViewList(view: view.body, inputs: inputs)
//            return _ViewListOutputs()
        }
        return _ViewListOutputs()
    }
}
