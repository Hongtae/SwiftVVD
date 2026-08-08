//
//  File: LayoutPriority.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LayoutPriorityTraitKey: _ViewTraitKey {
    public static var defaultValue: Double { 0 }
}

/// `UnaryLayout` that sets the layout priority on the child's `LayoutComputer`.
/// Wraps the child LC and overrides its `priority` field.
struct LayoutPriorityLayout: UnaryLayout {
    var value: Double
    typealias Body = Never

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        child.dimensions(in: proposal).size.value
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        return _Placement(
            proposedSize: context.proposedSize,
            aligning: .center,
            in: context.size
        )
    }

    func layoutPriority(child: LayoutProxy) -> Double {
        value
    }
}

extension View {
    public func layoutPriority(_ value: Double) -> some View {
        modifier(LayoutPriorityLayout(value: value))
    }
}
