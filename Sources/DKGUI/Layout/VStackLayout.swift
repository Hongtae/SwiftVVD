//
//  File: VStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public var animatableData: EmptyAnimatableData

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
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

public typealias _VStackLayout = VStackLayout
extension _VStackLayout: _VariadicView_UnaryViewRoot {
}

extension _VStackLayout: _VariadicView_ViewRoot {
}
