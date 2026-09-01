//
//  File: FocusedValues.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol FocusedValueKey {
    associatedtype Value
}

struct FocusedValueScope: Equatable {
    var id: ViewIdentity
    var name: String

    static let scene = FocusedValueScope(
        id: ViewIdentity(),
        name: "Scene"
    )

    static let view = FocusedValueScope(
        id: ViewIdentity(),
        name: "View"
    )
}

public struct FocusedValues {
    struct StorageOptions: OptionSet {
        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let inFocusedViewHierarchy = StorageOptions(rawValue: 1 << 0)
        static let scene = StorageOptions(rawValue: 1 << 1)
    }

    struct Entry<Key: FocusedValueKey> {
        var scope: FocusedValueScope
        var value: Key.Value
        var inFocusedViewHierarchy: Bool
        var depth: Int
    }

    var plist = PropertyList()
    var storageOptions = StorageOptions()
    var navigationDepth = 0
    var version = DisplayList.Version()

    @usableFromInline
    init() {}

    public subscript<Key>(key: Key.Type) -> Key.Value?
    where Key: FocusedValueKey {
        get {
            var resolved: Entry<Key>?
            var sceneDepth = Int.min
            plist.forEachValue(
                forKey: FocusedValuePropertyKey<Key>.self
            ) { entry, _ in
                guard let entry else { return }
                if entry.scope == .scene {
                    guard entry.depth > sceneDepth else { return }
                    resolved = entry
                    sceneDepth = entry.depth
                } else if entry.scope == .view,
                          entry.inFocusedViewHierarchy {
                    resolved = entry
                }
            }
            return resolved?.value
        }
        set {
            let isScene = storageOptions.contains(.scene)
            let entry = newValue.map {
                Entry<Key>(
                    scope: isScene ? .scene : .view,
                    value: $0,
                    inFocusedViewHierarchy: storageOptions.contains(
                        .inFocusedViewHierarchy
                    ),
                    depth: isScene ? navigationDepth : -1
                )
            }
            plist.setValue(entry, forKey: FocusedValuePropertyKey<Key>.self)
        }
    }

    // Values supplied by the active presentation context shadow matching
    // root keys while leaving unrelated root keys available.
    mutating func override(with other: FocusedValues) {
        var combined = other.plist
        combined.merge(plist)
        plist = combined
        storageOptions.formUnion(other.storageOptions)
        navigationDepth = max(navigationDepth, other.navigationDepth)
        version.combine(with: other.version)
    }

    init(resolving list: FocusedValueList) {
        version = list.version
        for item in list.items {
            item.update(&self)
        }
    }
}

private struct FocusedValuePropertyKey<Key: FocusedValueKey>: PropertyKey {
    static var defaultValue: FocusedValues.Entry<Key>? { nil }

    // Focus entries can contain arbitrary values. Their display-list version
    // is the invalidation identity; individual entries are always recorded.
    static func valuesEqual(
        _ lhs: FocusedValues.Entry<Key>?,
        _ rhs: FocusedValues.Entry<Key>?
    ) -> Bool {
        false
    }
}

struct FocusedValueList {
    struct Item {
        var version: DisplayList.Version
        var isFocused: Bool
        var update: (inout FocusedValues) -> Void
    }

    struct Key: HostPreferenceKey {
        nonisolated(unsafe) static let defaultValue = FocusedValueList()

        static func reduce(
            value: inout FocusedValueList,
            nextValue: () -> FocusedValueList
        ) {
            value.items.append(contentsOf: nextValue().items)
        }
    }

    var items: [Item] = []

    var version: DisplayList.Version {
        var version = DisplayList.Version()
        for item in items {
            version.combine(with: item.version)
        }
        return version
    }
}

struct FocusedValueNavigationDepthInputKey: ViewInput {
    static var defaultValue: Attribute<Int> {
        Attribute(type: Int.self)
    }

    static func valuesEqual(
        _ lhs: Attribute<Int>,
        _ rhs: Attribute<Int>
    ) -> Bool {
        lhs == rhs
    }
}

struct FocusedValuesInputKey: ViewInput {
    static var defaultValue: OptionalAttribute<FocusedValues> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<FocusedValues>,
        _ rhs: OptionalAttribute<FocusedValues>
    ) -> Bool {
        lhs == rhs
    }
}

@propertyWrapper public struct FocusedValue<Value>: DynamicProperty {
    @usableFromInline
    enum Content {
        case keyPath(KeyPath<FocusedValues, Value?>)
        case value(Value?)
    }

    @usableFromInline
    var content: Content

    public init(_ keyPath: KeyPath<FocusedValues, Value?>) {
        content = .keyPath(keyPath)
    }

    @inlinable public var wrappedValue: Value? {
        if case let .value(value) = content {
            return value
        }
        return nil
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let box = FocusedValueBox<Value>(
            _focusedValues: inputs[FocusedValuesInputKey.self]
        )
        buffer.append(box, fieldOffset: fieldOffset)
    }
}

@propertyWrapper public struct FocusedBinding<Value>: DynamicProperty {
    @usableFromInline
    enum Content {
        case keyPath(KeyPath<FocusedValues, Binding<Value>?>)
        case value(Binding<Value>?)
    }

    @usableFromInline
    var content: Content

    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) {
        content = .keyPath(keyPath)
    }

    @inlinable public var wrappedValue: Value? {
        get {
            if case let .value(value) = content {
                return value?.wrappedValue
            }
            return nil
        }
        nonmutating set {
            if case let .value(value) = content, let newValue {
                value?.wrappedValue = newValue
            }
        }
    }

    public var projectedValue: Binding<Value?> {
        if case let .value(value) = content, let value {
            return Binding(value)
        }
        return .constant(nil)
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        let box = FocusedValueBox<Binding<Value>>(
            _focusedValues: inputs[FocusedValuesInputKey.self]
        )
        buffer.append(
            box,
            fieldOffset: fieldOffset,
            propertyType: Self.self
        ) { box, property, phase in
            box.update(property: &property, phase: phase)
        }
    }
}

private struct FocusedValueBox<Value>: DynamicPropertyBox {
    var _focusedValues: OptionalAttribute<FocusedValues>
    var keyPath: KeyPath<FocusedValues, Value?>?
    var value: Value?

    init(_focusedValues: OptionalAttribute<FocusedValues>) {
        self._focusedValues = _focusedValues
    }

    mutating func reset() {
        keyPath = nil
        value = nil
    }

    mutating func update(
        property: inout FocusedValue<Value>,
        phase: _GraphInputs.Phase
    ) -> Bool {
        if case let .keyPath(propertyKeyPath) = property.content {
            keyPath = propertyKeyPath
        }
        guard let keyPath else {
            property.content = .value(nil)
            value = nil
            return true
        }

        value = _focusedValues.attribute?.value[keyPath: keyPath]
        property.content = .value(value)
        return true
    }

    mutating func update<Wrapped>(
        property: inout FocusedBinding<Wrapped>,
        phase: _GraphInputs.Phase
    ) -> Bool where Value == Binding<Wrapped> {
        if case let .keyPath(propertyKeyPath) = property.content {
            keyPath = propertyKeyPath
        }
        guard let keyPath else {
            property.content = .value(nil)
            value = nil
            return true
        }

        value = _focusedValues.attribute?.value[keyPath: keyPath]
        property.content = .value(value)
        return true
    }

    func getState<T>(type: T.Type) -> Binding<T>? {
        nil
    }
}

@available(*, unavailable)
extension FocusedValue: Sendable {
}

@available(*, unavailable)
extension FocusedValue.Content: Sendable {
}

@available(*, unavailable)
extension FocusedBinding: Sendable {
}

@available(*, unavailable)
extension FocusedBinding.Content: Sendable {
}

@available(*, unavailable)
extension FocusedValues: Sendable {
}

extension FocusedValues: Equatable {
    public static func == (lhs: FocusedValues, rhs: FocusedValues) -> Bool {
        lhs.version == rhs.version
    }
}
