//
//  File: HStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public var animatableData: EmptyAnimatableData

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
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
}

public typealias _HStackLayout = HStackLayout
extension _HStackLayout: _VariadicView_UnaryViewRoot {
}
