//
//  File: ZStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStack<Content> : View where Content : View {
    public var _tree: _VariadicView.Tree<_ZStackLayout, Content>

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        _tree = .init(
            root: _ZStackLayout(alignment: alignment), content: content())
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_ZStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension ZStack : _PrimitiveView {
}
