//
//  File: StackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StackLayoutCache {
    var spacings: [ViewSpacing] = []
    var subviewSpacings: [CGFloat] = []
    var priorities: [Double] = []
    
    // Store alignment for explicitAlignment calculation
    var horizontalAlignment: HorizontalAlignment?
    var verticalAlignment: VerticalAlignment?
}

/// Marks stack layouts that dispatch variadic view construction through layout view generation.
protocol HVStack: Layout, _VariadicView_UnaryViewRoot {
    associatedtype MinorAxisAlignment: AlignmentGuide

    var alignment: MinorAxisAlignment { get }
    var spacing: CGFloat? { get }

    static var majorAxis: Axis { get }
    static var resizeChildrenWithTrailingOverflow: Bool { get }
}

extension HVStack {
    static var resizeChildrenWithTrailingOverflow: Bool {
        false
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: Self.majorAxis)
    }

    public static func _makeView(root: _GraphValue<Self>,
                                 inputs: _ViewInputs,
                                 body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        Self._makeLayoutView(root: root, inputs: inputs, body: body)
    }
}
