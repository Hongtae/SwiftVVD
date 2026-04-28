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
    static var _tracksEnvironmentDependencies: Bool { get }
}

extension EnvironmentalModifier {
    // Resolve the modifier after dynamic-property processing so environment-backed
    // fields are current before the resolved modifier builds its view.
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (resolvedGV, _) = EnvironmentalBodyAccessor<Self>.makeBody(
            container: modifier, inputs: &graphInputs, fields: dpFields)
        return ResolvedModifier._makeView(modifier: resolvedGV, inputs: inputs, body: body)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (resolvedGV, _) = EnvironmentalBodyAccessor<Self>.makeBody(
            container: modifier, inputs: &graphInputs, fields: dpFields)
        return ResolvedModifier._makeViewList(modifier: resolvedGV, inputs: inputs, body: body)
    }

    public static var _requiresMainThread: Bool { false }
    public static var _tracksEnvironmentDependencies: Bool { true }
}
