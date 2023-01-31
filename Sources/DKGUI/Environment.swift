//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import SwiftShims
import DKGame

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func _getChildMetadata(_: Any.Type, index: Int, fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func _getChildOffset(_: Any.Type, index: Int) -> Int

@discardableResult
private func forEachField(of type: Any.Type, body: (UnsafePointer<CChar>, Int, Any.Type) -> Bool) -> Bool {
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

protocol _EnvironmentResolve {
    mutating func resolve(_: EnvironmentValues)
}

@propertyWrapper public struct Environment<Value>: DynamicProperty, _EnvironmentResolve {
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

    mutating func resolve(_ values: EnvironmentValues) {
        if case .keyPath(let keyPath) = content {
            content = .value(values[keyPath: keyPath])
        }
    }
}

extension EnvironmentValues {
    func resolve(modifiers: [any ViewModifier]) -> EnvironmentValues {
        var environmentValues = self
        modifiers.forEach { modifier in
            if let env = modifier as? _EnvironmentValuesResolve {
                environmentValues = env.resolve(environmentValues)
            }
        }
        return environmentValues
    }

    func resolve<Content>(_ view: Content) -> Content where Content: View {
        var view = view
        forEachField(of: Content.self) { charPtr, offset, type in
            if type.self is _EnvironmentResolve.Type {
                let name = String(cString: charPtr)
                Log.debug("field: \(name) type: \(type.self)")

                withUnsafeMutableBytes(of: &view) {
                    let ptr = $0.baseAddress!
                        .advanced(by: offset)
                        .bindMemory(to: _EnvironmentResolve.self,
                                    capacity: 1)
                    ptr.pointee.resolve(self)
                }
            }
            return true
        }
        return view
    }
}
