//
//  File: LazyHStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyHStack<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_HStackLayout, Content>
    var pinnedViews: PinnedScrollableViews

    public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self._tree = .init(
            root: _HStackLayout(alignment: alignment, spacing: spacing),
            content: content()
        )
        self.pinnedViews = pinnedViews
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_HStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyHStack: _PrimitiveView {
}
