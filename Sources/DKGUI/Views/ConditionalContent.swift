//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _ConditionalContent<TrueContent, FalseContent>: View where TrueContent: View, FalseContent: View {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public let storage: Storage

    init(storage: Storage) {
        self.storage = storage
    }
}

extension _ConditionalContent: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier], parent: any ViewProxy) -> any ViewProxy {
        ViewContext(view: self, parent: parent)
    }
}
