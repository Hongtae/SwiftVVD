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

extension View {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs()
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs()
    }
}

