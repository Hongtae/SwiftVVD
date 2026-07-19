//
//  File: StaticIf.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewInputPredicate: protocol for predicates that can be evaluated
// from _GraphInputs (the common base of _ViewInputs and _ViewListInputs).
// Internal type used for construction-time branch selection.
protocol ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool
    static func evaluate(listInputs: _ViewListInputs) -> Bool
}

extension ViewInputPredicate {
    static func evaluate(listInputs: _ViewListInputs) -> Bool {
        evaluate(inputs: listInputs.base)
    }
}

// StaticIf<Predicate, TrueContent, FalseContent>: evaluates Predicate once against
// the current inputs and unconditionally routes to either TrueContent or FalseContent.
// Unlike _ConditionalContent, the branch cannot change after view construction.
// Unconstrained base struct; View and ViewModifier conformances are conditional.
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

extension StaticIf: PrimitiveView
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

// AndOperationViewInputPredicate<A, B>: ViewInputPredicate that is true
// when both A and B evaluate to true.
struct AndOperationViewInputPredicate<A: ViewInputPredicate, B: ViewInputPredicate>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        A.evaluate(inputs: inputs) && B.evaluate(inputs: inputs)
    }
}

struct BothFeatures<A: Feature, B: Feature>: Feature {
    typealias Value = Bool

    static var isEnabled: Bool {
        A.isEnabled && B.isEnabled
    }
}

struct InferredToolbarUserDefaultFeature: Feature {
    typealias Value = Bool
    static var isEnabled: Bool { false }
}

// ViewInputFlag: ViewInput with Bool value semantics.
protocol ViewInputFlag: ViewInputPredicate, _GraphInputsModifier {
    associatedtype Input: ViewInput = Self where Input.Value: Equatable
    static var value: Input.Value { get }
    init()
}

extension ViewInputFlag {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        inputs[Input.self] == value
    }

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[Input.self] = value
    }
}

// ViewInputBoolFlag: ViewInputFlag that also acts as a ViewInputPredicate.
// evaluate(inputs:) reads the Bool from customInputs.
protocol ViewInputBoolFlag: ViewInput, ViewInputFlag
where Value == Bool, Input.Value == Bool {}

extension ViewInputBoolFlag {
    static var defaultValue: Bool { false }
    static var value: Bool { true }
}

// ViewInputFlagModifier stores the flag value and delegates graph-input
// installation through the flag protocol witness.
struct ViewInputFlagModifier<T: ViewInputFlag>: PrimitiveViewModifier, _GraphInputsModifier {
    typealias Body = Never
    var flag: T

    init(flag: T) {
        self.flag = flag
    }

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        T._makeInputs(modifier: modifier[\.flag], inputs: &inputs)
    }
}

// StyleContextAcceptsPredicate<T>: ViewInputPredicate that evaluates whether
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
        // Tuple type: OR logic over fields
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

// StyleContextAcceptsAnyPredicate<T>: parameter-pack version.
// Treats T the same as StyleContextAcceptsPredicate<T>: a single type or a
// tuple of accepted types with OR logic.
struct StyleContextAcceptsAnyPredicate<T>: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        StyleContextAcceptsPredicate<T>.evaluate(inputs: inputs)
    }
}

// IsDefaultButtonLabel: ViewInputBoolFlag that is true when the label is inside
// a default-style button in a toolbar context (set by ButtonStyleContainerModifier).
struct IsDefaultButtonLabel: ViewInputBoolFlag {
    typealias Value = Bool
    var description: String { "IsDefaultButtonLabel" }
}

// InvertedViewInputPredicate<P>: NOT predicate wrapping P.
struct InvertedViewInputPredicate<P: ViewInputBoolFlag>: ViewInputBoolFlag, _GraphInputsModifier {
    typealias Value = Bool
    typealias Input = P
    static var value: Bool { false }
    var description: String { "InvertedViewInputPredicate<\(P.self)>" }

    static func evaluate(inputs: _GraphInputs) -> Bool {
        !P.evaluate(inputs: inputs)
    }

}

// _staticIf: free function helper for constructing StaticIf with type inference.
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

// MultiViewLabel: ViewInputPredicate that is true when the label is embedded in
// a variadic multi-view container context (e.g. List, Grid rows).
// The default remains false unless a container writes MultiViewLabelKey.
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

// _SemanticFeature<T>: ViewInputPredicate that gates behavior on semantic version.
struct _SemanticFeature<T: SemanticProtocol>: SemanticFeature, Feature {
    typealias Value = Bool

    var description: String {
        "_SemanticFeature<\(T.self)>"
    }

    static var introduced: Semantics {
        T.semantic
    }

}
