//
//  File: StackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StackLayoutCache {
    var minSizes: [CGSize] = []
    var maxSizes: [CGSize] = []
    var spacings: [ViewSpacing] = []
    var priorities: [Double] = []
    var subviewSpacings: CGFloat = .zero
}
