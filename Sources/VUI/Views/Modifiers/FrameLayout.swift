//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Shared placement contract for fixed and flexible frame modifiers.
///
/// Conforming layouts expose the alignment whose parent and child guides are
/// reconciled by `commonPlacement`.
private protocol FrameLayoutCommon {
    var alignment: Alignment { get }
}

private extension FrameLayoutCommon {
    func commonPlacement(
        of child: LayoutProxy,
        in context: PlacementContext,
        childProposal: _ProposedSize
    ) -> _Placement {
        let childDimensions = child.dimensions(in: childProposal)
        let parentDimensions = ViewDimensions(
            guideComputer: .defaultValue,
            size: ViewSize(context.size)
        )

        // Place the child's selected guides on the corresponding parent
        // guides. The top-leading anchor preserves the raw child proposal;
        // the later geometry pass resolves any unspecified dimensions.
        let position = CGPoint(
            x: parentDimensions[alignment.horizontal]
                - childDimensions[alignment.horizontal],
            y: parentDimensions[alignment.vertical]
                - childDimensions[alignment.vertical]
        )
        return _Placement(proposedSize: childProposal, at: position)
    }
}

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

extension _FrameLayout: FrameLayoutCommon {}

extension _FrameLayout: UnaryLayout {
    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let childProposal = _ProposedSize(
            width: width ?? proposal.width,
            height: height ?? proposal.height
        )
        let childSize = child.dimensions(in: childProposal).size.value
        return CGSize(width: width ?? childSize.width, height: height ?? childSize.height)
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let parentProposal = context.proposedSize
        let childProposal = _ProposedSize(
            width: width ?? parentProposal.width,
            height: height ?? parentProposal.height
        )
        return commonPlacement(
            of: child,
            in: context,
            childProposal: childProposal
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

extension _FlexFrameLayout: FrameLayoutCommon {}

extension _FlexFrameLayout: UnaryLayout {
    /// Builds the proposal used by the measurement pass.
    ///
    /// Placement has a separate proposal policy because an intrinsic axis can
    /// remain unspecified after the frame size has already been resolved.
    private func childProposal(myProposal: _ProposedSize) -> _ProposedSize {
        let childWidth: CGFloat?
        if var width = myProposal.width ?? idealWidth {
            if let minWidth {
                width = Swift.max(width, minWidth)
            }
            if let maxWidth {
                width = Swift.min(width, maxWidth)
            }
            childWidth = width
        } else {
            childWidth = nil
        }

        let childHeight: CGFloat?
        if var height = myProposal.height ?? idealHeight {
            if let minHeight {
                height = Swift.max(height, minHeight)
            }
            if let maxHeight {
                height = Swift.min(height, maxHeight)
            }
            childHeight = height
        } else {
            childHeight = nil
        }

        return _ProposedSize(
            width: childWidth,
            height: childHeight
        )
    }

    private func childPlacementProposal(
        of child: LayoutProxy,
        context: PlacementContext
    ) -> _ProposedSize {
        // The child parameter belongs to the placement-helper shape; proposal
        // selection itself depends only on frame constraints and context.
        func proposal(
            min: CGFloat?,
            ideal: CGFloat?,
            max: CGFloat?,
            size: CGFloat,
            parentProposal: CGFloat?
        ) -> CGFloat? {
            // A proposal-free axis strictly inside its flexible bounds stays
            // unspecified during placement. Equality with either bound, an
            // ideal, or a concrete parent proposal pins it to the frame size.
            if ideal == nil,
               parentProposal == nil,
               (min ?? -.infinity) < size,
               size < (max ?? .infinity) {
                return nil
            }
            return size
        }

        return _ProposedSize(
            width: proposal(
                min: minWidth,
                ideal: idealWidth,
                max: maxWidth,
                size: context.size.width,
                parentProposal: context.proposedSize.width
            ),
            height: proposal(
                min: minHeight,
                ideal: idealHeight,
                max: maxHeight,
                size: context.size.height,
                parentProposal: context.proposedSize.height
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
        // A concrete parent proposal and an intrinsic measurement do not use
        // the same resolution branch. Keep this policy local to flexible-frame
        // measurement; placement uses childPlacementProposal instead.
        if let proposed {
            if let max {
                return Swift.min(Swift.max(proposed, min ?? -.infinity), max)
            }
            return Swift.max(child, min ?? -.infinity)
        }
        var value = ideal ?? child
        if let min {
            value = Swift.max(value, min)
        }
        if let max {
            value = Swift.min(value, max)
        }
        return value
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let childProposal = childProposal(myProposal: proposal)
        let childSize = child.dimensions(in: childProposal).size.value
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
        // Modern semantics preserve an intrinsic axis during placement, while
        // the older baseline pins both axes to the resolved frame size.
        let childProposal = if _SemanticFeature<Semantics_v5>.isEnabled {
            childPlacementProposal(of: child, context: context)
        } else {
            _ProposedSize(context.size)
        }
        return commonPlacement(
            of: child,
            in: context,
            childProposal: childProposal
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
