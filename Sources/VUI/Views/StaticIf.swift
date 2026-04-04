//
//  File: StaticIf.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Protocol for predicates that can be evaluated
// from _GraphInputs (the common base of _ViewInputs and _ViewListInputs).
protocol ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool
}

// StaticIf evaluates Predicate once against
// the current inputs and unconditionally routes to either TrueContent or FalseContent.
// Unlike _ConditionalContent, the branch cannot change after view construction.
// View and ViewModifier conformances are conditional.
struct StaticIf<Predicate, TrueContent, FalseContent> {
    var trueBody: TrueContent
    var falseBody: FalseContent

    init(trueBody: TrueContent, falseBody: FalseContent) {
        self.trueBody = trueBody
        self.falseBody = falseBody
    }
}

// View conformance when both TrueContent and FalseContent are Views.
extension StaticIf: View
    where Predicate: ViewInputPredicate, TrueContent: View, FalseContent: View {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if Predicate.evaluate(inputs: inputs.base) {
            return TrueContent._makeView(view: view[\.trueBody], inputs: inputs)
        } else {
            return FalseContent._makeView(view: view[\.falseBody], inputs: inputs)
        }
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if Predicate.evaluate(inputs: inputs.base) {
            return TrueContent._makeViewList(view: view[\.trueBody], inputs: inputs)
        } else {
            return FalseContent._makeViewList(view: view[\.falseBody], inputs: inputs)
        }
    }
}

extension StaticIf: _PrimitiveView
    where Predicate: ViewInputPredicate, TrueContent: View, FalseContent: View {}

// ViewModifier conformance when both TrueContent and FalseContent are ViewModifiers.
// Used in DefaultLabelStyle.makeBody:
//   .modifier(StaticIf<StyleContextAcceptsPredicate<T>, LabelStyleWritingModifier<S>, EmptyModifier>)
extension StaticIf: ViewModifier
    where Predicate: ViewInputPredicate, TrueContent: ViewModifier, FalseContent: ViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        if Predicate.evaluate(inputs: inputs.base) {
            return TrueContent._makeView(modifier: modifier[\.trueBody], inputs: inputs, body: body)
        } else {
            return FalseContent._makeView(modifier: modifier[\.falseBody], inputs: inputs, body: body)
        }
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        if Predicate.evaluate(inputs: inputs.base) {
            return TrueContent._makeViewList(modifier: modifier[\.trueBody], inputs: inputs, body: body)
        } else {
            return FalseContent._makeViewList(modifier: modifier[\.falseBody], inputs: inputs, body: body)
        }
    }
}

// ViewInputPredicate that is true
// when both A and B evaluate to true.
struct AndOperationViewInputPredicate<A: ViewInputPredicate, B: ViewInputPredicate>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        A.evaluate(inputs: inputs) && B.evaluate(inputs: inputs)
    }
}

// ViewInput with Bool value semantics.
protocol ViewInputFlag: ViewInput where Value == Bool {}

// ViewInputFlag that also acts as a ViewInputPredicate.
// evaluate(inputs:) reads the Bool from customInputs.
protocol ViewInputBoolFlag: ViewInputFlag, ViewInputPredicate {}

extension ViewInputBoolFlag {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        inputs.customInputs.value(forKey: Self.self)
    }
}

// ViewInputFlagModifier<T: ViewInputFlag> — _GraphInputsModifier that writes
// a Bool flag into customInputs.
struct ViewInputFlagModifier<T: ViewInputFlag>: _GraphInputsModifier {
    typealias Body = Never
    let value: Bool

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        inputs.customInputs.setValue(modifier._attribute.value.value, forKey: T.self)
    }
}

// ViewInputPredicate that evaluates whether
// the current style context matches type T.
// T can be a single StyleContext type OR a tuple (A, B, ...) for OR logic.
// Tuple fields are extracted at runtime via _forEachField.
struct StyleContextAcceptsPredicate<T>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        let ctx = inputs.customInputs.value(forKey: StyleContextInput.self)
        // Single StyleContext type
        if let singleType = T.self as? any StyleContext.Type {
            return ctx.acceptsTop(singleType)
        }
        // Tuple type with OR logic over fields.
        var result = false
        _forEachField(of: T.self) { _, _, childType in
            if let scType = childType as? any StyleContext.Type, ctx.acceptsTop(scType) {
                result = true
                return false  // early exit
            }
            return true
        }
        return result
    }
}

// Parameter-pack style predicate variant.
// T is evaluated the same way as StyleContextAcceptsPredicate<T>.
// This covers either a single type or a tuple with OR logic.
struct StyleContextAcceptsAnyPredicate<T>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        StyleContextAcceptsPredicate<T>.evaluate(inputs: inputs)
    }
}

// ViewInputBoolFlag that is true when the label is inside
// a default-style button in a toolbar context (set by ButtonStyleContainerModifier).
struct IsDefaultButtonLabel: ViewInputBoolFlag {
    typealias Value = Bool
    static var defaultValue: Bool { false }
    var description: String { "IsDefaultButtonLabel" }
}

// NOT predicate wrapping P.
struct InvertedViewInputPredicate<P: ViewInputBoolFlag>: ViewInputBoolFlag, _GraphInputsModifier {
    typealias Value = Bool
    typealias Body = Never
    static var defaultValue: Bool { false }
    var description: String { "InvertedViewInputPredicate<\(P.self)>" }

    static func evaluate(inputs: _GraphInputs) -> Bool {
        !P.evaluate(inputs: inputs)
    }

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        // Writes the inverted value of P into customInputs under Self's key.
        let val = !P.evaluate(inputs: inputs)
        inputs.customInputs.setValue(val, forKey: Self.self)
    }
}

// Free function helper for constructing StaticIf with type inference.
// Usage:
//   _staticIf(SomePredicate.self) { trueContent } falseContent: { falseContent }
@inline(__always)
func _staticIf<P: ViewInputPredicate, T: View, F: View>(
    _: P.Type,
    @ViewBuilder trueContent: () -> T,
    @ViewBuilder falseContent: () -> F
) -> StaticIf<P, T, F> {
    StaticIf(trueBody: trueContent(), falseBody: falseContent())
}

// ViewInputPredicate that is true when the label is embedded in
// a variadic multi-view container context (e.g. List, Grid rows).
// On macOS, this is always false in practice.
struct MultiViewLabel: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        inputs.customInputs.value(forKey: MultiViewLabelKey.self)
    }
}

private struct MultiViewLabelKey: PropertyKey {
    typealias Value = Bool
    static var defaultValue: Bool { false }
    var description: String { "MultiViewLabelKey" }
}

// ViewInputPredicate that checks the current
// interface idiom. On macOS, VisionInterfaceIdiom is always false.
struct InterfaceIdiomPredicate<Idiom>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        // VisionOS idiom is never active on macOS.
        return false
    }
}

// VisionInterfaceIdiom — marker type for visionOS interface idiom.
// Used as InterfaceIdiomPredicate<VisionInterfaceIdiom>.
struct VisionInterfaceIdiom {}
