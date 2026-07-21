//
//  File: Reflection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import SwiftShims

// Runtime entry points used to enumerate stored fields without allocating
// intermediate mirror values.

// The original reflection code can be found here:
// https://github.com/apple/swift/blob/main/stdlib/public/core/ReflectionMirror.swift

private func _isClassType(_ type: Any.Type) -> Bool {
    swift_isClassType(unsafeBitCast(type, to: UnsafeRawPointer.self))
}

@_silgen_name("swift_getMetadataKind")
private func _getMetadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func _getChildMetadata(_: Any.Type, index: Int, fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func _getChildOffset(_: Any.Type, index: Int) -> Int

enum _MetadataKind: UInt, Sendable {
    case `class` = 0
    case `struct` = 0x200
    case `enum` = 0x201
    case optional = 0x202
    case foreignClass = 0x203
    case opaque = 0x300
    case tuple = 0x301
    case function = 0x302
    case existential = 0x303
    case metatype = 0x304
    case objcClassWrapper = 0x305
    case existentialMetatype = 0x306
    case heapLocalVariable = 0x400
    case heapGenericLocalVariable = 0x500
    case errorObject = 0x501
    case unknown = 0xffff

    init(_ type: Any.Type) {
        self = _MetadataKind(rawValue: _getMetadataKind(type)) ?? .unknown
    }
}

struct _EachFieldOptions: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    nonisolated(unsafe) static var classType = _EachFieldOptions(rawValue: 1 << 0)
    nonisolated(unsafe) static var ignoreUnknown = _EachFieldOptions(rawValue: 1 << 1)
}

/// Visits each stored field in declaration order with its name, byte offset,
/// and runtime type. Returning false stops traversal.
@discardableResult
func _forEachField(of type: Any.Type, body: (UnsafePointer<CChar>, Int, Any.Type) -> Bool) -> Bool {
    let numChildren = _getRecursiveChildCount(type)
    for i in 0..<numChildren {
        let offset = _getChildOffset(type, index: i)

        var field = _FieldReflectionMetadata()
        let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }

        if let name = field.name {
            if !body(name, offset, childType) {
                return false
            }
        } else {
            if !body("", offset, childType) {
                return false
            }
        }
    }
    return true
}

/// Visits each stored field in declaration order and includes its runtime
/// metadata kind. Returning false stops traversal.
@discardableResult
func _forEachField(
    of type: Any.Type,
    options: _EachFieldOptions = [],
    body: (UnsafePointer<CChar>, Int, Any.Type, _MetadataKind) -> Bool
) -> Bool {
    if _isClassType(type) != options.contains(.classType) {
        return false
    }

    let numChildren = _getRecursiveChildCount(type)
    for i in 0..<numChildren {
        let offset = _getChildOffset(type, index: i)

        var field = _FieldReflectionMetadata()
        let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }
        let kind = _MetadataKind(childType)

        if let name = field.name {
            if !body(name, offset, childType, kind) {
                return false
            }
        } else {
            if !body("", offset, childType, kind) {
                return false
            }
        }
    }
    return true
}
