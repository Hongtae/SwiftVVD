//
//  File: BodyAccessor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Thread flag marker types.
// DynamicProperty field flags distinguish main-thread and async body paths.
// The current body evaluation path uses MainThreadFlags.
struct MainThreadFlags {}
struct AsyncThreadFlags {}

// BodyAccessor
// Protocol adopted by ModifierBodyAccessor, ViewBodyAccessor, EnvironmentalBodyAccessor.
// Creates the body AG rule (DynamicBody or StaticBody) during _makeView setup,
// and drives body re-evaluation when the container value changes.
//
// Body values are published through DynamicBody/StaticBody.
protocol BodyAccessor {
    associatedtype Container
    associatedtype Body

    // Used to read the container value inside DynamicBody.updateValue().
    var containerAttr: Attribute<Container> { get }

    // Return value is published via _AGGraph.setStatefulOutput in StatefulRule.
    mutating func updateBody(of container: Container, changed: Bool) -> Body
}

// Category marker for the default View.body accessor path.
protocol DSLBodyAccessor: BodyAccessor {
}

// DynamicBody
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
        _AGGraph.setStatefulOutput(body)
    }
}

// StaticBody
// StatefulRule for body when there are no DynamicProperties.
struct StaticBody<Accessor: BodyAccessor, Flags>: StatefulRule {
    typealias Value = Accessor.Body
    var accessor: Accessor

    mutating func updateValue() {
        let container = accessor.containerAttr.value  // registers AG dependency
        let body = accessor.updateBody(of: container, changed: false)
        _AGGraph.setStatefulOutput(body)
    }
}

// ModifierBodyAccessor
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
        guard let graph = _AGGraph.current else {
            fatalError("ModifierBodyAccessor.makeBody called outside _AGGraph context")
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

// Evaluates a style body from the projected style field while retaining the
// owning modifier and styleable view. Dynamic properties are installed on the
// projected style value, then written back into a modifier copy before dispatch.
struct StyleBodyAccessor<V: StyleableView, S: StyleModifier>: BodyAccessor {
    typealias Container = S.Style
    typealias Body = S.StyleBody

    let _view: Attribute<V>
    let _styleModifier: Attribute<S>

    var containerAttr: Attribute<S.Style> {
        _styleModifier[offset: { modifier in
            PointerOffset.of(&modifier.style)
        }]
    }

    mutating func updateBody(
        of style: S.Style,
        changed: Bool
    ) -> S.StyleBody {
        var modifier = _styleModifier.value
        modifier.style = style
        let view = _view.value
        guard let configuration =
                view.configuration as? S.StyleConfiguration else {
            fatalError(
                "StyleBodyAccessor configuration type mismatch: " +
                "\(V.Configuration.self) vs " +
                "\(S.StyleConfiguration.self)"
            )
        }
        return modifier.styleBody(configuration: configuration)
    }

    static func makeBody(
        container: _GraphValue<S.Style>,
        view: _GraphValue<V>,
        styleModifier: Attribute<S>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<S.StyleBody>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "StyleBodyAccessor.makeBody called outside _AGGraph context"
            )
        }
        let buffer = _DynamicPropertyBuffer(
            fields: fields,
            container: container,
            inputs: &inputs
        )
        let accessor = StyleBodyAccessor(
            _view: view._attribute,
            _styleModifier: styleModifier
        )
        if buffer.isEmpty {
            let attr = graph.makeStatefulRule(
                StaticBody<StyleBodyAccessor<V, S>, MainThreadFlags>(
                    accessor: accessor
                )
            )
            return (_GraphValue(_attribute: attr), nil)
        } else {
            let attr = graph.makeStatefulRule(
                DynamicBody<StyleBodyAccessor<V, S>, MainThreadFlags>(
                    accessor: accessor,
                    buffer: buffer
                )
            )
            return (_GraphValue(_attribute: attr), buffer)
        }
    }
}

// EnvironmentalBodyAccessor
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
        guard let graph = _AGGraph.current else {
            fatalError("EnvironmentalBodyAccessor.makeBody called outside _AGGraph context")
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

// ViewBodyAccessor
// BodyAccessor conformance for View.body.
// View._makeView currently uses withObservationTracking directly.
// ViewBodyAccessor is kept for the alternate body access path.
struct ViewBodyAccessor<V: View>: DSLBodyAccessor {
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
        guard let graph = _AGGraph.current else {
            fatalError("ViewBodyAccessor.makeBody called outside _AGGraph context")
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
