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

    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        LayoutComputer(
            sizeThatFits: { lc.sizeThatFits($0) },
            spacing: lc.spacing,
            place: { lc.place(at: $0, anchor: $1, proposal: $2) },
            priority: value,
            explicitAlignment: { lc.explicitAlignment($0, at: $1) }
        )
    }
}

extension View {
    public func layoutPriority(_ value: Double) -> some View {
        modifier(LayoutPriorityLayout(value: value))
    }
}
