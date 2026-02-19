//
//  File: ZStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStackLayout: Layout {
    public var alignment: Alignment

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = Void

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        subviews.reduce(ViewSpacing()) { spacing, subview in
            spacing.union(subview.spacing, edges: .all)
        }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let fitSizes = subviews.map {
            $0.sizeThatFits(proposal)
        }
        let fitWidth = fitSizes.reduce(CGFloat.zero) { result, size in
            max(result, size.width)
        }
        let fitHeight = fitSizes.reduce(CGFloat.zero) { result, size in
            max(result, size.height)
        }
        return CGSize(width: fitWidth, height: fitHeight)
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Cache) {
        var anchor: UnitPoint
        switch self.alignment {
        case .leading:          anchor = .leading
        case .trailing:         anchor = .trailing
        case .top:              anchor = .top
        case .bottom:           anchor = .bottom
        case .topLeading:       anchor = .topLeading
        case .topTrailing:      anchor = .topTrailing
        case .bottomLeading:    anchor = .bottomLeading
        case .bottomTrailing:   anchor = .bottomTrailing
        default:
            anchor = .center
        }

        let (minX, minY) = (bounds.minX, bounds.minY)
        let (width, height) = (bounds.width, bounds.height)

        let offset = CGPoint(x: minX + width * anchor.x,
                             y: minY + height * anchor.y)

        // ZStack passes the bounds-constrained proposal to each child
        // Children decide their own size within those constraints
        let boundsProposal = ProposedViewSize(width: width, height: height)
        
        subviews.forEach { view in
            view.place(at: offset, anchor: anchor, proposal: boundsProposal)
        }
    }
}

public typealias _ZStackLayout = ZStackLayout
extension _ZStackLayout: _VariadicView_UnaryViewRoot {}
extension _ZStackLayout: Sendable {}


