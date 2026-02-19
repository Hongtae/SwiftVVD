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
