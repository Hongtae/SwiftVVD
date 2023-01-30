//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Text: View {
    public init<S>(_ content: S) where S : StringProtocol {
    }
}

extension Text: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], parent: any ViewProxy) -> any ViewProxy {
        ViewContext(view: self, parent: parent)
    }
}
