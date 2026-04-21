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
    // Controls whether environment dependencies are tracked by the resolved modifier.
    static var _tracksEnvironmentDependencies: Bool { get }
}

extension EnvironmentalModifier {
    // Process each DynamicProperty field before creating the resolve(in:) AG rule,
    // ensuring that properties such as @Namespace are initialized first.
    // liveModifierAttr wraps modifier._attribute in a rule that applies DynamicProperty
    // update closures. The MutableBox<Namespace.Box> captured in each closure retains
    // the allocated ID across re-evaluations.
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let envAttr = inputs.base.cachedEnvironment.value.environment

        var graphInputs = inputs.base
        var buffer = _DynamicPropertyBuffer()
        _forEachField(of: Self.self) { _, offset, fieldType in
            if let dpType = fieldType as? any DynamicProperty.Type {
                dpType._makeProperty(in: &buffer, container: modifier,
                                     fieldOffset: offset, inputs: &graphInputs)
            }
            return true
        }

        let liveModifierAttr: Attribute<Self>
        if buffer.contexts.isEmpty {
            liveModifierAttr = modifier._attribute
        } else {
            let capturedContexts = buffer.contexts
            liveModifierAttr = graph.makeRule {
                var m = modifier._attribute.value
                withUnsafeMutableBytes(of: &m) { rawBytes in
                    guard let base = rawBytes.baseAddress else { return }
                    for (offset, anyCtx) in capturedContexts {
                        if let ctx = anyCtx as? (UnsafeMutableRawPointer) -> Void {
                            ctx(base.advanced(by: offset))
                        }
                    }
                }
                return m
            }
        }

        let resolvedAttr: Attribute<ResolvedModifier> = graph.makeRule {
            let m = liveModifierAttr.value
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

        var graphInputs = inputs.base
        var buffer = _DynamicPropertyBuffer()
        _forEachField(of: Self.self) { _, offset, fieldType in
            if let dpType = fieldType as? any DynamicProperty.Type {
                dpType._makeProperty(in: &buffer, container: modifier,
                                     fieldOffset: offset, inputs: &graphInputs)
            }
            return true
        }

        let liveModifierAttr: Attribute<Self>
        if buffer.contexts.isEmpty {
            liveModifierAttr = modifier._attribute
        } else {
            let capturedContexts = buffer.contexts
            liveModifierAttr = graph.makeRule {
                var m = modifier._attribute.value
                withUnsafeMutableBytes(of: &m) { rawBytes in
                    guard let base = rawBytes.baseAddress else { return }
                    for (offset, anyCtx) in capturedContexts {
                        if let ctx = anyCtx as? (UnsafeMutableRawPointer) -> Void {
                            ctx(base.advanced(by: offset))
                        }
                    }
                }
                return m
            }
        }

        let resolvedAttr: Attribute<ResolvedModifier> = graph.makeRule {
            let m = liveModifierAttr.value
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
    public static var _tracksEnvironmentDependencies: Bool { true }
}
