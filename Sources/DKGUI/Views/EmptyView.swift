//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
}

extension EmptyView: _PrimitiveView {
    func makeViewProxy() -> any ViewProxy {
        ViewContext(view: self)
    }
}
