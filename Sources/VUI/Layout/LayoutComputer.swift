//
//  File: LayoutComputer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Encapsulates a view's two-pass layout logic as closures.
///
/// Pass 1 (sizing): The parent calls `sizeThatFits(_:)` on each child.
/// Pass 2 (placement): The parent calls `place(at:anchor:proposal:)` to
///   write the final position into the child's position AG node.
///
/// An `Attribute<LayoutComputer>` is stored in `_ViewOutputs._layoutComputer`
/// for every view that participates in layout.  The parent layout
/// (e.g., VStackLayout) reads each child's `Attribute<LayoutComputer>` —
/// automatically registering a re-layout dependency — to build `LayoutSubviews`.
struct LayoutComputer {
    var _sizeThatFits: (ProposedViewSize) -> CGSize
    var _spacing: ViewSpacing
    var _dimensions: (ProposedViewSize) -> ViewDimensions
    var _place: (CGPoint, UnitPoint, ProposedViewSize) -> Void
    /// Layout priority set by `LayoutPriorityLayout`. Defaults to 0.
    var priority: Double = 0

    init(
        sizeThatFits: @escaping (ProposedViewSize) -> CGSize,
        spacing: ViewSpacing = ViewSpacing(),
        dimensions: @escaping (ProposedViewSize) -> ViewDimensions,
        place: @escaping (CGPoint, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in },
        priority: Double = 0
    ) {
        _sizeThatFits = sizeThatFits
        _spacing = spacing
        _dimensions = dimensions
        _place = place
        self.priority = priority
    }

    /// Returns the size that best fits `proposal`.
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        _sizeThatFits(proposal)
    }

    /// The view's preferred spacing to neighbouring views.
    var spacing: ViewSpacing { _spacing }

    /// Returns layout dimensions (size + alignment guides) for `proposal`.
    func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        _dimensions(proposal)
    }

    /// Places this view at `position` relative to `anchor`.
    /// Writes the resolved origin into the view's position AG node,
    /// triggering dependent rendering nodes.
    func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        _place(position, anchor, proposal)
    }

    /// A LayoutComputer that always reports the given fixed size and does nothing on placement.
    /// Used as a stub for primitive views not yet AG-implemented.
    static func fixed(_ size: CGSize) -> LayoutComputer {
        LayoutComputer(
            sizeThatFits: { _ in size },
            spacing: ViewSpacing(),
            dimensions: { _ in ViewDimensions(width: size.width, height: size.height) }
        )
    }
}
