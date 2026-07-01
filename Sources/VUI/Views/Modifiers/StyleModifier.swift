//
//  File: StyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// MARK: - AnyStyleModifierType

// Protocol for type-erased style dispatch.
// StyleModifierType<M: StyleModifier> conforms to this.
// Static methods: makeView, makeViewList, viewListCount.
protocol AnyStyleModifierType {
    static func makeView<V: StyleableView>(
        view: _GraphValue<V>, modifier: AnyStyleModifier, inputs: _ViewInputs
    ) -> _ViewOutputs
    static func makeViewList<V: StyleableView>(
        view: _GraphValue<V>, modifier: AnyStyleModifier, inputs: _ViewListInputs
    ) -> _ViewListOutputs
    static func viewListCount(inputs: _ViewListCountInputs) -> Int?
}

// MARK: - StyleModifier

// StyleModifier: protocol for modifier types wrapping a style.
// Requirements: var style, init(style:), styleBody(configuration:).
// ViewModifier conformance with Body == Never.
protocol StyleModifier: ViewModifier where Body == Never {
    associatedtype Style
    var style: Style { get set }
    init(style: Style)

    associatedtype StyleConfiguration
    associatedtype StyleBody: View
    func styleBody(configuration: StyleConfiguration) -> StyleBody
}

extension StyleModifier {
    // Default _makeView: push self onto StyleInput<StyleConfiguration> stack, then call body.
    static func _makeView(
        modifier: _GraphValue<Self>, inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let modAttr = modifier._attribute
        let styleAttr: Attribute<Self> = graph.makeRule { modAttr.value }
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<Self>.self)
        var newInputs = inputs
        var stack = newInputs.base.customInputs.value(
            forKey: StyleInput<Self.StyleConfiguration>.self)
        stack = .node(anyMod, stack)
        newInputs.base.customInputs.setValue(stack,
            forKey: StyleInput<Self.StyleConfiguration>.self)
        return body(_Graph(), newInputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>, inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let modAttr = modifier._attribute
        let styleAttr: Attribute<Self> = graph.makeRule { modAttr.value }
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<Self>.self)
        var newInputs = inputs
        var stack = newInputs.base.customInputs.value(
            forKey: StyleInput<Self.StyleConfiguration>.self)
        stack = .node(anyMod, stack)
        newInputs.base.customInputs.setValue(stack,
            forKey: StyleInput<Self.StyleConfiguration>.self)
        return body(_Graph(), newInputs)
    }
}

// MARK: - StyleModifierType

// StyleModifierType<M: StyleModifier>: AnyStyleModifierType
// Concrete dispatcher parameterized by the concrete StyleModifier type M.
// makeView uses AnyStyleModifier.value to read M from the AG node,
// then calls M.styleBody(configuration:) to build the view.
struct StyleModifierType<M: StyleModifier>: AnyStyleModifierType {
    static func makeView<V: StyleableView>(
        view: _GraphValue<V>, modifier: AnyStyleModifier, inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("StyleModifierType.makeView called outside AG context.")
        }
        let styleAttr = Attribute<M>(modifier.value)
        let bodyAttr = graph.makeRule {
            let v = view._attribute.value
            let m = styleAttr.value
            guard let config = v.configuration as? M.StyleConfiguration else {
                fatalError("StyleModifierType.makeView: configuration type mismatch: \(type(of: v.configuration)) vs \(M.StyleConfiguration.self)")
            }
            return m.styleBody(configuration: config)
        }
        return VUI.makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
    }

    static func makeViewList<V: StyleableView>(
        view: _GraphValue<V>, modifier: AnyStyleModifier, inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("StyleModifierType.makeViewList called outside AG context.")
        }
        let styleAttr = Attribute<M>(modifier.value)
        let bodyAttr = graph.makeRule {
            let v = view._attribute.value
            let m = styleAttr.value
            guard let config = v.configuration as? M.StyleConfiguration else {
                fatalError("StyleModifierType.makeViewList: configuration type mismatch")
            }
            return m.styleBody(configuration: config)
        }
        return M.StyleBody._makeViewList(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
    }

    static func viewListCount(inputs: _ViewListCountInputs) -> Int? { nil }
}

// MARK: - Style Modifier Wrappers

// AG node value wrappers stored in the attribute graph node pointed to
// by AnyStyleModifier.value.
// ButtonStyleModifier<S>: StyleModifier wrapper for PrimitiveButtonStyle.
struct ButtonStyleModifier<S: PrimitiveButtonStyle>: StyleModifier {
    typealias Body = Never
    typealias StyleConfiguration = PrimitiveButtonStyleConfiguration
    typealias StyleBody = S.Body

    var style: S

    init(style: S) { self.style = style }

    func styleBody(configuration: PrimitiveButtonStyleConfiguration) -> S.Body {
        style.makeBody(configuration: configuration)
    }
}

struct ToggleStyleModifier<S: ToggleStyle>: StyleModifier {
    typealias Body = Never
    typealias StyleConfiguration = ToggleStyleConfiguration
    typealias StyleBody = S.Body

    var style: S

    init(style: S) { self.style = style }

    func styleBody(configuration: ToggleStyleConfiguration) -> S.Body {
        style.makeBody(configuration: configuration)
    }
}

// LabelStyleModifier<S>: StyleModifier conformance is declared in LabelStyle.swift.

// MARK: - Wrapped Style Access

// Internal protocols for accessing the wrapped style value.
// Used by ResolvedButtonStyle._makeView and ResolvedLabelStyle._makeView
// (which extract style via existential dispatch before calling makeBody).
protocol _HasPrimStyle {
    func _primStyle() -> any PrimitiveButtonStyle
}
extension ButtonStyleModifier: _HasPrimStyle {
    func _primStyle() -> any PrimitiveButtonStyle { style }
}

protocol _HasLabelStyle {
    func _labelStyle() -> any LabelStyle
}

// Dispatch protocols. Conditional conformances of StyleModifierType allow
// the metatype stored in AnyStyleModifier._type to be cast to these and
// used for type-erased style extraction.
protocol _StyleModifierPrimDispatch {
    static func _primStyle(attrID: AGAttribute) -> any PrimitiveButtonStyle
}
extension StyleModifierType: _StyleModifierPrimDispatch where M: _HasPrimStyle {
    static func _primStyle(attrID: AGAttribute) -> any PrimitiveButtonStyle {
        Attribute<M>(attrID).value._primStyle()
    }
}

protocol _StyleModifierLabelDispatch {
    static func _labelStyle(attrID: AGAttribute) -> any LabelStyle
}
extension StyleModifierType: _StyleModifierLabelDispatch where M: _HasLabelStyle {
    static func _labelStyle(attrID: AGAttribute) -> any LabelStyle {
        Attribute<M>(attrID).value._labelStyle()
    }
}

// Note: LabelStyleModifier<S>: _HasLabelStyle conformance is in LabelStyle.swift.

// MARK: - AnyStyleModifier

// Type-erased style modifier.
//   value: AGAttribute points to the AG node storing the style.
//   _type: AnyStyleModifierType.Type is the metatype for dispatch.
struct AnyStyleModifier {
    let value: AGAttribute
    let _type: any AnyStyleModifierType.Type

    // Computed type-erased style extraction for _makeView paths.
    var primStyle: (any PrimitiveButtonStyle)? {
        (_type as? any _StyleModifierPrimDispatch.Type)?._primStyle(attrID: value)
    }
    var labelStyle: (any LabelStyle)? {
        (_type as? any _StyleModifierLabelDispatch.Type)?._labelStyle(attrID: value)
    }
}

// MARK: - StyleInput

// PropertyKey with Stack<AnyStyleModifier> value.
// PrimitiveButtonStyle uses StyleInput<PrimitiveButtonStyleConfiguration>.
// LabelStyle uses StyleInput<LabelStyleConfiguration>.
struct StyleInput<Configuration>: GraphInput {
    typealias Value = Stack<AnyStyleModifier>
    static var defaultValue: Stack<AnyStyleModifier> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    var description: String { "StyleInput<\(Configuration.self)>" }
}

// MARK: - StyleableView

// StyleableView: protocol for views resolved by the style system.
// Provides body.getter (used by StyleableView._makeView default impl)
// and configuration storage.
protocol StyleableView: View {
    associatedtype Configuration
    var configuration: Configuration { get }

    static var isScrapeable: Bool { get }

    associatedtype DefaultStyleModifier: StyleModifier
        where DefaultStyleModifier.StyleConfiguration == Configuration
    static var defaultStyleModifier: DefaultStyleModifier { get }
}

extension StyleableView {
    static var isScrapeable: Bool { false }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var stack = inputs.base.customInputs.value(forKey: StyleInput<Configuration>.self)
        if let head = stack.pop() {
            var poppedInputs = inputs
            poppedInputs.base.customInputs.setValue(stack, forKey: StyleInput<Configuration>.self)
            return head._type.makeView(view: view, modifier: head, inputs: poppedInputs)
        } else {
            guard !(Body.self is Never.Type) else {
                fatalError("\(Self.self) may not have Body == Never")
            }
            let bodyGV = view[\.body]
            return Body._makeView(view: bodyGV, inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var stack = inputs.base.customInputs.value(forKey: StyleInput<Configuration>.self)
        if let head = stack.pop() {
            var poppedInputs = inputs
            poppedInputs.base.customInputs.setValue(stack, forKey: StyleInput<Configuration>.self)
            return head._type.makeViewList(view: view, modifier: head, inputs: poppedInputs)
        } else {
            guard !(Body.self is Never.Type) else {
                fatalError("\(Self.self) may not have Body == Never")
            }
            let bodyGV = view[\.body]
            return Body._makeViewList(view: bodyGV, inputs: inputs)
        }
    }
}
