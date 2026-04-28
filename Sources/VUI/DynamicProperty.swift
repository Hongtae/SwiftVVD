//
//  File: DynamicProperty.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Protocol for managing a DynamicProperty's backing storage in _DynamicPropertyBuffer.
///
/// Requirements:
///   reset() -> ()
///   update(property: inout Property, phase: Phase) -> Bool
///   getState<T>(type: T.Type) -> Binding<T>?
protocol DynamicPropertyBox {
    associatedtype Property: DynamicProperty
    mutating func reset()
    mutating func update(property: inout Property, phase: Phase) -> Bool
    func getState<T>(type: T.Type) -> Binding<T>?
}

public protocol DynamicProperty {
    static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs)
    mutating func update()
}

extension DynamicProperty {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs) {
        func make<T: DynamicProperty>(_ type: T.Type, offset: Int) {
            T._makeProperty(in: &buffer, container: container, fieldOffset: offset, inputs: &inputs)
        }
        _forEachField(of: self) { charPtr, offset, fieldType in
            if let propType = fieldType as? any DynamicProperty.Type {
                make(propType, offset: fieldOffset + offset)
            }
            return true
        }
        buffer.properties.append(.init(type: self, offset: fieldOffset))
    }

    public mutating func update() {
    }
}

public struct _DynamicPropertyBuffer {
    struct FieldInfo {
        let type: DynamicProperty.Type
        let offset: Int
    }
    var properties: [FieldInfo] = []
    var contexts: [Int: Any] = [:]

    var isEmpty: Bool { contexts.isEmpty }

    // Box instance is stored in contexts keyed by fieldOffset;
    // update closure writes back to the View struct field at that offset.
    mutating func append<T: DynamicPropertyBox>(_ box: T, fieldOffset: Int) {
        let boxRef = MutableBox(box)
        properties.append(.init(type: T.Property.self, offset: fieldOffset))
        contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            var property = ptr.assumingMemoryBound(to: T.Property.self).pointee
            _ = boxRef.value.update(property: &property, phase: Phase())
            ptr.assumingMemoryBound(to: T.Property.self).pointee = property
        }
    }

    // Calls addFields which loops over DynamicPropertyCache.Fields and calls _makeProperty per entry.
    init<T>(fields: DynamicPropertyCache.Fields, container: _GraphValue<T>, inputs: inout _GraphInputs) {
        for entry in fields.entries {
            entry.type._makeProperty(in: &self, container: container,
                                     fieldOffset: entry.offset, inputs: &inputs)
        }
    }

    // Applies stored update closures to the container's fields in-place.
    func applyContexts<T>(to container: inout T) {
        guard !contexts.isEmpty else { return }
        withUnsafeMutableBytes(of: &container) { rawBytes in
            guard let base = rawBytes.baseAddress else { return }
            for (offset, anyCtx) in contexts {
                if let fn = anyCtx as? (UnsafeMutableRawPointer) -> Void {
                    fn(base.advanced(by: offset))
                }
            }
        }
    }
}

func _hasDynamicProperty<V: View>(_ view: V.Type) -> Bool {
    let nonExist = _forEachField(of: view) { _, _, fieldType in
        if fieldType is DynamicProperty.Type {
            return false
        }
        return true
    }
    return nonExist == false
}

func _unsafeCastDynamicProperty<V: View, T: DynamicProperty>(to propertyType: T.Type, at offset: Int, from view: V) -> any DynamicProperty {
    var property: (any DynamicProperty)?
    withUnsafeBytes(of: view) {
        let ptr = $0.baseAddress!.advanced(by: offset)
        property = ptr.assumingMemoryBound(to: propertyType).pointee
    }
    if let property { return property }
    fatalError("Unable to find dynamic property at offset: \(offset)")
}

func _getDynamicProperty<V: View>(at offset: Int, from view: V) -> any DynamicProperty {
    func restore<T: DynamicProperty>(_ ptr: UnsafeRawPointer, _: T.Type) -> T {
        ptr.assumingMemoryBound(to: T.self).pointee
    }
    var property: (any DynamicProperty)?
    _forEachField(of: V.self) { charPtr, position, fieldType in
        if let propertyType = fieldType as? DynamicProperty.Type {
            if offset == position {
                withUnsafeBytes(of: view) {
                    let ptr = $0.baseAddress!.advanced(by: offset)
                    property = restore(ptr, propertyType)
                }
            }
        }
        return position < offset
    }
    if let property { return property }
    fatalError("Unable to find dynamic property at offset: \(offset)")
}
