//
//  File: AGComparison.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

private struct _AGComparisonField {
    var offset: Int
    var type: Any.Type
    var kind: _MetadataKind
    var isStrong: Bool
}

private extension _MetadataKind {
    var supportsStoredFieldTraversal: Bool {
        switch self {
        case .struct, .tuple:
            return true
        default:
            return false
        }
    }
}

private func _isOpaqueExistentialContainer(
    _ type: Any.Type,
    kind: _MetadataKind
) -> Bool {
    kind == .existential
        && _AGGraph.valueSize(of: type) >= 4 * MemoryLayout<UInt>.size
}

protocol _AnyAGValueStorage: AnyObject {
    var anyValue: Any { get }
}

final class _AGValueStorage<Value>: _AnyAGValueStorage {
    private let storage: UnsafeMutablePointer<Value>

    init(_ value: Value) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: value)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    var pointer: UnsafePointer<Value> {
        UnsafePointer(storage)
    }

    var anyValue: Any {
        storage.pointee
    }
}

private enum _AGComparisonLayout {
    private static let cache = Mutex<[ObjectIdentifier: [_AGComparisonField]]>([:])

    // Field offsets are metadata-owned and remain stable for the lifetime of
    // the corresponding type metadata.
    static func fields(
        of type: Any.Type,
        kind: _MetadataKind
    ) -> [_AGComparisonField] {
        guard kind.supportsStoredFieldTraversal else {
            return []
        }
        let identifier = ObjectIdentifier(type)
        if let cached = cache.withLock({ $0[identifier] }) {
            return cached
        }

        var fields: [_AGComparisonField] = []
        let collect: (
            UnsafePointer<CChar>,
            Int,
            Any.Type,
            _EachFieldMetadata
        ) -> Bool = { _, offset, fieldType, metadata in
            fields.append(
                _AGComparisonField(
                    offset: offset,
                    type: fieldType,
                    kind: metadata.kind,
                    isStrong: metadata.isStrong
                )
            )
            return true
        }
        _forEachFieldWithMetadata(of: type, body: collect)
        return cache.withLock { cache in
            if let cached = cache[identifier] {
                return cached
            }
            cache[identifier] = fields
            return fields
        }
    }
}

extension _AGGraph {
    static func compareValues<Value>(
        _ lhs: Value,
        _ rhs: Value,
        options: AGComparisonOptions
    ) -> Bool {
        withUnsafePointer(to: lhs) { lhsPointer in
            withUnsafePointer(to: rhs) { rhsPointer in
                compareStoredValues(lhsPointer, rhsPointer, options: options)
            }
        }
    }

    static func compareStoredValues<Value>(
        _ lhs: UnsafePointer<Value>,
        _ rhs: UnsafePointer<Value>,
        options: AGComparisonOptions
    ) -> Bool {
        if Value.self == String.self {
            return lhs.pointee as! String == rhs.pointee as! String
        }
        if options.rawValue & 0xff <= 2 {
            return compareLayoutValues(
                lhs,
                rhs,
                type: Value.self,
                kind: _MetadataKind(Value.self)
            )
        }
        return compareRawValues(lhs, rhs, type: Value.self)
    }

    private static func compareLayoutValues(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        type: Any.Type,
        kind: _MetadataKind
    ) -> Bool {
        if lhs == rhs {
            return true
        }
        if type == String.self {
            return lhs.assumingMemoryBound(to: String.self).pointee
                == rhs.assumingMemoryBound(to: String.self).pointee
        }
        if type is AnyClass {
            // Class storage is the reference itself. Instance fields belong to
            // the referenced object and do not participate in value equality.
            return compareRawValues(lhs, rhs, type: type)
        }
        if _isOpaqueExistentialContainer(type, kind: kind) {
            return compareOpaqueExistentialValues(
                lhs,
                rhs,
                type: type
            )
        }
        if kind == .enum || kind == .optional {
            return compareEnumValues(lhs, rhs, type: type)
        }

        let fields = _AGComparisonLayout.fields(of: type, kind: kind)
        if fields.isEmpty {
            return compareRawValues(lhs, rhs, type: type)
        }
        for field in fields {
            let lhsField = lhs.advanced(by: field.offset)
            let rhsField = rhs.advanced(by: field.offset)
            let isEqual = if field.isStrong {
                compareLayoutValues(
                    lhsField,
                    rhsField,
                    type: field.type,
                    kind: field.kind
                )
            } else {
                // Non-strong references use runtime-managed storage and cannot
                // be interpreted as ordinary values of the reported type.
                compareRawValues(lhsField, rhsField, type: field.type)
            }
            if !isEqual {
                return false
            }
        }
        return true
    }

    private static func compareEnumValues(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        type: Any.Type
    ) -> Bool {
        func compare<Value>(_ type: Value.Type) -> Bool {
            compareEnumValues(
                lhs.assumingMemoryBound(to: Value.self),
                rhs.assumingMemoryBound(to: Value.self)
            )
        }
        return _openExistential(type, do: compare)
    }

    private static func compareEnumValues<Value>(
        _ lhs: UnsafePointer<Value>,
        _ rhs: UnsafePointer<Value>
    ) -> Bool {
        guard let lhsCase = _enumCaseName(of: lhs.pointee),
              let rhsCase = _enumCaseName(of: rhs.pointee) else {
            return compareRawValues(lhs, rhs, type: Value.self)
        }
        guard cStringsEqual(lhsCase, rhsCase) else {
            return false
        }

        switch (_enumPayload(of: lhs.pointee), _enumPayload(of: rhs.pointee)) {
        case (nil, nil):
            return true
        case let (lhsPayload?, rhsPayload?):
            return compareEnumPayloads(lhsPayload, rhsPayload)
        default:
            return false
        }
    }

    private static func compareEnumPayloads(
        _ lhsPayload: Any,
        _ rhsPayload: Any
    ) -> Bool {
        // Open the payload type before comparing so an out-of-line existential
        // box does not become part of the value comparison.
        func compare<Payload>(_ lhs: Payload) -> Bool {
            guard let rhs = rhsPayload as? Payload else {
                return false
            }
            return withUnsafePointer(to: lhs) { lhsPointer in
                withUnsafePointer(to: rhs) { rhsPointer in
                    compareLayoutValues(
                        lhsPointer,
                        rhsPointer,
                        type: Payload.self,
                        kind: _MetadataKind(Payload.self)
                    )
                }
            }
        }
        return _openExistential(lhsPayload, do: compare)
    }

    private static func cStringsEqual(
        _ lhs: UnsafePointer<CChar>,
        _ rhs: UnsafePointer<CChar>
    ) -> Bool {
        var index = 0
        while lhs[index] == rhs[index] {
            if lhs[index] == 0 {
                return true
            }
            index += 1
        }
        return false
    }

    private static func compareRawValues(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        type: Any.Type
    ) -> Bool {
        let count = valueSize(of: type)
        return compareRawRange(lhs, rhs, offset: 0, count: count)
    }

    private static func compareOpaqueExistentialValues(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        type: Any.Type
    ) -> Bool {
        let wordSize = MemoryLayout<UInt>.size
        let metadataOffset = 3 * wordSize
        let count = valueSize(of: type)
        guard compareRawRange(
            lhs,
            rhs,
            offset: metadataOffset,
            count: count - metadataOffset
        ) else {
            return false
        }

        let metadata = lhs.load(
            fromByteOffset: metadataOffset,
            as: UnsafeRawPointer.self
        )
        let dynamicType = unsafeBitCast(metadata, to: Any.Type.self)
        let layout = valueLayout(of: dynamicType)
        if layout.size > metadataOffset || layout.alignment > wordSize {
            return compareRawRange(lhs, rhs, offset: 0, count: wordSize)
        }
        return compareLayoutValues(
            lhs,
            rhs,
            type: dynamicType,
            kind: _MetadataKind(dynamicType)
        )
    }

    private static func compareRawRange(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        offset: Int,
        count: Int
    ) -> Bool {
        guard count > 0 else { return true }
        let lhsBytes = UnsafeRawBufferPointer(
            start: lhs.advanced(by: offset),
            count: count
        )
        let rhsBytes = UnsafeRawBufferPointer(
            start: rhs.advanced(by: offset),
            count: count
        )
        return lhsBytes.elementsEqual(rhsBytes)
    }

    fileprivate static func valueSize(of type: Any.Type) -> Int {
        valueLayout(of: type).size
    }

    private static func valueLayout(
        of type: Any.Type
    ) -> (size: Int, alignment: Int) {
        func layout<Value>(
            of type: Value.Type
        ) -> (size: Int, alignment: Int) {
            (MemoryLayout<Value>.size, MemoryLayout<Value>.alignment)
        }
        return _openExistential(type, do: layout)
    }
}
