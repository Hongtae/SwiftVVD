//
//  File: ContainerValues.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// ContainerValueKey is the protocol for keys into ContainerValues.
public protocol ContainerValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct ContainerValues {
    var base: ViewTraitCollection

    init(base: ViewTraitCollection = ViewTraitCollection()) {
        self.base = base
    }

    public subscript<Key: ContainerValueKey>(key: Key.Type) -> Key.Value {
        get {
            base[ContainerValueViewTraitKey<Key>.self]
        }
        set {
            base[ContainerValueViewTraitKey<Key>.self] = newValue
        }
    }
}

private struct ContainerValueViewTraitKey<Key>: _ViewTraitKey
    where Key: ContainerValueKey {
    static var defaultValue: Key.Value {
        Key.defaultValue
    }
}

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

    private struct AddTrait: Rule {
        var _modifier: Attribute<_ContainerValueWritingModifier>
        var _traits: OptionalAttribute<ViewTraitCollection>

        var value: ViewTraitCollection {
            var values = ContainerValues(
                base: _traits.value ?? ViewTraitCollection()
            )
            let modifier = _modifier.value
            values[keyPath: modifier.keyPath] = modifier.value
            return values.base
        }
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeViewList called outside an active _AGGraph context."
            )
        }
        let traits: Attribute<ViewTraitCollection> = graph.makeRule(
            AddTrait(
                _modifier: modifier._attribute,
                _traits: inputs._traits
            )
        )
        var modifiedInputs = inputs
        modifiedInputs._traits = OptionalAttribute(traits)
        return body(_Graph(), modifiedInputs)
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
