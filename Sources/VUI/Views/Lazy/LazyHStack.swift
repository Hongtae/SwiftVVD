//
//  File: LazyHStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyHStack<Content>: View where Content: View {
    var tree: ResettableLazyLayoutRoot<_VariadicView.Tree<LazyHStackLayout, Content>>

    var pinnedViews: PinnedScrollableViews {
        tree.content.root.pinnedViews
    }

    public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.tree = ResettableLazyLayoutRoot {
            _VariadicView.Tree(
                root: LazyHStackLayout(
                    base: _HStackLayout(alignment: alignment, spacing: spacing),
                    pinnedViews: pinnedViews
                ),
                content: content()
            )
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        ResettableLazyLayoutRoot<_VariadicView.Tree<LazyHStackLayout, Content>>
            ._makeView(view: view[\.tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyHStack: _PrimitiveView {
}
