//
//  File: Namespace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// A dynamic property that provides a namespace for matched-geometry effects and sheet identification.
@propertyWrapper
public struct Namespace: DynamicProperty, Sendable {
    @usableFromInline
    var id: Int

    @inlinable
    public init() { id = 0 }

    // _makeProperty stores a Box for this Namespace field.
    // container and inputs are currently unused.
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        buffer.append(Box(), fieldOffset: fieldOffset)
    }

    public var wrappedValue: Namespace.ID {
        ID(id: id)
    }

    public struct ID: Hashable, Sendable, BitwiseCopyable {
        // Stored namespace identifier.
        @usableFromInline
        var id: Int

        @inlinable
        init(id: Int) { self.id = id }
    }
}

extension Namespace: BitwiseCopyable {}

// MARK: - Namespace.Box

extension Namespace {
    // Backing box for Namespace dynamic property storage.
    // reset(): id = 0.
    // update(property:phase:): allocates a global ID on first update and writes it to property.id.
    struct Box: DynamicPropertyBox {
        typealias Property = Namespace

        var id: Int = 0

        mutating func reset() { id = 0 }

        // phase is currently unused.
        mutating func update(property: inout Namespace, phase: Phase) -> Bool {
            let changed = (id == 0)
            if changed { id = Namespace._allocateID() }
            property.id = id
            return changed
        }

        func getState<T>(type: T.Type) -> Binding<T>? { nil }
    }
}

// MARK: - ID allocation

extension Namespace {
    // Allocates a process-wide unique namespace ID.
    static func _allocateID() -> Int {
        AGMakeUniqueID()
    }
}
