//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout: ViewModifier, Animatable, Sendable {
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _FrameLayout: UnaryLayout {
    private func childProposal(for proposal: _ProposedSize) -> _ProposedSize {
        _ProposedSize(
            width: width ?? proposal.width,
            height: height ?? proposal.height
        )
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let childSize = child.dimensions(in: childProposal(for: proposal)).size.value
        return CGSize(width: width ?? childSize.width, height: height ?? childSize.height)
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let proposal = childProposal(for: context.proposedSize)
        let childSize = child.dimensions(in: proposal).size.value
        let anchor = UnitPoint(
            x: alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5,
            y: alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5
        )
        return _Placement(
            proposedSize: proposal.fixingUnspecifiedDimensions(at: childSize),
            anchoring: anchor,
            at: CGPoint(
                x: context.size.width * anchor.x,
                y: context.size.height * anchor.y
            )
        )
    }
}

extension View {
    @inlinable nonisolated
    public func frame(width: CGFloat? = nil,
                      height: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        return modifier(
            _FrameLayout(width: width, height: height, alignment: alignment))
    }
}

public struct _FlexFrameLayout: ViewModifier, Animatable, Sendable {
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let idealHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil,
         maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
         idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, 
         alignment: Alignment) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }
  
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _FlexFrameLayout: UnaryLayout {
    private func constrainedProposal(
        _ value: CGFloat?,
        min: CGFloat?,
        ideal: CGFloat?,
        max: CGFloat?
    ) -> CGFloat? {
        guard var value = value ?? ideal else { return nil }
        if let min { value = Swift.max(value, min) }
        if let max { value = Swift.min(value, max) }
        return value
    }

    private func childProposal(for proposal: _ProposedSize) -> _ProposedSize {
        _ProposedSize(
            width: constrainedProposal(
                proposal.width,
                min: minWidth,
                ideal: idealWidth,
                max: maxWidth
            ),
            height: constrainedProposal(
                proposal.height,
                min: minHeight,
                ideal: idealHeight,
                max: maxHeight
            )
        )
    }

    private func resolvedDimension(
        _ proposed: CGFloat?,
        child: CGFloat,
        min: CGFloat?,
        ideal: CGFloat?,
        max: CGFloat?
    ) -> CGFloat {
        if let proposed {
            if let max {
                return Swift.min(Swift.max(proposed, min ?? -.infinity), max)
            }
            return Swift.max(child, min ?? -.infinity)
        }
        var value = ideal ?? child
        if let min { value = Swift.max(value, min) }
        if let max { value = Swift.min(value, max) }
        return value
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let childSize = child.dimensions(in: childProposal(for: proposal)).size.value
        return CGSize(
            width: resolvedDimension(
                proposal.width,
                child: childSize.width,
                min: minWidth,
                ideal: idealWidth,
                max: maxWidth
            ),
            height: resolvedDimension(
                proposal.height,
                child: childSize.height,
                min: minHeight,
                ideal: idealHeight,
                max: maxHeight
            )
        )
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let proposal = childProposal(for: context.proposedSize)
        let childSize = child.dimensions(in: proposal).size.value
        let anchor = UnitPoint(
            x: alignment.horizontal == .leading ? 0 : alignment.horizontal == .trailing ? 1 : 0.5,
            y: alignment.vertical == .top ? 0 : alignment.vertical == .bottom ? 1 : 0.5
        )
        return _Placement(
            proposedSize: proposal.fixingUnspecifiedDimensions(at: childSize),
            anchoring: anchor,
            at: CGPoint(
                x: context.size.width * anchor.x,
                y: context.size.height * anchor.y
            )
        )
    }
}

@usableFromInline
func log_error(_ message: String) {
    Log.error(message)
}

extension View {
    @inlinable nonisolated
    public func frame(minWidth: CGFloat? = nil,
                      idealWidth: CGFloat? = nil,
                      maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, 
                      idealHeight: CGFloat? = nil,
                      maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        func areInNondecreasingOrder(
            _ min: CGFloat?, _ ideal: CGFloat?, _ max: CGFloat?
        ) -> Bool {
            let min = min ?? -.infinity
            let ideal = ideal ?? min
            let max = max ?? ideal
            return min <= ideal && ideal <= max
        }

        if !areInNondecreasingOrder(minWidth, idealWidth, maxWidth)
            || !areInNondecreasingOrder(minHeight, idealHeight, maxHeight)
        {
            log_error("Contradictory frame constraints specified.")
        }

        return modifier(
            _FlexFrameLayout(
                minWidth: minWidth,
                idealWidth: idealWidth, maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: idealHeight, maxHeight: maxHeight,
                alignment: alignment))
    }
}
