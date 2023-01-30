//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
}

extension EmptyView: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], parent: any ViewProxy) -> any ViewProxy {
        ViewContext(view: self, parent: parent)
    }
}
