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
    // EnvironmentalBodyAccessor<Self>.makeBody combines DynamicProperty
    // processing and resolve(in:) into a single DynamicBody/StaticBody AG rule.
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (resolvedGV, _) = EnvironmentalBodyAccessor<Self>.makeBody(
            container: modifier, inputs: &graphInputs, fields: dpFields)
        return ResolvedModifier._makeViewList(modifier: resolvedGV, inputs: inputs, body: body)
    }

    public static var _requiresMainThread: Bool { true }
    public static var _tracksEnvironmentDependencies: Bool { true }
}
