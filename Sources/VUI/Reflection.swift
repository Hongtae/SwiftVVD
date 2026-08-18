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

private typealias _EnumTagWitness = @convention(c) (
    UnsafeRawPointer,
    UnsafeRawPointer
) -> UInt32

private typealias _DestroyValueWitness = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeRawPointer
) -> Void

private typealias _InitializeWithCopyValueWitness = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer,
    UnsafeRawPointer
) -> UnsafeMutableRawPointer

private typealias _ProjectEnumDataValueWitness = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeRawPointer
) -> Void

private typealias _InjectEnumTagValueWitness = @convention(c) (
    UnsafeMutableRawPointer,
    UInt32,
    UnsafeRawPointer
) -> Void

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
    case extendedExistential = 0x307
    case heapLocalVariable = 0x400
    case heapGenericLocalVariable = 0x500
    case errorObject = 0x501
    case unknown = 0xffff

    init(_ type: Any.Type) {
        self = _MetadataKind(rawValue: _getMetadataKind(type)) ?? .unknown
    }
}

struct _EnumValueWitnesses: @unchecked Sendable {
    private static let wordSize = MemoryLayout<UInt>.size
    private static let destroyOffset = wordSize
    private static let initializeWithCopyOffset = 2 * wordSize
    private static let sizeOffset = 8 * wordSize
    private static let flagsOffset = 10 * wordSize
    private static let getTagOffset =
        flagsOffset + 2 * MemoryLayout<UInt32>.size
    private static let projectDataOffset = getTagOffset + wordSize
    private static let injectTagOffset = projectDataOffset + wordSize

    let metadata: UnsafeRawPointer
    private let table: UnsafeRawPointer

    init?(_ type: Any.Type) {
        let kind = _MetadataKind(type)
        guard kind == .enum || kind == .optional else { return nil }
        metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        table = metadata.advanced(by: -Self.wordSize).load(
            as: UnsafeRawPointer.self
        )
    }

    var size: Int {
        Int(table.load(fromByteOffset: Self.sizeOffset, as: UInt.self))
    }

    var alignment: Int {
        let flags = table.load(
            fromByteOffset: Self.flagsOffset,
            as: UInt32.self
        )
        return Int(flags & 0xff) + 1
    }

    func tag(of value: UnsafeRawPointer) -> UInt32 {
        let function = table.load(
            fromByteOffset: Self.getTagOffset,
            as: UnsafeRawPointer.self
        )
        return unsafeBitCast(function, to: _EnumTagWitness.self)(
            value,
            metadata
        )
    }

    @discardableResult
    func initializeWithCopy(
        _ destination: UnsafeMutableRawPointer,
        from source: UnsafeRawPointer
    ) -> UnsafeMutableRawPointer {
        let function = table.load(
            fromByteOffset: Self.initializeWithCopyOffset,
            as: UnsafeRawPointer.self
        )
        return unsafeBitCast(
            function,
            to: _InitializeWithCopyValueWitness.self
        )(
            destination,
            UnsafeMutableRawPointer(mutating: source),
            metadata
        )
    }

    func destroy(_ value: UnsafeMutableRawPointer) {
        let function = table.load(
            fromByteOffset: Self.destroyOffset,
            as: UnsafeRawPointer.self
        )
        unsafeBitCast(function, to: _DestroyValueWitness.self)(value, metadata)
    }

    func projectEnumData(_ value: UnsafeMutableRawPointer) {
        let function = table.load(
            fromByteOffset: Self.projectDataOffset,
            as: UnsafeRawPointer.self
        )
        unsafeBitCast(
            function,
            to: _ProjectEnumDataValueWitness.self
        )(value, metadata)
    }

    func injectEnumTag(_ tag: UInt32, into value: UnsafeMutableRawPointer) {
        let function = table.load(
            fromByteOffset: Self.injectTagOffset,
            as: UnsafeRawPointer.self
        )
        unsafeBitCast(
            function,
            to: _InjectEnumTagValueWitness.self
        )(value, tag, metadata)
    }
}

struct _EnumCaseMetadata: @unchecked Sendable {
    let payloadType: Any.Type?
    let isIndirect: Bool
}

private func _resolveRelativePointer(
    storedAt field: UnsafeRawPointer
) -> UnsafeRawPointer? {
    let offset = field.load(as: Int32.self)
    guard offset != 0 else { return nil }
    return field.advanced(by: Int(offset))
}

private func _symbolicMangledNameLength(
    at start: UnsafePointer<UInt8>
) -> UInt {
    var cursor = start
    while cursor.pointee != 0 {
        let byte = cursor.pointee
        cursor = cursor.advanced(by: 1)
        if byte >= 0x01 && byte <= 0x17 {
            cursor = cursor.advanced(by: MemoryLayout<Int32>.size)
        } else if byte >= 0x18 && byte <= 0x1f {
            cursor = cursor.advanced(by: MemoryLayout<UInt>.size)
        }
    }
    return UInt(start.distance(to: cursor))
}

func _enumCaseMetadata(of type: Any.Type) -> [_EnumCaseMetadata]? {
    let kind = _MetadataKind(type)
    guard kind == .enum || kind == .optional else { return nil }

    let wordSize = MemoryLayout<UInt>.size
    let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
    let descriptor = metadata.load(
        fromByteOffset: wordSize,
        as: UnsafeRawPointer.self
    )
    let payloadCasesAndSizeOffset = descriptor.load(
        fromByteOffset: 20,
        as: UInt32.self
    )
    let payloadCaseCount = Int(payloadCasesAndSizeOffset & 0x00ff_ffff)
    let emptyCaseCount = Int(
        descriptor.load(fromByteOffset: 24, as: UInt32.self)
    )
    let caseCount = payloadCaseCount + emptyCaseCount
    guard caseCount > 0 else { return [] }

    let fieldsField = descriptor.advanced(
        by: 4 * MemoryLayout<UInt32>.size
    )
    guard let fields = _resolveRelativePointer(storedAt: fieldsField) else {
        return nil
    }
    let descriptorKind = fields.load(fromByteOffset: 8, as: UInt16.self)
    let recordSize = Int(fields.load(fromByteOffset: 10, as: UInt16.self))
    let recordCount = Int(fields.load(fromByteOffset: 12, as: UInt32.self))
    guard (descriptorKind == 2 || descriptorKind == 3),
          recordSize >= 12,
          recordCount == caseCount else {
        return nil
    }

    let records = fields.advanced(by: 16)
    let genericArguments = metadata.advanced(by: 2 * wordSize)
    var cases: [_EnumCaseMetadata] = []
    cases.reserveCapacity(recordCount)
    for index in 0..<recordCount {
        let record = records.advanced(by: index * recordSize)
        let flags = record.load(as: UInt32.self)
        let typeField = record.advanced(by: MemoryLayout<UInt32>.size)
        let payloadType: Any.Type?
        if let mangledTypePointer = _resolveRelativePointer(
            storedAt: typeField
        ) {
            let mangledType = mangledTypePointer.assumingMemoryBound(
                to: UInt8.self
            )
            guard let resolvedType = _getTypeByMangledNameInContext(
                mangledType,
                _symbolicMangledNameLength(at: mangledType),
                genericContext: descriptor,
                genericArguments: genericArguments
            ) else {
                return nil
            }
            payloadType = resolvedType
        } else {
            payloadType = nil
        }
        cases.append(
            _EnumCaseMetadata(
                payloadType: payloadType,
                isIndirect: flags & 1 != 0
            )
        )
    }
    return cases
}

struct _EachFieldMetadata: Sendable {
    let kind: _MetadataKind
    let isStrong: Bool
    let isVar: Bool
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

/// Visits each stored field and includes its runtime kind and storage flags.
/// Returning false stops traversal.
@discardableResult
func _forEachFieldWithMetadata(
    of type: Any.Type,
    options: _EachFieldOptions = [],
    body: (
        UnsafePointer<CChar>,
        Int,
        Any.Type,
        _EachFieldMetadata
    ) -> Bool
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
        let metadata = _EachFieldMetadata(
            kind: _MetadataKind(childType),
            isStrong: field.isStrong,
            isVar: field.isVar
        )

        if let name = field.name {
            if !body(name, offset, childType, metadata) {
                return false
            }
        } else {
            if !body("", offset, childType, metadata) {
                return false
            }
        }
    }
    return true
}
