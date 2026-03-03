//
//  File: StyleContextWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//


struct StyleContextWriter<Style>: ViewModifier where Style: StyleContext {
    typealias Body = Never
    let style: Style
}

extension StyleContextWriter: _ViewInputsModifier where Self: ViewModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        fatalError("Implement with AG")
    }
}
