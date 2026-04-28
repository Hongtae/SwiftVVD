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
    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        let h = self.horizontal
        let v = self.vertical
        return LayoutComputer(
            sizeThatFits: { proposal in
                // Propose ideal (nil) for fixed axes so the child returns its natural size
                let fixedProposal = ProposedViewSize(
                    width:  h ? nil : proposal.width,
                    height: v ? nil : proposal.height
                )
                return lc.sizeThatFits(fixedProposal)
            },
            spacing: lc.spacing,
            place: { position, anchor, proposal in
                let fixedProposal = ProposedViewSize(
                    width:  h ? nil : proposal.width,
                    height: v ? nil : proposal.height
                )
                lc.place(at: position, anchor: anchor, proposal: fixedProposal)
            },
            explicitAlignment: { lc.explicitAlignment($0, at: $1) }
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

