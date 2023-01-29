//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//


public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct EnvironmentValues: CustomStringConvertible {
    var values: [ObjectIdentifier: Any]

    public init() {
        self.values = [:]
    }

    public subscript<K>(key: K.Type) -> K.Value where K: EnvironmentKey {
        get {
            if let value = values[ObjectIdentifier(key)] as? K.Value {
                return value
            }
            return K.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }

    public var description: String { String(describing: values) }
}

@propertyWrapper public struct Environment<Value>: DynamicProperty {
    enum Content {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }
    var content: Content

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        }
    }
}
