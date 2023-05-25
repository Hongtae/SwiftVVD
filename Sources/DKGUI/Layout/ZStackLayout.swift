//
//  File: ZStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStackLayout: Layout {
    public var alignment: Alignment

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set { }
    }

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
        self.animatableData = EmptyAnimatableData()
    }

    public func makeCache(subviews: Subviews) -> _StackLayoutCache {
        _StackLayoutCache()
    }

    public func updateCache(_ cache: inout _StackLayoutCache, subviews: Subviews) {
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout _StackLayoutCache) -> CGSize {
        .zero
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout _StackLayoutCache) {
    }

    public func callAsFunction<V>(@ViewBuilder _ content: () -> V) -> some View where V : View {
        _VariadicView.Tree(root: _LayoutRoot(self),
                           content: content())
    }
}

public typealias _ZStackLayout = ZStackLayout
extension _ZStackLayout: _VariadicView_ViewRoot {
}
