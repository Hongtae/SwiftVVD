//
//  File: HStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct HStack<Content>: View where Content: View {
    public init(@ViewBuilder content: () -> Content) {
    }
}

extension HStack: _PrimitiveView {
    func makeViewProxy() -> any ViewProxy {
        ViewContext(view: self)
    }
}
