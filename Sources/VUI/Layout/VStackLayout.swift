//
//  File: VStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _VStackLayout.Cache

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension VStackLayout: DerivedLayout {
    var base: _VStackLayout {
        _VStackLayout(alignment: alignment, spacing: spacing)
    }
}

public struct _VStackLayout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = _StackLayoutCache

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension _VStackLayout: _VariadicView_UnaryViewRoot {}
extension _VStackLayout: _VariadicView_ViewRoot {}
extension _VStackLayout: _VariadicView_ImplicitRoot {
    static var implicitRoot: Self {
        Self()
    }
}
extension _VStackLayout: Sendable {}

extension _VStackLayout: HVStack {
    typealias MinorAxisAlignment = HorizontalAlignment

    static var majorAxis: Axis {
        .vertical
    }
}
