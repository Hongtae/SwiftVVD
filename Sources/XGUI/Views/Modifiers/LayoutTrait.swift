//
//  File: LayoutTrait.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct _LayoutTrait<K>: _ViewTraitKey where K: LayoutValueKey {
    public static var defaultValue: K.Value { K.defaultValue }
    public typealias Value = K.Value
}

extension View {
    public func layoutValue<K>(key: K.Type, value: K.Value) -> some View where K: LayoutValueKey {
        return _trait(_LayoutTrait<K>.self, value)
    }
}
