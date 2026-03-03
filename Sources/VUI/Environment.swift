//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

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
    public subscript<T: AnyObject & Observable>(objectType type: T.Type) -> T? {
        get { values[ObjectIdentifier(type)] as? T }
        set { values[ObjectIdentifier(type)] = newValue }
    }

    // Internal subscripts for keypath literal use.
    // (T.Type is not Hashable, so ObjectIdentifier is used as the subscript index.)

    // Optional — keypath stored in Environment<T?>.init and _EnvironmentKeyWritingModifier<T?>.
    subscript<T: AnyObject & Observable>(_obs id: ObjectIdentifier) -> T? {
        get { values[id] as? T }
        set { values[id] = newValue }
    }

    // Non-optional — keypath stored in Environment<T>.init. Crashes if not injected.
    subscript<T: AnyObject & Observable>(_crashingObs id: ObjectIdentifier) -> T {
        get {
            guard let obj = values[id] as? T else {
                fatalError("No observable object of type \(T.self) found in the environment. Inject it with .environment(_ object:).")
            }
            return obj
        }
    }
}

@propertyWrapper public struct Environment<Value> {
    @usableFromInline
    enum Content: @unchecked Sendable {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }
    @usableFromInline
    var content: Content

    /// Returns the resolved value.
    ///
    /// During body evaluation, `_makeProperty` + the body rule in `View._makeView`
    /// will have already resolved this field from `.keyPath` to `.value` via `_write`.
    /// Outside that context (e.g. before the view is mounted), `.keyPath` returns
    /// the default value from an empty `EnvironmentValues`.
    @inlinable public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        }
    }

    @inlinable public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    @usableFromInline
    internal init(_ value: Value) {
        content = .value(value)
    }

    /// Returns a copy of self with `.keyPath` resolved to `.value` using `values`.
    func _resolve(_ values: EnvironmentValues) -> Self {
        if case .keyPath(let keyPath) = content {
            return Self(values[keyPath: keyPath])
        }
        return self
    }

    /// Writes `self` into the raw memory at `ptr` (must point to an `Environment<Value>` field).
    func _write(_ ptr: UnsafeMutableRawPointer) {
        ptr.assumingMemoryBound(to: Environment<Value>.self).pointee = self
    }
}

extension Environment {
    /// Reads an `Observable` object of type `Value` injected via `.environment(_ object:)`.
    /// Crashes at runtime if no object of that type is present.
    public init(_ objectType: Value.Type) where Value: AnyObject, Value: Observable {
        content = .keyPath(\EnvironmentValues[_crashingObs: ObjectIdentifier(objectType)])
    }

    /// Reads an `Observable` object of type `T` as `T?`.
    /// Returns `nil` if the object was not injected into the environment.
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        content = .keyPath(\EnvironmentValues[_obs: ObjectIdentifier(objectType)])
    }
}

extension Environment: DynamicProperty {
    /// Registers a write closure in `buffer.contexts[fieldOffset]`.
    ///
    /// The closure is called inside the body rule (see `View._makeView`) with a pointer
    /// to the corresponding field in a mutable copy of the view struct.  It reads the
    /// current `.keyPath` value from the copy, resolves it against the live
    /// `EnvironmentValues` AG node, and writes the resulting `.value` back — exactly
    /// mirroring the mutation that occurs before `body` is called.
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer,
                                        container: _GraphValue<V>,
                                        fieldOffset: Int,
                                        inputs: inout _GraphInputs) {
        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        let envAttr = inputs.cachedEnvironment.value.environment
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            // Read the .keyPath instance from the view copy, resolve, write back.
            let current = ptr.assumingMemoryBound(to: Self.self).pointee
            current._resolve(envAttr.value)._write(ptr)
        }
    }
}

extension Environment: Sendable where Value: Sendable {
}
