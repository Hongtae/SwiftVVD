//
//  File: FocusedValues.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol FocusedValueKey {
    associatedtype Value
}

public struct FocusedValues {
    var storage: [ObjectIdentifier: Any] = [:]

    public subscript<Key>(key: Key.Type) -> Key.Value? where Key: FocusedValueKey {
        get {
            storage[ObjectIdentifier(key)] as? Key.Value
        }
        set {
            if let newValue {
                storage[ObjectIdentifier(key)] = newValue
            } else {
                storage.removeValue(forKey: ObjectIdentifier(key))
            }
        }
    }
}

@available(*, unavailable)
extension FocusedValues: Sendable {
}

extension FocusedValues: Equatable {
    public static func == (lhs: FocusedValues, rhs: FocusedValues) -> Bool {
        lhs.storage.isEmpty && rhs.storage.isEmpty
    }
}
