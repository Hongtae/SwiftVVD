//
//  File: LayoutPriority.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LayoutPriorityTraitKey: _ViewTraitKey {
    public static var defaultValue: Double { 0 }
}

extension View {
    public func layoutPriority(_ value: Double) -> some View {
        return _trait(LayoutPriorityTraitKey.self, value)
    }
}
