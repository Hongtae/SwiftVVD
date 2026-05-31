//
//  File: StyleContextWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// StyleContextWriter<T: StyleContext>: _GraphInputsModifier that pushes a
// StyleContext type onto the current context stack in customInputs.
//
// Implementation:
//   _makeInputs reads the current AnyStyleContextType from customInputs,
//   calls pushing(T.self) to add T to the context set, then writes the
//   new value back. This is a pure type-level operation; no instance is stored.
struct StyleContextWriter<T: StyleContext>: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        let current = inputs.customInputs.value(forKey: StyleContextInput.self)
        let new = current.pushing(T.self)
        inputs.customInputs.setValue(new, forKey: StyleContextInput.self)
    }
}

// DefaultStyleContextWriter: resets the context to NoStyleContext (defaultValue).
struct DefaultStyleContextWriter: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        inputs.customInputs.setValue(.defaultValue, forKey: StyleContextInput.self)
    }
}
