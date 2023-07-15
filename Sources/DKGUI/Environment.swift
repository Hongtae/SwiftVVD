//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import SwiftShims
import DKGame

// The original reflection code can be found here:
// https://github.com/apple/swift/blob/main/stdlib/public/core/ReflectionMirror.swift

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func _getChildMetadata(_: Any.Type, index: Int, fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func _getChildOffset(_: Any.Type, index: Int) -> Int

// Note: I modified some code that I don't think is necessary. (removed _MetadataKind)
@discardableResult
private func _forEachField(of type: Any.Type, body: (UnsafePointer<CChar>, Int, Any.Type) -> Bool) -> Bool {
    let numChildren = _getRecursiveChildCount(type)
    for i in 0..<numChildren {
        let offset = _getChildOffset(type, index: i)

        var field = _FieldReflectionMetadata()
        let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }

        if !body(field.name!, offset, childType) {
            return false
        }
    }
    return true
}


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

protocol _EnvironmentValuesResolve {
    func _resolve(_: EnvironmentValues) -> EnvironmentValues
}

protocol _EnvironmentResolve {
    func _resolve(_: EnvironmentValues) -> Self
    func _write(_: UnsafeMutableRawPointer)
}

@propertyWrapper public struct Environment<Value>: DynamicProperty, _EnvironmentResolve {
    enum Content {
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

extension EnvironmentValues {
    func _resolve(modifiers: [any ViewModifier]) -> EnvironmentValues {
        var environmentValues = self
        modifiers.forEach { modifier in
            if let env = modifier as? _EnvironmentValuesResolve {
                environmentValues = env._resolve(environmentValues)
            }
        }
        return environmentValues
    }

    func _resolve<Content>(_ view: _GraphValue<Content>) -> _GraphValue<Content> where Content: View {
        _GraphValue(_resolve(view.value))
    }

    func _resolve<Content>(_ view: Content) -> Content where Content: View {
        var view = view
        var resolvedEnvironments: [String: _EnvironmentResolve] = [:]

        for (label, value) in Mirror(reflecting: view).children {
            if let label, let value = value as? _EnvironmentResolve {
                resolvedEnvironments[label] = value._resolve(self)
            }
        }
        _forEachField(of: Content.self) { charPtr, offset, fieldType in
            if fieldType.self is _EnvironmentResolve.Type {
                let name = String(cString: charPtr)
                // Log.debug("Update environment: \(Content.self).\(name) (type: \(fieldType), offset: \(offset))")
                if let env = resolvedEnvironments[name] {
                    assert(type(of: env) == fieldType, "object type mismatch!")
                    withUnsafeMutableBytes(of: &view) {
                        let ptr = $0.baseAddress!.advanced(by: offset)
                        env._write(ptr)
                    }
                } else {
                    Log.warn("Unable to update environment: \(Content.self).\(name) (type: \(fieldType))")
                }
            }
            return true
        }
        return view
    }
}
