//
//  File: HStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct HStack<Content>: View where Content: View {
    public init(@ViewBuilder content: () -> Content) {
    }
}

extension HStack: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], parent: any ViewProxy) -> any ViewProxy {
        ViewContext(view: self, parent: parent)
    }
}
