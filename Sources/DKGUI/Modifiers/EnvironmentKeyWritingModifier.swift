//
//  File: EnvironmentKeyWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import SwiftShims

@_silgen_name("swift_reflectionMirror_recursiveCount")
internal func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
internal func _getChildMetadata(_: Any.Type, index: Int, fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
internal func _getChildOffset(_: Any.Type, index: Int) -> Int

@discardableResult
private func forEachField(of type: Any.Type, body: (Int, Any.Type) -> Bool) -> Bool {
    let numChildren = _getRecursiveChildCount(type)
    for i in 0..<numChildren {
        let offset = _getChildOffset(type, index: i)

        var field = _FieldReflectionMetadata()
        let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }

        if !body(offset, childType) {
            return false
        }
    }
    return true
}

protocol _EnvironmentModifier {
    func resolveEnvironmentValues(_ values: EnvironmentValues) -> EnvironmentValues
    func updateViewEnvironment<Content>(_ view: inout Content, values: EnvironmentValues) where Content: View
}

struct _EnvironmentKeyWritingModifier<Value>: ViewModifier, _EnvironmentModifier {
    typealias Body = Never

    var keyPath: WritableKeyPath<EnvironmentValues, Value>
    var value: Value
    init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

    func resolveEnvironmentValues(_ values: EnvironmentValues) -> EnvironmentValues {
        var values = values
        values[keyPath: self.keyPath] = value
        return values
    }

    func updateViewEnvironment<Content>(_ view: inout Content, values: EnvironmentValues) where Content: View {
        forEachField(of: Content.self) { offset, type in
            if type.self == Environment<Value>.self {
                withUnsafeMutableBytes(of: &view) {
                    let ptr = $0.baseAddress!
                        .advanced(by: offset)
                        .bindMemory(to: Environment<Value>.self,
                                    capacity: 1)
                    ptr.pointee.resolve(values)
                }
            }
            return true
        }
    }
}

extension View {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        return modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
}
