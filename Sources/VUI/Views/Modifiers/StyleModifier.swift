//
//  File: StyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Stack<Element> — linked list.
//   empty  |  node(value: Element, next: Stack<Element>)
enum Stack<Element> {
    case empty
    indirect case node(value: Element, next: Stack<Element>)

    func pushing(_ element: Element) -> Stack<Element> {
        .node(value: element, next: self)
    }

    func popping() -> (head: Element, tail: Stack<Element>)? {
        guard case .node(let v, let next) = self else { return nil }
        return (v, next)
    }
}

// Phantom type used as metatype key for type-erased dispatch.
// Stored in AnyStyleModifier._type as StyleModifierType<ButtonStyleModifier<S>>.Type
// or StyleModifierType<LabelStyleModifier<S>>.Type.
struct StyleModifierType<Modifier> {}

// AG node value wrappers — stored in the attribute graph node pointed to
// by AnyStyleModifier.value.
struct ButtonStyleModifier<S: PrimitiveButtonStyle> {
    let style: S
}
struct LabelStyleModifier<S: LabelStyle> {
    let style: S
}

// Internal protocols for accessing the wrapped style value.
protocol _HasPrimStyle {
    func _primStyle() -> any PrimitiveButtonStyle
}
extension ButtonStyleModifier: _HasPrimStyle {
    func _primStyle() -> any PrimitiveButtonStyle { style }
}

protocol _HasLabelStyle {
    func _labelStyle() -> any LabelStyle
}
extension LabelStyleModifier: _HasLabelStyle {
    func _labelStyle() -> any LabelStyle { style }
}

// Dispatch protocols — conditional conformances of StyleModifierType allow
// the metatype stored in AnyStyleModifier._type to be cast to these and
// used for type-erased style extraction.
protocol _StyleModifierPrimDispatch {
    static func _primStyle(attrID: AGAttribute) -> any PrimitiveButtonStyle
}
extension StyleModifierType: _StyleModifierPrimDispatch where Modifier: _HasPrimStyle {
    static func _primStyle(attrID: AGAttribute) -> any PrimitiveButtonStyle {
        Attribute<Modifier>(attrID).value._primStyle()
    }
}

protocol _StyleModifierLabelDispatch {
    static func _labelStyle(attrID: AGAttribute) -> any LabelStyle
}
extension StyleModifierType: _StyleModifierLabelDispatch where Modifier: _HasLabelStyle {
    static func _labelStyle(attrID: AGAttribute) -> any LabelStyle {
        Attribute<Modifier>(attrID).value._labelStyle()
    }
}

// Type-erased style modifier. Two stored properties match reference Mirror output:
//   value: AGAttribute             — points to the AG node storing the style
//   _type: StyleModifierType<T>.Type — metatype for dispatch and identification
struct AnyStyleModifier {
    let value: AGAttribute
    let _type: Any.Type

    // Computed — type-erased style extraction.
    var primStyle: (any PrimitiveButtonStyle)? {
        (_type as? any _StyleModifierPrimDispatch.Type)?._primStyle(attrID: value)
    }
    var labelStyle: (any LabelStyle)? {
        (_type as? any _StyleModifierLabelDispatch.Type)?._labelStyle(attrID: value)
    }
}

// PropertyItem key — value is Stack<AnyStyleModifier>.
// PrimitiveButtonStyle uses StyleInput<PrimitiveButtonStyleConfiguration>.
// LabelStyle uses StyleInput<LabelStyleConfiguration>.
struct StyleInput<Configuration>: PropertyItem {
    typealias Item = Stack<AnyStyleModifier>
    static var defaultValue: Stack<AnyStyleModifier> { .empty }
    var description: String { "StyleInput<\(Configuration.self)>" }
}
