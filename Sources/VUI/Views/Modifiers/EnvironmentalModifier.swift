//
//  File: EnvironmentalModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol EnvironmentalModifier: ViewModifier where Self.Body == Never {
    associatedtype ResolvedModifier: ViewModifier
    func resolve(in environment: EnvironmentValues) -> Self.ResolvedModifier

    static var _requiresMainThread: Bool { get }
}

extension EnvironmentalModifier {
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let envAttr = inputs.base.cachedEnvironment.value.environment
        let resolvedAttr: Attribute<ResolvedModifier> = graph.makeRule {
            let m = modifier._attribute.value
            let env = envAttr.value
            return m.resolve(in: env)
        }
        return ResolvedModifier._makeView(
            modifier: _GraphValue(_attribute: resolvedAttr),
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let envAttr = inputs.base.cachedEnvironment.value.environment
        let resolvedAttr: Attribute<ResolvedModifier> = graph.makeRule {
            let m = modifier._attribute.value
            let env = envAttr.value
            return m.resolve(in: env)
        }
        return ResolvedModifier._makeViewList(
            modifier: _GraphValue(_attribute: resolvedAttr),
            inputs: inputs,
            body: body
        )
    }

    public static var _requiresMainThread: Bool { false }
}
