//
//  File: LazyVStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyVStack<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_VStackLayout, Content>
    var pinnedViews: PinnedScrollableViews

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self._tree = .init(
            root: _VStackLayout(alignment: alignment, spacing: spacing),
            content: content()
        )
        self.pinnedViews = pinnedViews
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_VStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyVStack: _PrimitiveView {
}
