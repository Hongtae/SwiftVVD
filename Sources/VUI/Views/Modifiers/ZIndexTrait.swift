//
//  File: ZIndexTrait.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct ZIndexTraitKey: _ViewTraitKey {
    @inlinable static var defaultValue: Double { 0 }
    @usableFromInline typealias Value = Double
}

extension View {
    /// Writes the z-index trait consumed by dynamic containers during display ordering.
    @inlinable public func zIndex(_ value: Double) -> some View {
        _trait(ZIndexTraitKey.self, value)
    }
}
