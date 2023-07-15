//
//  File: ZStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStackLayout: Layout {
    public typealias Cache = Void
    public var alignment: Alignment

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set { }
    }

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
        self.animatableData = EmptyAnimatableData()
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        subviews.reduce(ViewSpacing()) { spacing, subview in
            spacing.union(subview.spacing, edges: .all)
        }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        subviews.map {
            $0.sizeThatFits(proposal)
        }.reduce(proposal.replacingUnspecifiedDimensions()) { result, size in
            CGSize.maximum(result, size)
        }
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var offset = bounds.origin
        let width = bounds.width
        let height = bounds.height
        var anchor: UnitPoint
        switch self.alignment {
        case .leading:
            offset.x = bounds.minX
            offset.y = bounds.midY
            anchor = .leading
        case .trailing:
            offset.x = bounds.maxX
            offset.y = bounds.midY
            anchor = .trailing
        case .top:
            offset.x = bounds.midX
            offset.y = bounds.minY
            anchor = .top
        case .bottom:
            offset.x = bounds.midX
            offset.y = bounds.maxY
            anchor = .bottom
        case .topLeading:
            offset.x = bounds.minX
            offset.y = bounds.minY
            anchor = .topLeading
        case .topTrailing:
            offset.x = bounds.maxX
            offset.y = bounds.minY
            anchor = .topTrailing
        case .bottomLeading:
            offset.x = bounds.minX
            offset.y = bounds.maxY
            anchor = .bottomLeading
        case .bottomTrailing:
            offset.x = bounds.maxX
            offset.y = bounds.maxY
            anchor = .bottomTrailing
        default:
            offset.x = bounds.midX
            offset.y = bounds.midY
            anchor = .center
        }

        let proposal = ProposedViewSize(width: width, height: height)
        subviews.forEach {
            $0.place(at: offset, anchor: anchor, proposal: proposal)
        }
    }
}

public typealias _ZStackLayout = ZStackLayout
extension _ZStackLayout: _VariadicView_UnaryViewRoot {
}
