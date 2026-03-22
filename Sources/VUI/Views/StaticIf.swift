//
//  File: StaticIf.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// ViewInputPredicate — protocol for predicates that can be evaluated
// from _GraphInputs (the common base of _ViewInputs and _ViewListInputs).
protocol ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool
}

// StaticIf<Predicate, TrueContent, FalseContent> — View that evaluates Predicate
// once against the current inputs and unconditionally routes to either TrueContent
// or FalseContent._makeView/_makeViewList.
// Unlike _ConditionalContent, the branch cannot change after view construction.
struct StaticIf<Predicate: ViewInputPredicate, TrueContent: View, FalseContent: View>: View {
    var trueBody: TrueContent
    var falseBody: FalseContent

    typealias Body = Never

    init(trueBody: TrueContent, falseBody: FalseContent) {
        self.trueBody = trueBody
        self.falseBody = falseBody
    }

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

extension StaticIf: _PrimitiveView {}

// _staticIf — free function helper for constructing StaticIf with type inference.
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

// MultiViewLabel — ViewInputPredicate that is true when the label is embedded in
// a variadic multi-view container context (e.g. List, Grid rows).
// On macOS, this is always false in practice.
struct MultiViewLabel: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        inputs.customInputs.value(forKey: MultiViewLabelKey.self)
    }
}

private struct MultiViewLabelKey: PropertyItem {
    typealias Item = Bool
    static var defaultValue: Bool { false }
    var description: String { "MultiViewLabelKey" }
}

// InterfaceIdiomPredicate<Idiom> — ViewInputPredicate that checks the current
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
