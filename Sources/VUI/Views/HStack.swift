//
//  File: HStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct HStack<Content>: View where Content: View {
    public var _tree: _VariadicView.Tree<_HStackLayout, Content>

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(
            root: _HStackLayout(alignment: alignment, spacing: spacing), content: content())
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_HStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension HStack: _PrimitiveView {
}
