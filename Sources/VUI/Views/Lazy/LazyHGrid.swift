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
            ._makeLazyLayoutView(view: view[\.tree], inputs: inputs)
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
    typealias Cache = _LazyGridLayout.Cache

    static var _lazyLayoutProperties: _LazyLayout_Properties {
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

    private var layout: _LazyGridLayout {
        _LazyGridLayout(
            axis: .horizontal,
            items: self.rows,
            horizontalAlignment: .center,
            verticalAlignment: alignment,
            spacing: spacing
        )
    }

    func makeCache(subviews: Subviews) -> Cache {
        layout.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        layout.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        layout.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        layout.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        layout.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }
}
