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

    // TODO: allocate a stable unique ID through the dynamic property pipeline.
    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        fatalError("Namespace._makeProperty: unique ID allocation is not implemented")
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

        public static func == (a: ID, b: ID) -> Bool { a.id == b.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public var hashValue: Int { id }
    }
}
