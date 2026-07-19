//
//  File: FixedSizeLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FixedSizeLayout: ViewModifier, Animatable, Sendable {
    @inlinable public init(horizontal: Bool = true, vertical: Bool = true) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    @usableFromInline var horizontal: Bool
    @usableFromInline var vertical: Bool

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _FixedSizeLayout: UnaryLayout {
    private func childProposal(for proposal: _ProposedSize) -> _ProposedSize {
        _ProposedSize(
            width: horizontal ? nil : proposal.width,
            height: vertical ? nil : proposal.height
        )
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        child.dimensions(in: childProposal(for: proposal)).size.value
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let proposal = childProposal(for: context.proposedSize)
        let childSize = child.dimensions(in: proposal).size.value
        return _Placement(
            proposedSize: proposal.fixingUnspecifiedDimensions(at: childSize),
            anchoring: .topLeading,
            at: .zero
        )
    }
}

extension View {
    @inlinable public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        return modifier(
            _FixedSizeLayout(horizontal: horizontal, vertical: vertical))
    }

    @inlinable public func fixedSize() -> some View {
        return fixedSize(horizontal: true, vertical: true)
    }
}
