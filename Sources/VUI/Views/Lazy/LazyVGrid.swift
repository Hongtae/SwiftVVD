//
//  File: LazyVGrid.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyVGrid<Content>: View where Content: View {
    var tree: ResettableLazyLayoutRoot<_VariadicView.Tree<LazyVGridLayout, Content>>

    var pinnedViews: PinnedScrollableViews {
        tree.content.root.pinnedViews
    }

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.tree = ResettableLazyLayoutRoot {
            _VariadicView.Tree(
                root: LazyVGridLayout(
                    columns: columns,
                    alignment: alignment,
                    spacing: spacing,
                    pinnedViews: pinnedViews
                ),
                content: content()
            )
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        ResettableLazyLayoutRoot<_VariadicView.Tree<LazyVGridLayout, Content>>
            ._makeView(view: view[\.tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyVGrid: PrimitiveView, UnaryView {
}

struct LazyVGridLayout: HVGrid {
    var columns: [GridItem]
    var alignment: HorizontalAlignment
    var spacing: CGFloat?
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _LazyStack_Cache<Self>

    static var layoutProperties: _LazyLayout_Properties {
        _LazyLayout_Properties(axes: .vertical)
    }

    var minorAxisAnchor: CGFloat {
        alignment.fraction
    }

    var gridItems: [GridItem] {
        columns
    }

    init(
        columns: [GridItem],
        alignment: HorizontalAlignment,
        spacing: CGFloat?,
        pinnedViews: PinnedScrollableViews
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
    }

}
