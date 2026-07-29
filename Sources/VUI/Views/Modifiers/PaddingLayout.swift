//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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

extension _PaddingLayout: Sendable {}

extension _PaddingLayout: UnaryLayout {
    private var resolvedInsets: EdgeInsets {
        insets ?? EdgeInsets(_all: 16)
    }

    private var appliedInsets: EdgeInsets {
        let resolved = resolvedInsets
        return EdgeInsets(
            top: edges.contains(.top) ? resolved.top : 0,
            leading: edges.contains(.leading) ? resolved.leading : 0,
            bottom: edges.contains(.bottom) ? resolved.bottom : 0,
            trailing: edges.contains(.trailing) ? resolved.trailing : 0
        )
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let insets = appliedInsets
        let horizontal = insets.leading + insets.trailing
        let vertical = insets.top + insets.bottom
        let childProposal = _ProposedSize(
            width: proposal.width.map { max(0, $0 - horizontal) },
            height: proposal.height.map { max(0, $0 - vertical) }
        )
        let childSize = child.dimensions(in: childProposal).size.value
        return CGSize(
            width: childSize.width + horizontal,
            height: childSize.height + vertical
        )
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let insets = appliedInsets
        let horizontal = insets.leading + insets.trailing
        let vertical = insets.top + insets.bottom
        let proposal = _ProposedSize(
            width: context.proposedSize.width.map { max(0, $0 - horizontal) },
            height: context.proposedSize.height.map { max(0, $0 - vertical) }
        )
        return _Placement(
            proposedSize: proposal,
            anchoring: .topLeading,
            at: CGPoint(x: insets.leading, y: insets.top)
        )
    }

    func spacing(
        in context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> Spacing {
        child.layoutComputer.spacing()
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

struct DefaultPaddingEdgeInsetsProperty: PropertyKey {
    static var defaultValue: EdgeInsets { .init(_all: 16) }

    var description: String {
        "DefaultPaddingEdgeInsetsProperty"
    }
}
