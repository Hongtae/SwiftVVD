//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _PaddingLayout: ViewModifier, Animatable {
    public var edges: Edge.Set
    public var insets: EdgeInsets?
    @inlinable public init(edges: Edge.Set = .all, insets: EdgeInsets?) {
        self.edges = edges
        self.insets = insets
    }
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _PaddingLayout: _ViewLayoutModifier {
    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        let resolvedInsets = insets ?? EdgeInsets(_all: 16)
        let top      = edges.contains(.top)      ? resolvedInsets.top      : 0
        let bottom   = edges.contains(.bottom)   ? resolvedInsets.bottom   : 0
        let leading  = edges.contains(.leading)  ? resolvedInsets.leading  : 0
        let trailing = edges.contains(.trailing) ? resolvedInsets.trailing : 0
        let horizontal = leading + trailing
        let vertical   = top + bottom

        return LayoutComputer(
            sizeThatFits: { proposal in
                let childProposal = ProposedViewSize(
                    width:  proposal.width.map  { max(0, $0 - horizontal) },
                    height: proposal.height.map { max(0, $0 - vertical) }
                )
                let childSize = lc.sizeThatFits(childProposal)
                return CGSize(
                    width:  childSize.width  + horizontal,
                    height: childSize.height + vertical
                )
            },
            spacing: lc.spacing,
            dimensions: { proposal in
                let childProposal = ProposedViewSize(
                    width:  proposal.width.map  { max(0, $0 - horizontal) },
                    height: proposal.height.map { max(0, $0 - vertical) }
                )
                let childSize = lc.sizeThatFits(childProposal)
                return ViewDimensions(
                    width:  childSize.width  + horizontal,
                    height: childSize.height + vertical
                )
            },
            place: { position, anchor, proposal in
                let childProposal = ProposedViewSize(
                    width:  proposal.width.map  { max(0, $0 - horizontal) },
                    height: proposal.height.map { max(0, $0 - vertical) }
                )
                let childSize = lc.sizeThatFits(childProposal)
                let parentW = childSize.width  + horizontal
                let parentH = childSize.height + vertical
                // Compute the top-left origin of the padded frame, then offset inward
                let origin = CGPoint(
                    x: position.x - parentW * anchor.x + leading,
                    y: position.y - parentH * anchor.y + top
                )
                lc.place(at: origin, anchor: .topLeading, proposal: childProposal)
            }
        )
    }
}

extension View {
    @inlinable public func padding(_ insets: EdgeInsets) -> some View {
        return modifier(_PaddingLayout(insets: insets))
    }

    @inlinable public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let insets = length.map { EdgeInsets(_all: $0) }
        return modifier(_PaddingLayout(edges: edges, insets: insets))
    }

    @inlinable public func padding(_ length: CGFloat) -> some View {
        return padding(.all, length)
    }
}

struct DefaultPaddingEdgeInsetsProperty: PropertyItem {
    static var defaultValue: EdgeInsets { .init(_all: 16) }

    var description: String {
        "DefaultPaddingEdgeInsetsProperty"
    }
}

