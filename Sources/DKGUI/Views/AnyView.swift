//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct AnyView: View {
    var view: any View
    public init<V>(_ view: V) where V: View {
        self.view = view
    }

    public init<V>(erasing view: V) where V: View {
        self.view = view
    }
}

extension AnyView: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], environmentValues: EnvironmentValues) -> any ViewProxy {
        ViewContext(view: self, modifiers: modifiers, environmentValues: environmentValues)
    }
}
