//
//  File: VStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct VStack<Content>: View where Content: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

extension VStack: _PrimitiveView {
    func makeViewProxy() -> any ViewProxy {
        ViewContext(view: self)
    }
}
