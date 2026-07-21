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
}

private extension _MetadataKind {
    var supportsStoredFieldTraversal: Bool {
        switch self {
        case .struct, .enum, .optional, .tuple:
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
        _forEachField(of: type) { _, offset, fieldType, kind in
            fields.append(
                _AGComparisonField(offset: offset, type: fieldType, kind: kind)
            )
            return true
        }
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

        let fields = _AGComparisonLayout.fields(of: type, kind: kind)
        if fields.isEmpty {
            return compareRawValues(lhs, rhs, type: type)
        }
        for field in fields {
            if !compareLayoutValues(
                lhs.advanced(by: field.offset),
                rhs.advanced(by: field.offset),
                type: field.type,
                kind: field.kind
            ) {
                return false
            }
        }
        return true
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
