//
//  File: Reflection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import SwiftShims

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
func _forEachField(of type: Any.Type, body: (UnsafePointer<CChar>, Int, Any.Type) -> Bool) -> Bool {
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
