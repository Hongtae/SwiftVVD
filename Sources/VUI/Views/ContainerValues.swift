//
//  File: ContainerValues.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// ContainerValueKey — protocol for keys into ContainerValues.
public protocol ContainerValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

// ContainerValues — dictionary-like store for container-specific values
// attached to individual views inside variadic containers (List, Grid, etc.).
// Read via LayoutSubview.containerValues in Layout.placeSubviews.
public struct ContainerValues {
    var storage: [ObjectIdentifier: Any] = [:]

    public subscript<Key: ContainerValueKey>(key: Key.Type) -> Key.Value {
        get {
            storage[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }
}

// ContainerValuesInput — PropertyKey that carries ContainerValues
// through the customInputs stack. Written by _ContainerValueWritingModifier,
// read by containers (Layout, VariadicView) when collecting subview metadata.
struct ContainerValuesInput: PropertyKey {
    typealias Value = ContainerValues
    static var defaultValue: ContainerValues { ContainerValues() }
    static func valuesEqual(_ a: ContainerValues, _ b: ContainerValues) -> Bool { false }
    var description: String { "ContainerValuesInput" }
}

// _ContainerValueWritingModifier<Value> — ViewModifier that writes a single
// ContainerValues entry (identified by keyPath) into customInputs so that
// the enclosing container can read it via LayoutSubview.containerValues.
// Body=Never + custom _makeView/_makeViewList (pass-through with input mutation).
@frozen
public struct _ContainerValueWritingModifier<Value> {
    public var keyPath: WritableKeyPath<ContainerValues, Value>
    public var value: Value

    public init(keyPath: WritableKeyPath<ContainerValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }
}

extension _ContainerValueWritingModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        var cv = inputs.base.customInputs.value(forKey: ContainerValuesInput.self)
        cv[keyPath: modifier._attribute.value.keyPath] = modifier._attribute.value.value
        inputs.base.customInputs.setValue(cv, forKey: ContainerValuesInput.self)
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        var cv = inputs.base.customInputs.value(forKey: ContainerValuesInput.self)
        cv[keyPath: modifier._attribute.value.keyPath] = modifier._attribute.value.value
        inputs.base.customInputs.setValue(cv, forKey: ContainerValuesInput.self)
        return body(_Graph(), inputs)
    }
}

extension View {
    public func containerValue<V>(
        _ keyPath: WritableKeyPath<ContainerValues, V>,
        _ value: V
    ) -> some View {
        modifier(_ContainerValueWritingModifier(keyPath: keyPath, value: value))
    }
}
