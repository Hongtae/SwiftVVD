//
//  File: StaticSourceWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

struct StaticSourceWriter<Source, Type> {
    public typealias Body = Never
    let source: Type
}

extension StaticSourceWriter: ViewModifier where Source: View, Type: View {
}

extension StaticSourceWriter: _ViewInputsModifier where Self: ViewModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        let outputs = Type._makeView(view: modifier[\.source], inputs: inputs)
        if let view = outputs.view {
            inputs.layouts.sourceWrites[ObjectIdentifier(Source.self)] = view
        }
    }
}
