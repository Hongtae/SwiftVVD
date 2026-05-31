//
//  File: Namespace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Namespace stores an integer ID. A zero value means no persistent ID has been
// installed by the dynamic-property box yet.

/// A dynamic property that provides a namespace for matched-geometry effects and sheet identification.
@propertyWrapper
public struct Namespace: DynamicProperty, Sendable {
    @usableFromInline
    var id: Int

    @inlinable
    public init() { id = 0 }

    // Registers the namespace box. The container and inputs are intentionally unused.
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        buffer.append(Box(), fieldOffset: fieldOffset)
    }

    // Nonzero IDs use the stored value. A zero ID returns an ephemeral allocation
    // without mutating self, so reads outside the update pass still get a token.
    public var wrappedValue: Namespace.ID {
        if id != 0 { return ID(id: id) }
        return ID(id: Namespace._allocateID())
    }

    public struct ID: Hashable, Sendable, BitwiseCopyable {
        // Exposed for inlinable namespace consumers.
        @usableFromInline
        var id: Int

        @inlinable
        init(id: Int) { self.id = id }
    }
}

extension Namespace: BitwiseCopyable {}

// MARK: - Namespace.Box

extension Namespace {
    // Dynamic-property storage for Namespace. The box owns the persistent ID
    // and writes it back into the property during update.
    struct Box: DynamicPropertyBox {
        typealias Property = Namespace

        var id: Int = 0

        // Reset drops the persistent ID; the next update allocates again.
        mutating func reset() { id = 0 }

        // Allocates on first update and ignores phase.
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
    // Namespace IDs use AttributeGraph's process-wide unique-ID allocator.
    static func _allocateID() -> Int {
        AGMakeUniqueID()
    }
}
