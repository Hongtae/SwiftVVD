//
//  File: BodyAccessor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// MARK: - Thread flag types
// The current renderer uses MainThreadFlags for body evaluation.
struct MainThreadFlags {}
struct AsyncThreadFlags {}

// MARK: - BodyAccessor
// Protocol adopted by ModifierBodyAccessor, ViewBodyAccessor, EnvironmentalBodyAccessor.
// Creates the body AG rule (DynamicBody or StaticBody) during _makeView setup,
// and drives body re-evaluation when the container value changes.
// updateBody returns Body so DynamicBody/StaticBody can publish it through AttributeGraph.
protocol BodyAccessor {
    associatedtype Container
    associatedtype Body

    // Used to read the container value inside DynamicBody.updateValue().
    var containerAttr: Attribute<Container> { get }

    static func makeBody(
        container: _GraphValue<Container>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<Body>, Optional<_DynamicPropertyBuffer>)

    // Returns the body value published by the StatefulRule.
    mutating func updateBody(of container: Container, changed: Bool) -> Body
}

// MARK: - DynamicBody
// StatefulRule that computes Body when the container has DynamicProperties.
// updateValue(): reads container (dep), applies DynamicProperty field updates, calls body.
struct DynamicBody<Accessor: BodyAccessor, Flags>: StatefulRule {
    typealias Value = Accessor.Body
    var accessor: Accessor
    var buffer: _DynamicPropertyBuffer

    mutating func updateValue() {
        var container = accessor.containerAttr.value  // registers AG dependency
        buffer.applyContexts(to: &container)
        let body = accessor.updateBody(of: container, changed: !buffer.isEmpty)
        AttributeGraph.setStatefulOutput(body)
    }
}

// MARK: - StaticBody
// StatefulRule for body when there are no DynamicProperties.
struct StaticBody<Accessor: BodyAccessor, Flags>: StatefulRule {
    typealias Value = Accessor.Body
    var accessor: Accessor

    mutating func updateValue() {
        let container = accessor.containerAttr.value  // registers AG dependency
        let body = accessor.updateBody(of: container, changed: false)
        AttributeGraph.setStatefulOutput(body)
    }
}

// MARK: - ModifierBodyAccessor
// BodyAccessor conformance for ViewModifier.body(content:).
struct ModifierBodyAccessor<M: ViewModifier>: BodyAccessor {
    typealias Container = M
    typealias Body = M.Body

    let containerAttr: Attribute<M>

    mutating func updateBody(of modifier: M, changed: Bool) -> M.Body {
        modifier.body(content: _ViewModifier_Content<M>())
    }

    static func makeBody(
        container: _GraphValue<M>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<M.Body>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = AttributeGraph.current else {
            fatalError("ModifierBodyAccessor.makeBody called outside AttributeGraph context")
        }
        let buffer = _DynamicPropertyBuffer(fields: fields, container: container, inputs: &inputs)
        let accessor = ModifierBodyAccessor(containerAttr: container._attribute)
        if buffer.isEmpty {
            let attr = graph.makeStatefulRule(StaticBody<ModifierBodyAccessor<M>, MainThreadFlags>(accessor: accessor))
            return (_GraphValue(_attribute: attr), nil)
        } else {
            let attr = graph.makeStatefulRule(DynamicBody<ModifierBodyAccessor<M>, MainThreadFlags>(accessor: accessor, buffer: buffer))
            return (_GraphValue(_attribute: attr), buffer)
        }
    }
}

// MARK: - EnvironmentalBodyAccessor
// BodyAccessor conformance for EnvironmentalModifier.resolve(in:).
// Unlike ModifierBodyAccessor, stores environmentAttr to read current EnvironmentValues
// during updateBody, which calls modifier.resolve(in: environment).
struct EnvironmentalBodyAccessor<E: EnvironmentalModifier>: BodyAccessor {
    typealias Container = E
    typealias Body = E.ResolvedModifier

    let containerAttr: Attribute<E>
    let environmentAttr: Attribute<EnvironmentValues>

    mutating func updateBody(of modifier: E, changed: Bool) -> E.ResolvedModifier {
        modifier.resolve(in: environmentAttr.value)
    }

    static func makeBody(
        container: _GraphValue<E>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<E.ResolvedModifier>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = AttributeGraph.current else {
            fatalError("EnvironmentalBodyAccessor.makeBody called outside AttributeGraph context")
        }
        let environmentAttr = inputs.cachedEnvironment.value.environment
        let buffer = _DynamicPropertyBuffer(fields: fields, container: container, inputs: &inputs)
        let accessor = EnvironmentalBodyAccessor(containerAttr: container._attribute,
                                                  environmentAttr: environmentAttr)
        if buffer.isEmpty {
            let attr = graph.makeStatefulRule(StaticBody<EnvironmentalBodyAccessor<E>, MainThreadFlags>(accessor: accessor))
            return (_GraphValue(_attribute: attr), nil)
        } else {
            let attr = graph.makeStatefulRule(DynamicBody<EnvironmentalBodyAccessor<E>, MainThreadFlags>(accessor: accessor, buffer: buffer))
            return (_GraphValue(_attribute: attr), buffer)
        }
    }
}

// MARK: - ViewBodyAccessor
// BodyAccessor conformance for View.body.
// View._makeView currently uses withObservationTracking directly.
// ViewBodyAccessor is reserved for a future body-access path.
struct ViewBodyAccessor<V: View>: BodyAccessor {
    typealias Container = V
    typealias Body = V.Body

    let containerAttr: Attribute<V>

    mutating func updateBody(of view: V, changed: Bool) -> V.Body {
        view.body
    }

    static func makeBody(
        container: _GraphValue<V>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<V.Body>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = AttributeGraph.current else {
            fatalError("ViewBodyAccessor.makeBody called outside AttributeGraph context")
        }
        let buffer = _DynamicPropertyBuffer(fields: fields, container: container, inputs: &inputs)
        let accessor = ViewBodyAccessor(containerAttr: container._attribute)
        if buffer.isEmpty {
            let attr = graph.makeStatefulRule(StaticBody<ViewBodyAccessor<V>, MainThreadFlags>(accessor: accessor))
            return (_GraphValue(_attribute: attr), nil)
        } else {
            let attr = graph.makeStatefulRule(DynamicBody<ViewBodyAccessor<V>, MainThreadFlags>(accessor: accessor, buffer: buffer))
            return (_GraphValue(_attribute: attr), buffer)
        }
    }
}
