//
//  File: StaticSourceWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

struct StaticSourceWriter<Source, Type> {
    public typealias Body = Never
    let source: Type
}

extension StaticSourceWriter: ViewModifier where Source: View, Type: View {
}

extension StaticSourceWriter: _ViewInputsModifier where Self: ViewModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.layouts.sourceWrites[ObjectIdentifier(Source.self)] = ViewProxy(modifier[\.source])
    }
}
