//
//  File: LazyVGrid.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LazyVGrid<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_LazyGridLayout, Content>
    var pinnedViews: PinnedScrollableViews

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self._tree = .init(
            root: _LazyGridLayout(
                axis: .vertical,
                items: columns,
                horizontalAlignment: alignment,
                verticalAlignment: .center,
                spacing: spacing
            ),
            content: content()
        )
        self.pinnedViews = pinnedViews
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_LazyGridLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension LazyVGrid: _PrimitiveView {
}
