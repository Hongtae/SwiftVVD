//
//  File: StaticSourceWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// PropertyItem key that stores a ViewProxy for a given Source view type.
/// Written by StaticSourceWriter, read by Source._makeView implementations
/// (e.g. PrimitiveButtonStyleConfiguration.Label, LabelStyleConfiguration.Title/Icon).
struct _StaticSourceInputKey<Source>: PropertyItem {
    typealias Item = ViewProxy?
    static var defaultValue: ViewProxy? { nil }
    var description: String { "_StaticSourceInputKey<\(Source.self)>" }
}

struct StaticSourceWriter<Source, Type> {
    public typealias Body = Never
    let source: Type
}

extension StaticSourceWriter: ViewModifier where Source: View, Type: View {
}

extension StaticSourceWriter: _ViewInputsModifier where Source: View, Type: View {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        let proxy: ViewProxy? = ViewProxy(modifier[\.source])
        inputs.base.customInputs.setValue(proxy, forKey: _StaticSourceInputKey<Source>.self)
    }
}
