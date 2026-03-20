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

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        var modified = lc
        modified.priority = value
        return modified
    }
}

extension View {
    public func layoutPriority(_ value: Double) -> some View {
        modifier(LayoutPriorityLayout(value: value))
    }
}
