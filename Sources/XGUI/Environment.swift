//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
    static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool
}

extension EnvironmentKey {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        false
    }
}

extension EnvironmentKey where Self.Value: Equatable {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        lhs == rhs
    }
}

protocol _EnvironmentValuesResolve {
    func _resolve(_ values: inout EnvironmentValues)
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

extension EnvironmentValues {
    mutating func _resolve(modifiers: [any ViewModifier]) {
        var environmentValues = self
        modifiers.forEach { modifier in
            if let env = modifier as? _EnvironmentValuesResolve {
                env._resolve(&environmentValues)
            }
        }
        self = environmentValues
    }
}

@propertyWrapper public struct Environment<Value>: DynamicProperty {
    enum Content: @unchecked Sendable {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }
    var content: Content

    public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        }
    }

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    private init(_ value: Value) {
        content = .value(value)
    }

    func _resolve(_ values: EnvironmentValues) -> Self {
        if case .keyPath(let keyPath) = content {
            return Self(values[keyPath: keyPath])
        }
        return self
    }

    func _write(_ ptr: UnsafeMutableRawPointer) {
        let env = ptr.assumingMemoryBound(to: Environment<Value>.self)
        env.pointee = self
    }
}

extension Environment: _DynamicPropertyStorageBinding {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer,
                                        container: _GraphValue<V>,
                                        fieldOffset: Int,
                                        inputs: inout _GraphInputs) {
        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        buffer.properties.append(.init(type: self, offset: fieldOffset))
    }

    mutating func bind(in buffer: inout _DynamicPropertyBuffer, fieldOffset: Int, view: ViewContext, tracker: Tracker) {
        if case .keyPath(let keyPath) = content {
            let value = view.environment[keyPath: keyPath]
            self.content = .value(value)
        }
    }
}

extension Environment: Sendable where Value: Sendable {
}
