//
//  File: EnvironmentKeyTransformModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct _EnvironmentKeyTransformModifier<Value>: ViewModifier, _GraphInputsModifier {
    public typealias Body = Never

    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public let transform: (inout Value) -> Void

    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        let parentEnvAttr = inputs.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value   // dep: transform closure changes
            var env = parentEnvAttr.value.trackingCopy() // dep: parent environment changes
            m.transform(&env[keyPath: m.keyPath])
            return env
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(newEnvAttr)
        )
    }
}

private extension CachedEnvironment.ID {
    static let isEnabled = CachedEnvironment.ID(base: UniqueID())
}

extension _ViewInputs {
    var isEnabled: Attribute<Bool> {
        base.cachedEnvironment.value.attribute(id: .isEnabled) {
            $0.isEnabled
        }
    }
}

extension View {
    @inlinable nonisolated public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }

    @inlinable nonisolated public func disabled(_ disabled: Bool) -> some View {
        return modifier(_EnvironmentKeyTransformModifier(
            keyPath: \.isEnabled,
            transform: { $0 = $0 && !disabled }
        ))
    }
}
