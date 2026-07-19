//
//  File: LazyHGrid.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyHGrid<Content>: View where Content: View {
    var tree: ResettableLazyLayoutRoot<_VariadicView.Tree<LazyHGridLayout, Content>>

    var pinnedViews: PinnedScrollableViews {
        tree.content.root.pinnedViews
    }

    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.tree = ResettableLazyLayoutRoot {
            _VariadicView.Tree(
                root: LazyHGridLayout(
                    rows: rows,
                    alignment: alignment,
                    spacing: spacing,
                    pinnedViews: pinnedViews
                ),
                content: content()
            )
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        ResettableLazyLayoutRoot<_VariadicView.Tree<LazyHGridLayout, Content>>
            ._makeView(view: view[\.tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyHGrid: PrimitiveView, UnaryView {
}

struct LazyHGridLayout: HVGrid {
    var rows: [GridItem]
    var alignment: VerticalAlignment
    var spacing: CGFloat?
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _LazyStack_Cache<Self>

    static var layoutProperties: _LazyLayout_Properties {
        _LazyLayout_Properties(axes: .horizontal)
    }

    var minorAxisAnchor: CGFloat {
        alignment.fraction
    }

    var gridItems: [GridItem] {
        rows
    }

    init(
        rows: [GridItem],
        alignment: VerticalAlignment,
        spacing: CGFloat?,
        pinnedViews: PinnedScrollableViews
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
    }

}
