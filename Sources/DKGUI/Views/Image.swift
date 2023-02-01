//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Image: View {
    public init() {
    }

    public init(_ name: String, bundle: Bundle? = nil) {
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
    }
}

extension Image: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], environmentValues: EnvironmentValues) -> any ViewProxy {
        ViewContext(view: self, modifiers: modifiers, environmentValues: environmentValues)
    }
}
