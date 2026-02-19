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

extension View {
    @inlinable public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        return modifier(
            _FixedSizeLayout(horizontal: horizontal, vertical: vertical))
    }

    @inlinable public func fixedSize() -> some View {
        return fixedSize(horizontal: true, vertical: true)
    }
}

extension _FixedSizeLayout: _ViewLayoutModifier {
    private class LayoutViewContext: ViewModifierContext<_FixedSizeLayout> {
        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            guard let modifier else { fatalError("Invalid view modifier") }
            
            // For fixed size dimensions, we don't constrain the child
            // by passing nil for those dimensions
            let childProposal = ProposedViewSize(
                width: modifier.horizontal ? nil : proposal.width,
                height: modifier.vertical ? nil : proposal.height
            )
            
            return self.body.sizeThatFits(childProposal)
        }
        
        override func layoutSubviews() {
            guard let modifier else { fatalError("Invalid view modifier") }
            
            let frame = self.bounds
            
            // For fixed dimensions, get child's ideal size
            // For non-fixed dimensions, use parent's allocated size
            let childIdealSize = self.body.sizeThatFits(
                ProposedViewSize(
                    width: modifier.horizontal ? nil : frame.width,
                    height: modifier.vertical ? nil : frame.height
                )
            )
            
            let proposalWidth = modifier.horizontal ? childIdealSize.width : frame.width
            let proposalHeight = modifier.vertical ? childIdealSize.height : frame.height
            
            let position = CGPoint(x: frame.midX, y: frame.midY)
            let proposal = ProposedViewSize(width: proposalWidth, height: proposalHeight)
            self.body.place(at: position, anchor: .center, proposal: proposal)
        }
    }
    
    static func _makeLayoutView(modifier: _GraphValue<Self>, inputs: _ViewInputs, content: any ViewGenerator) -> any ViewGenerator {
        UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
            let body = content.makeView()
            return LayoutViewContext(graph: graph, body: body, inputs: inputs)
        }
    }
}
