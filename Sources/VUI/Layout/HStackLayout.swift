//
//  File: HStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _HStackLayout.Cache

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension HStackLayout: DerivedLayout {
    var base: _HStackLayout {
        _HStackLayout(alignment: alignment, spacing: spacing)
    }
}

public struct _HStackLayout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension _HStackLayout: _VariadicView_UnaryViewRoot {}
extension _HStackLayout: _VariadicView_ViewRoot {}
extension _HStackLayout: _VariadicView_ImplicitRoot {
    static var implicitRoot: Self {
        Self()
    }
}
extension _HStackLayout: Sendable {}

extension _HStackLayout: HVStack {
    typealias MinorAxisAlignment = VerticalAlignment

    static var majorAxis: Axis {
        .horizontal
    }
}
