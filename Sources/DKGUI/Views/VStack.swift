//
//  File: VStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStack<Content>: View where Content: View {
    public var _tree: _VariadicView.Tree<_VStackLayout, Content>

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(
            root: _VStackLayout(alignment: alignment, spacing: spacing), content: content())
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_VStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension VStack: _PrimitiveView {
}

extension VStack: _ViewProxyProvider {
}
