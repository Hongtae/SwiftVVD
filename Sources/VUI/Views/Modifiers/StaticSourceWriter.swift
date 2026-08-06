//
//  File: StaticSourceWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// ViewAlias: source-alias view types whose backing content is provided at
// render time via SourceInput<Self>.
// Conforming types: PrimitiveButtonStyleConfiguration.Label,
//   ButtonStyleConfiguration.Label, LabelStyleConfiguration.Title/Icon,
//   MenuStyleConfiguration.Label/Content, etc.
protocol ViewAlias: View {}

extension ViewAlias {
    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        var inputs = inputs
        guard let source = inputs.popLast(SourceInput<Self>.self) else {
            return _ViewOutputs()
        }
        inputs.base.resetCurrentStyleableView()
        return source.makeView(view: view, inputs: inputs)
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        guard let source = inputs.base.popLast(SourceInput<Self>.self) else {
            return _ViewListOutputs(
                views: .staticList(.merged([])),
                nextImplicitID: inputs.implicitID,
                staticCount: 0
            )
        }
        inputs.base.resetCurrentStyleableView()
        return source.makeViewList(view: view, inputs: inputs)
    }
}

// AnySourceFormula: protocol for type-erased view dispatch.
// SourceFormula<T> conforms via its metatype stored in AnySource.formula.
// The `view` parameter carries the alias view's _GraphValue (e.g. Label's node).
// The `source` parameter carries the full AnySource (formula + backing AG node).
protocol AnySourceFormula {
    static func makeView<A: ViewAlias>(
        view: _GraphValue<A>, source: AnySource, inputs: _ViewInputs
    ) -> _ViewOutputs
    static func makeViewList<A: ViewAlias>(
        view: _GraphValue<A>, source: AnySource, inputs: _ViewListInputs
    ) -> _ViewListOutputs
    static func viewListCount(source: AnySource, inputs: _ViewListCountInputs) -> Int?
    static func snapshot(source: AnySource) -> AnyView?
}

// SourceFormula<T>: zero-size empty struct with no stored properties.
// Carries the backing view type T via its type parameter.
// The alias view's _GraphValue (view:) is ignored. Dispatch goes through source.value.
struct SourceFormula<T: View>: AnySourceFormula {
    static func makeView<A: ViewAlias>(
        view: _GraphValue<A>, source: AnySource, inputs: _ViewInputs
    ) -> _ViewOutputs {
        T._makeView(view: _GraphValue(_attribute: Attribute<T>(source.value.toStrong())), inputs: inputs)
    }
    static func makeViewList<A: ViewAlias>(
        view: _GraphValue<A>, source: AnySource, inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        T._makeViewList(view: _GraphValue(_attribute: Attribute<T>(source.value.toStrong())), inputs: inputs)
    }
    static func viewListCount(source: AnySource, inputs: _ViewListCountInputs) -> Int? {
        nil  // Dynamic/unknown count.
    }
    static func snapshot(source: AnySource) -> AnyView? {
        guard let graph = _AGGraph.current, source.value.isValid(in: graph) else {
            return nil
        }
        return AnyView(Attribute<T>(source.value.toStrong()).value)
    }
}

// AnySource: type-erased source descriptor stored in SourceInput<Source>.
//   formula:    type-erased source formula metatype
//   value:      weak AG node ref for the backing source view
//   valueIsNil: AG attribute for nil-tracking of optional sources
struct AnySource {
    let formula: any AnySourceFormula.Type
    let value: AGWeakAttribute
    let valueIsNil: Optional<Attribute<Bool>>

    init<T: View>(value: _GraphValue<T>, valueIsNil: Optional<Attribute<Bool>> = nil) {
        self.formula = SourceFormula<T>.self
        self.value = value._attribute.asWeak().base
        self.valueIsNil = valueIsNil
    }

    // SE-0352: passing `any AnySourceFormula.Type` to a generic function opens the existential.
    private static func _dispatchMakeView<F: AnySourceFormula, A: ViewAlias>(
        _ f: F.Type, view: _GraphValue<A>, source: AnySource, inputs: _ViewInputs
    ) -> _ViewOutputs {
        F.makeView(view: view, source: source, inputs: inputs)
    }
    private static func _dispatchMakeViewList<F: AnySourceFormula, A: ViewAlias>(
        _ f: F.Type, view: _GraphValue<A>, source: AnySource, inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        F.makeViewList(view: view, source: source, inputs: inputs)
    }
    private static func _dispatchViewListCount<F: AnySourceFormula>(
        _ f: F.Type, source: AnySource, inputs: _ViewListCountInputs
    ) -> Int? {
        F.viewListCount(source: source, inputs: inputs)
    }
    private static func _dispatchSnapshot<F: AnySourceFormula>(
        _ f: F.Type, source: AnySource
    ) -> AnyView? {
        F.snapshot(source: source)
    }

    func makeView<A: ViewAlias>(view: _GraphValue<A>, inputs: _ViewInputs) -> _ViewOutputs {
        Self._dispatchMakeView(formula, view: view, source: self, inputs: inputs)
    }
    func makeViewList<A: ViewAlias>(view: _GraphValue<A>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Self._dispatchMakeViewList(formula, view: view, source: self, inputs: inputs)
    }
    func viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Self._dispatchViewListCount(formula, source: self, inputs: inputs)
    }
    func snapshot() -> AnyView? {
        Self._dispatchSnapshot(formula, source: self)
    }
    func snapshotValue<T: View>(as type: T.Type) -> T? {
        guard isSource(type),
              let graph = _AGGraph.current,
              value.isValid(in: graph) else {
            return nil
        }
        return Attribute<T>(value.toStrong()).value
    }
    func isSource<T: View>(_ type: T.Type) -> Bool {
        ObjectIdentifier(formula as Any.Type) == ObjectIdentifier(SourceFormula<T>.self)
    }
}

// SourceInput<Source>: PropertyKey whose value is Stack<AnySource>.
// Written by StaticSourceWriter. Read by Source._makeView implementations.
struct SourceInput<Source>: ViewInput {
    typealias Value = Stack<AnySource>
    static var defaultValue: Stack<AnySource> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    var description: String { "SourceInput<\(Source.self)>" }
}

struct StyleableViewContextInput: GraphInput {
    static var defaultValue: Any.Type? { nil }

    static func valuesEqual(_ a: Any.Type?, _ b: Any.Type?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            true
        case let (a?, b?):
            ObjectIdentifier(a) == ObjectIdentifier(b)
        default:
            false
        }
    }
}

extension _GraphInputs {
    mutating func setCurrentStyleableView<V: StyleableView>(_ type: V.Type) {
        self[StyleableViewContextInput.self] = type
    }

    func isCurrentStyleableView<V: StyleableView>(_ type: V.Type) -> Bool {
        guard let current = self[StyleableViewContextInput.self] else {
            return false
        }
        return ObjectIdentifier(current) == ObjectIdentifier(type)
    }

    mutating func resetCurrentStyleableView() {
        self[StyleableViewContextInput.self] = nil
    }
}

// StaticSourceWriter<Source, Type>: ViewModifier that writes a SourceInput entry
// for Source into customInputs so that Source._makeView can render Type.
struct StaticSourceWriter<Source, Type> {
    public typealias Body = Never
    let source: Type
}

extension StaticSourceWriter: ViewModifier where Source: View, Type: View {
}

extension StaticSourceWriter: _GraphInputsModifier where Source: View, Type: View {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        if ObjectIdentifier(Source.self) == ObjectIdentifier(Type.self),
           Source.self is any ViewAlias.Type {
            return
        }
        let anySource = AnySource(value: modifier[\.source])
        var stack = inputs.customInputs.value(forKey: SourceInput<Source>.self)
        stack = .node(anySource, stack)
        inputs.customInputs.setValue(stack, forKey: SourceInput<Source>.self)
    }
}

extension View {
    func viewAlias<Alias: ViewAlias, Source: View>(
        _ alias: Alias.Type,
        @ViewBuilder source: () -> Source
    ) -> some View {
        modifier(
            StaticSourceWriter<Alias, Source>(
                source: source()
            )
        )
    }
}
