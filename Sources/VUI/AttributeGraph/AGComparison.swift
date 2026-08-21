//
//  File: AGComparison.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

protocol _AGTypeDescriptorEquatable {
    static func _agTypeDescriptorValuesEqual(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer
    ) -> Bool
}

extension _AGTypeDescriptorEquatable where Self: Equatable {
    static func _agTypeDescriptorValuesEqual(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer
    ) -> Bool {
        lhs.assumingMemoryBound(to: Self.self).pointee
            == rhs.assumingMemoryBound(to: Self.self).pointee
    }
}

private final class _AGPreparedEnumLayout: @unchecked Sendable {
    let witnesses: _EnumValueWitnesses
    let cases: [_EnumCaseMetadata]

    init?(_ type: Any.Type) {
        guard let witnesses = _EnumValueWitnesses(type),
              let cases = _enumCaseMetadata(of: type) else {
            return nil
        }
        self.witnesses = witnesses
        self.cases = cases
    }
}

private enum _AGPreparedComparisonOperation: @unchecked Sendable {
    case bytes(offset: Int, count: Int)
    case string(offset: Int)
    case registeredEquality(
        offset: Int,
        type: any _AGTypeDescriptorEquatable.Type
    )
    case enumValue(offset: Int, layout: _AGPreparedEnumLayout)
    case opaqueExistential(offset: Int, type: Any.Type)
    case alwaysUnequal(offset: Int)

    func offset(by delta: Int) -> Self {
        switch self {
        case let .bytes(offset, count):
            .bytes(offset: offset + delta, count: count)
        case let .string(offset):
            .string(offset: offset + delta)
        case let .registeredEquality(offset, type):
            .registeredEquality(offset: offset + delta, type: type)
        case let .enumValue(offset, layout):
            .enumValue(offset: offset + delta, layout: layout)
        case let .opaqueExistential(offset, type):
            .opaqueExistential(offset: offset + delta, type: type)
        case let .alwaysUnequal(offset):
            .alwaysUnequal(offset: offset + delta)
        }
    }
}

private final class _AGPreparedComparisonProgram: @unchecked Sendable {
    let operations: [_AGPreparedComparisonOperation]

    init(operations: [_AGPreparedComparisonOperation]) {
        self.operations = operations
    }
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

private func _existentialFlags(
    _ type: Any.Type,
    kind: _MetadataKind
) -> UInt32? {
    guard kind == .existential else { return nil }
    let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
    return metadata.load(
        fromByteOffset: MemoryLayout<UInt>.size,
        as: UInt32.self
    )
}

private func _isErrorExistentialContainer(
    _ type: Any.Type,
    kind: _MetadataKind
) -> Bool {
    guard let flags = _existentialFlags(type, kind: kind) else {
        return false
    }
    let specialProtocolMask = UInt32(0x3f) << 24
    let errorProtocol = UInt32(1) << 24
    return flags & specialProtocolMask == errorProtocol
}

private func _isOpaqueExistentialContainer(
    _ type: Any.Type,
    kind: _MetadataKind
) -> Bool {
    guard let flags = _existentialFlags(type, kind: kind),
          _AGGraph.valueSize(of: type) >= 4 * MemoryLayout<UInt>.size else {
        return false
    }
    // The high metadata flag is set for non-class-constrained existentials.
    return flags & (UInt32(1) << 31) != 0
}

protocol _AnyAGValueStorage: AnyObject {
    var anyValue: Any { get }
    var rawPointer: UnsafeRawPointer { get }

    func publishValue(to graph: _AGGraph, for attribute: AGAttribute)

    func updateErasedValue(
        _ value: Any,
        valuesEqual: (UnsafeRawPointer, UnsafeRawPointer) -> Bool
    ) -> _AGValueStorageUpdateResult
}

enum _AGValueStorageUpdateResult {
    case unchanged
    case changed
    case typeMismatch
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

    /// Exposes initialized storage to narrowly-scoped graph bookkeeping paths.
    var mutablePointer: UnsafeMutablePointer<Value> {
        storage
    }

    var rawPointer: UnsafeRawPointer {
        UnsafeRawPointer(storage)
    }

    func updateErasedValue(
        _ value: Any,
        valuesEqual: (UnsafeRawPointer, UnsafeRawPointer) -> Bool
    ) -> _AGValueStorageUpdateResult {
        guard let value = value as? Value else {
            return .typeMismatch
        }
        return withUnsafePointer(to: value) { proposedValue in
            if valuesEqual(rawPointer, UnsafeRawPointer(proposedValue)) {
                return .unchanged
            }
            storage.pointee = value
            return .changed
        }
    }

    var anyValue: Any {
        storage.pointee
    }

    func publishValue(to graph: _AGGraph, for attribute: AGAttribute) {
        graph.publishComputedValue(storage.pointee, for: attribute)
    }
}

private enum _AGComparisonLayout {
    private static let cache = Mutex<
        [ObjectIdentifier: _AGPreparedComparisonProgram]
    >([:])

    // The completed program is immutable and keyed by concrete type metadata.
    // Runtime field discovery therefore occurs once per participating type.
    static func program(
        of type: Any.Type,
        kind: _MetadataKind
    ) -> _AGPreparedComparisonProgram {
        let identifier = ObjectIdentifier(type)
        if let cached = cache.withLock({ $0[identifier] }) {
            return cached
        }

        var operations: [_AGPreparedComparisonOperation] = []
        appendOperations(
            of: type,
            kind: kind,
            isStrong: true,
            at: 0,
            to: &operations
        )
        let program = _AGPreparedComparisonProgram(operations: operations)
        return cache.withLock { cache in
            if let cached = cache[identifier] {
                return cached
            }
            cache[identifier] = program
            return program
        }
    }

    private static func appendOperations(
        of type: Any.Type,
        kind: _MetadataKind,
        isStrong: Bool,
        at offset: Int,
        to operations: inout [_AGPreparedComparisonOperation]
    ) {
        guard isStrong else {
            appendBytes(
                offset: offset,
                count: _AGGraph.valueSize(of: type),
                to: &operations
            )
            return
        }
        if type == String.self {
            operations.append(.string(offset: offset))
            return
        }
        if let descriptorEquality = type
            as? any _AGTypeDescriptorEquatable.Type {
            operations.append(
                .registeredEquality(
                    offset: offset,
                    type: descriptorEquality
                )
            )
            return
        }
        if type is AnyClass {
            appendBytes(
                offset: offset,
                count: _AGGraph.valueSize(of: type),
                to: &operations
            )
            return
        }
        if _isErrorExistentialContainer(type, kind: kind) {
            operations.append(.alwaysUnequal(offset: offset))
            return
        }
        if _isOpaqueExistentialContainer(type, kind: kind) {
            operations.append(
                .opaqueExistential(offset: offset, type: type)
            )
            return
        }
        if kind == .enum || kind == .optional {
            if let layout = _AGPreparedEnumLayout(type) {
                operations.append(.enumValue(offset: offset, layout: layout))
            } else {
                appendBytes(
                    offset: offset,
                    count: _AGGraph.valueSize(of: type),
                    to: &operations
                )
            }
            return
        }
        guard kind.supportsStoredFieldTraversal else {
            appendBytes(
                offset: offset,
                count: _AGGraph.valueSize(of: type),
                to: &operations
            )
            return
        }

        var fields: [(
            offset: Int,
            type: Any.Type,
            metadata: _EachFieldMetadata
        )] = []
        _forEachFieldWithMetadata(of: type) {
            _, fieldOffset, fieldType, metadata in
            fields.append((fieldOffset, fieldType, metadata))
            return true
        }
        guard !fields.isEmpty else {
            appendBytes(
                offset: offset,
                count: _AGGraph.valueSize(of: type),
                to: &operations
            )
            return
        }

        for field in fields {
            if field.metadata.isStrong {
                let fieldProgram = program(
                    of: field.type,
                    kind: field.metadata.kind
                )
                for operation in fieldProgram.operations {
                    append(
                        operation.offset(by: offset + field.offset),
                        to: &operations
                    )
                }
            } else {
                appendBytes(
                    offset: offset + field.offset,
                    count: _AGGraph.valueSize(of: field.type),
                    to: &operations
                )
            }
        }
    }

    private static func appendBytes(
        offset: Int,
        count: Int,
        to operations: inout [_AGPreparedComparisonOperation]
    ) {
        guard count > 0 else { return }
        append(.bytes(offset: offset, count: count), to: &operations)
    }

    private static func append(
        _ operation: _AGPreparedComparisonOperation,
        to operations: inout [_AGPreparedComparisonOperation]
    ) {
        if case let .bytes(offset, count) = operation,
           case let .bytes(previousOffset, previousCount)? = operations.last,
           previousOffset + previousCount == offset {
            operations[operations.count - 1] = .bytes(
                offset: previousOffset,
                count: previousCount + count
            )
        } else {
            operations.append(operation)
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
                if options.comparisonMode.rawValue
                    <= AGComparisonMode.layout.rawValue,
                   let descriptorEquality = Value.self
                    as? any _AGTypeDescriptorEquatable.Type {
                    return descriptorEquality._agTypeDescriptorValuesEqual(
                        lhsPointer,
                        rhsPointer
                    )
                }
                return compareStoredValues(
                    lhsPointer,
                    rhsPointer,
                    options: options
                )
            }
        }
    }

    static func compareStoredValues<Value>(
        _ lhs: UnsafePointer<Value>,
        _ rhs: UnsafePointer<Value>,
        options: AGComparisonOptions
    ) -> Bool {
        storedValueComparator(for: Value.self, options: options)(lhs, rhs)
    }

    static func storedValueComparator<Value>(
        for type: Value.Type,
        options: AGComparisonOptions
    ) -> (UnsafeRawPointer, UnsafeRawPointer) -> Bool {
        if type == String.self {
            return { lhs, rhs in
                lhs.assumingMemoryBound(to: String.self).pointee
                    == rhs.assumingMemoryBound(to: String.self).pointee
            }
        }
        if options.comparisonMode.rawValue <= AGComparisonMode.layout.rawValue {
            let program = _AGComparisonLayout.program(
                of: type,
                kind: _MetadataKind(type)
            )
            return { lhs, rhs in
                comparePreparedLayoutValues(lhs, rhs, program: program)
            }
        }
        let count = valueSize(of: type)
        return { lhs, rhs in
            compareRawRange(lhs, rhs, offset: 0, count: count)
        }
    }

    private static func comparePreparedLayoutValues(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        program: _AGPreparedComparisonProgram
    ) -> Bool {
        if lhs == rhs {
            return true
        }
        for operation in program.operations {
            let isEqual: Bool
            switch operation {
            case let .bytes(offset, count):
                isEqual = compareRawRange(
                    lhs,
                    rhs,
                    offset: offset,
                    count: count
                )
            case let .string(offset):
                isEqual = lhs.advanced(by: offset)
                    .assumingMemoryBound(to: String.self).pointee
                    == rhs.advanced(by: offset)
                    .assumingMemoryBound(to: String.self).pointee
            case let .registeredEquality(offset, type):
                isEqual = type._agTypeDescriptorValuesEqual(
                    lhs.advanced(by: offset),
                    rhs.advanced(by: offset)
                )
            case let .enumValue(offset, layout):
                isEqual = compareEnumValues(
                    lhs.advanced(by: offset),
                    rhs.advanced(by: offset),
                    layout: layout
                )
            case let .opaqueExistential(offset, type):
                isEqual = compareOpaqueExistentialValues(
                    lhs.advanced(by: offset),
                    rhs.advanced(by: offset),
                    type: type
                )
            case .alwaysUnequal:
                isEqual = false
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
        layout: _AGPreparedEnumLayout
    ) -> Bool {
        let lhsTag = layout.witnesses.tag(of: lhs)
        guard lhsTag == layout.witnesses.tag(of: rhs) else {
            return false
        }
        guard Int(lhsTag) < layout.cases.count else {
            return false
        }
        let activeCase = layout.cases[Int(lhsTag)]
        guard let payloadType = activeCase.payloadType else {
            return true
        }
        if activeCase.isIndirect {
            return compareIndirectEnumPayloads(
                lhs,
                rhs,
                payloadType: payloadType,
                witnesses: layout.witnesses
            )
        }
        return compareDirectEnumPayloads(
            lhs,
            rhs,
            tag: lhsTag,
            payloadType: payloadType,
            witnesses: layout.witnesses
        )
    }

    private static func compareDirectEnumPayloads(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        tag: UInt32,
        payloadType: Any.Type,
        witnesses: _EnumValueWitnesses
    ) -> Bool {
        withEnumScratch(witnesses: witnesses) { lhsScratch, rhsScratch in
            witnesses.initializeWithCopy(lhsScratch, from: lhs)
            witnesses.initializeWithCopy(rhsScratch, from: rhs)
            witnesses.projectEnumData(lhsScratch)
            witnesses.projectEnumData(rhsScratch)
            defer {
                witnesses.injectEnumTag(tag, into: lhsScratch)
                witnesses.injectEnumTag(tag, into: rhsScratch)
                witnesses.destroy(lhsScratch)
                witnesses.destroy(rhsScratch)
            }

            return comparePreparedLayoutValues(
                lhsScratch,
                rhsScratch,
                program: _AGComparisonLayout.program(
                    of: payloadType,
                    kind: _MetadataKind(payloadType)
                )
            )
        }
    }

    private static func compareIndirectEnumPayloads(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        payloadType: Any.Type,
        witnesses: _EnumValueWitnesses
    ) -> Bool {
        withEnumScratch(witnesses: witnesses) { lhsScratch, rhsScratch in
            lhsScratch.copyMemory(from: lhs, byteCount: witnesses.size)
            rhsScratch.copyMemory(from: rhs, byteCount: witnesses.size)
            witnesses.projectEnumData(lhsScratch)
            witnesses.projectEnumData(rhsScratch)

            let lhsBox = lhsScratch.load(as: UnsafeRawPointer.self)
            let rhsBox = rhsScratch.load(as: UnsafeRawPointer.self)
            if lhsBox == rhsBox {
                return true
            }
            let payloadLayout = valueLayout(of: payloadType)
            let alignmentMask = payloadLayout.alignment - 1
            let headerSize = 2 * MemoryLayout<UInt>.size
            let payloadOffset =
                (headerSize + alignmentMask) & ~alignmentMask
            return comparePreparedLayoutValues(
                lhsBox.advanced(by: payloadOffset),
                rhsBox.advanced(by: payloadOffset),
                program: _AGComparisonLayout.program(
                    of: payloadType,
                    kind: _MetadataKind(payloadType)
                )
            )
        }
    }

    private static func withEnumScratch<Result>(
        witnesses: _EnumValueWitnesses,
        _ body: (
            UnsafeMutableRawPointer,
            UnsafeMutableRawPointer
        ) throws -> Result
    ) rethrows -> Result {
        let alignmentMask = witnesses.alignment - 1
        let valueStride =
            (max(witnesses.size, 1) + alignmentMask) & ~alignmentMask
        return try withUnsafeTemporaryAllocation(
            byteCount: 2 * valueStride,
            alignment: witnesses.alignment
        ) { storage in
            let lhs = storage.baseAddress!
            return try body(lhs, lhs.advanced(by: valueStride))
        }
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
        let isInline = isValueInlineInExistentialContainer(dynamicType)
        guard
            let lhsValue = projectExistentialValue(
                lhs,
                isInline: isInline,
                alignment: layout.alignment
            ),
            let rhsValue = projectExistentialValue(
                rhs,
                isInline: isInline,
                alignment: layout.alignment
            )
        else {
            return false
        }
        return comparePreparedLayoutValues(
            lhsValue,
            rhsValue,
            program: _AGComparisonLayout.program(
                of: dynamicType,
                kind: _MetadataKind(dynamicType)
            )
        )
    }

    private static func isValueInlineInExistentialContainer(
        _ type: Any.Type
    ) -> Bool {
        func isInline<Value>(_ type: Value.Type) -> Bool {
            _isBitwiseTakable(type)
                && MemoryLayout<Value>.size <= 3 * MemoryLayout<UInt>.size
                && MemoryLayout<Value>.alignment <= MemoryLayout<UInt>.alignment
        }
        return _openExistential(type, do: isInline)
    }

    private static func projectExistentialValue(
        _ container: UnsafeRawPointer,
        isInline: Bool,
        alignment: Int
    ) -> UnsafeRawPointer? {
        if isInline {
            return container
        }
        guard let box = container.load(as: UnsafeRawPointer?.self) else {
            return nil
        }

        // Out-of-line existential storage starts with the two-word heap object
        // header. The value begins at the next address satisfying its runtime
        // alignment.
        let alignmentMask = alignment - 1
        let headerSize = 2 * MemoryLayout<UInt>.size
        let valueOffset = (headerSize + alignmentMask) & ~alignmentMask
        return box.advanced(by: valueOffset)
    }

    private static func compareRawRange(
        _ lhs: UnsafeRawPointer,
        _ rhs: UnsafeRawPointer,
        offset: Int,
        count: Int
    ) -> Bool {
        guard count > 0 else { return true }
        let lhsBytes = lhs.advanced(by: offset)
        let rhsBytes = rhs.advanced(by: offset)
        if count == 1 {
            return lhsBytes.load(as: UInt8.self)
                == rhsBytes.load(as: UInt8.self)
        }
        return memcmp(lhsBytes, rhsBytes, count) == 0
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
