//
//  File: StaticSourceWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// AnySource — type-erased _GraphValue<T> wrapper.
// Stores closures that capture the concrete T so that makeView/makeViewList
// can be called without knowing T at the call site.
struct AnySource {
    private let _makeViewFn: (_ViewInputs) -> _ViewOutputs
    private let _makeViewListFn: (_ViewListInputs) -> _ViewListOutputs
    let valueIsNil: Bool?

    init<T: View>(value: _GraphValue<T>, valueIsNil: Bool? = nil) {
        _makeViewFn = { inputs in T._makeView(view: value, inputs: inputs) }
        _makeViewListFn = { inputs in T._makeViewList(view: value, inputs: inputs) }
        self.valueIsNil = valueIsNil
    }

    func makeView(inputs: _ViewInputs) -> _ViewOutputs { _makeViewFn(inputs) }
    func makeViewList(inputs: _ViewListInputs) -> _ViewListOutputs { _makeViewListFn(inputs) }
}

// SourceInput<Source> — PropertyItem key whose value is Stack<AnySource>.
// Written by StaticSourceWriter and read by Source._makeView implementations
// (e.g. PrimitiveButtonStyleConfiguration.Label, LabelStyleConfiguration.Title/Icon).
struct SourceInput<Source>: PropertyItem {
    typealias Item = Stack<AnySource>
    static var defaultValue: Stack<AnySource> { .empty }
    var description: String { "SourceInput<\(Source.self)>" }
}

// StaticSourceWriter<Source, Type> — ViewModifier that writes a SourceInput entry
// for Source into customInputs, enabling Source._makeView to later render Type.
struct StaticSourceWriter<Source, Type> {
    public typealias Body = Never
    let source: Type
}

extension StaticSourceWriter: ViewModifier where Source: View, Type: View {
}

extension StaticSourceWriter: _ViewInputsModifier where Source: View, Type: View {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        let anySource = AnySource(value: modifier[\.source])
        let stack = inputs.base.customInputs.value(forKey: SourceInput<Source>.self)
        inputs.base.customInputs.setValue(stack.pushing(anySource), forKey: SourceInput<Source>.self)
    }
}
