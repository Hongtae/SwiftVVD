//
//  File: PickerStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol PickerStyle {
    static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

public struct _PickerValue<Style, SelectionValue>
where Style: PickerStyle, SelectionValue: Hashable {
    let style: Style
    let configuration: PickerStyleConfiguration<SelectionValue>

    init(
        style: Style,
        configuration: PickerStyleConfiguration<SelectionValue>
    ) {
        self.style = style
        self.configuration = configuration
    }
}

struct PickerStyleConfiguration<SelectionValue>
where SelectionValue: Hashable {
    struct Label: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct Content: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct CurrentValueLabel: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var _selection: Binding<SelectionValue>
    var multiSelection: [Binding<SelectionValue>]
    var currentValueLabel: CurrentValueLabel?

    init(
        selection: Binding<SelectionValue>,
        multiSelection: [Binding<SelectionValue>],
        hasCurrentValueLabel: Bool
    ) {
        _selection = selection
        self.multiSelection = multiSelection
        currentValueLabel = hasCurrentValueLabel
            ? CurrentValueLabel()
            : nil
    }

    var label: Label { Label() }
    var content: Content { Content() }

    var selections: [Binding<SelectionValue>] {
        [_selection] + multiSelection
    }
}

private protocol AnyPickerStyleType {
    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedPicker<SelectionValue>>,
        style: AnyPickerStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedPicker<SelectionValue>>,
        style: AnyPickerStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

private struct AnyPickerStyle {
    var value: AGAttribute
    var type: any AnyPickerStyleType.Type
}

private struct PickerStyleType<Style: PickerStyle>: AnyPickerStyleType {
    private static func makeValue<SelectionValue>(
        view: _GraphValue<ResolvedPicker<SelectionValue>>,
        style: AnyPickerStyle,
        graph: _AGGraph
    ) -> _GraphValue<_PickerValue<Style, SelectionValue>>
    where SelectionValue: Hashable {
        let styleAttribute = Attribute<Style>(style.value)
        let configuration = view[\.configuration]._attribute
        let value: Attribute<_PickerValue<Style, SelectionValue>> =
            graph.makeRule {
                _PickerValue(
                    style: styleAttribute.value,
                    configuration: configuration.value
                )
            }
        return _GraphValue(_attribute: value)
    }

    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedPicker<SelectionValue>>,
        style: AnyPickerStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PickerStyleType.makeView called outside an active graph."
            )
        }
        return Style._makeView(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedPicker<SelectionValue>>,
        style: AnyPickerStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PickerStyleType.makeViewList called outside an active graph."
            )
        }
        return Style._makeViewList(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }
}

private struct PickerStyleInput: ViewInput {
    static var defaultValue: AnyPickerStyle? { nil }

    static func valuesEqual(
        _ lhs: AnyPickerStyle?,
        _ rhs: AnyPickerStyle?
    ) -> Bool {
        false
    }
}

struct PickerStyleWriter<Style: PickerStyle>:
    ViewModifier,
    _GraphInputsModifier
{
    typealias Body = Never
    var style: Style

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[PickerStyleInput.self] = AnyPickerStyle(
            value: modifier[\.style]._attribute.identifier,
            type: PickerStyleType<Style>.self
        )
    }
}

struct ResolvedPicker<SelectionValue>: View, PrimitiveView
where SelectionValue: Hashable {
    typealias Body = Never
    var configuration: PickerStyleConfiguration<SelectionValue>

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedPicker._makeView called outside an active graph."
            )
        }
        let style = inputs.base[PickerStyleInput.self]
            ?? defaultStyle(in: graph)
        return style.type.makeView(view: view, style: style, inputs: inputs)
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedPicker._makeViewList called outside an active graph."
            )
        }
        let style = inputs.base[PickerStyleInput.self]
            ?? defaultStyle(in: graph)
        return style.type.makeViewList(
            view: view,
            style: style,
            inputs: inputs
        )
    }

    private static func defaultStyle(in graph: _AGGraph) -> AnyPickerStyle {
        let style: Attribute<DefaultPickerStyle> = graph.makeRule {
            DefaultPickerStyle()
        }
        return AnyPickerStyle(
            value: style.identifier,
            type: PickerStyleType<DefaultPickerStyle>.self
        )
    }
}

extension View {
    public func pickerStyle<Style>(_ style: Style) -> some View
    where Style: PickerStyle {
        modifier(PickerStyleWriter(style: style))
    }
}

struct PickerSelectionProjection<SelectionValue>
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]

    func isSelected(_ value: SelectionValue) -> Bool {
        selections.allSatisfy { $0.wrappedValue == value }
    }

    func select(_ value: SelectionValue) {
        for selection in selections {
            selection.wrappedValue = value
        }
    }

    func binding(for value: SelectionValue) -> Binding<Bool> {
        let selections = selections
        return Binding<Bool>(
            get: {
                selections.allSatisfy { $0.wrappedValue == value }
            },
            set: { isSelected, transaction in
                guard isSelected else { return }
                for selection in selections {
                    selection.transaction(transaction).wrappedValue = value
                }
            }
        )
    }
}

private func pickerTag<SelectionValue>(
    for child: _VariadicView.Children.Element,
    as type: SelectionValue.Type = SelectionValue.self
) -> SelectionValue? where SelectionValue: Hashable {
    switch child[TagValueTraitKey<SelectionValue>.self] {
    case .untagged:
        nil
    case .tagged(let value):
        value
    }
}

private struct PickerMenuBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            Menu {
                _VariadicView.Tree(
                    PickerMenuOptionsRoot(
                        selections: configuration.selections
                    )
                ) {
                    configuration.content
                }
            } label: {
                PickerSelectedLabelBody(configuration: configuration)
            }
        }
    }
}

private struct PickerSelectedLabelBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>

    @ViewBuilder
    var body: some View {
        if let currentValueLabel = configuration.currentValueLabel {
            currentValueLabel
        } else {
            _VariadicView.Tree(
                PickerCurrentValueRoot(
                    selections: configuration.selections
                )
            ) {
                configuration.content
            }
        }
    }
}

private struct PickerCurrentValueRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        if let child = children.first(where: {
            guard let value: SelectionValue = pickerTag(for: $0) else {
                return false
            }
            return PickerSelectionProjection(
                selections: selections
            ).isSelected(value)
        }) {
            child
        }
    }
}

private struct PickerMenuOptionsRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]

    func body(children: _VariadicView.Children) -> some View {
        ForEach(children.indices, id: \.self) { index in
            PickerMenuOption(
                child: children[index],
                selections: selections
            )
        }
    }
}

private struct PickerMenuOption<SelectionValue>: View
where SelectionValue: Hashable {
    var child: _VariadicView.Children.Element
    var selections: [Binding<SelectionValue>]

    @ViewBuilder
    var body: some View {
        if let value: SelectionValue = pickerTag(for: child) {
            Toggle(
                isOn: PickerSelectionProjection(
                    selections: selections
                ).binding(for: value)
            ) {
                child
            }
        } else {
            child
        }
    }
}

private struct PickerRowsBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
            _VariadicView.Tree(
                PickerRowsRoot(selections: configuration.selections)
            ) {
                configuration.content
            }
        }
    }
}

private struct PickerRowsRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]

    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(children.indices, id: \.self) { index in
                PickerRow(
                    child: children[index],
                    selections: selections
                )
            }
        }
    }
}

private struct PickerRow<SelectionValue>: View
where SelectionValue: Hashable {
    var child: _VariadicView.Children.Element
    var selections: [Binding<SelectionValue>]

    private var tag: SelectionValue? {
        pickerTag(for: child)
    }

    private var isSelected: Bool {
        guard let tag else { return false }
        return PickerSelectionProjection(
            selections: selections
        ).isSelected(tag)
    }

    private func select() {
        guard let tag else { return }
        PickerSelectionProjection(selections: selections).select(tag)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(isSelected ? "●" : "○")
            child
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .gesture(
            SingleTapGesture<MouseEvent>().onEnded { _ in
                select()
            },
            including: .all
        )
        .simultaneousGesture(
            SingleTapGesture<TouchEvent>().onEnded { _ in
                select()
            },
            including: .all
        )
    }
}

private struct PickerSegmentsBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
            _VariadicView.Tree(
                PickerSegmentsRoot(selections: configuration.selections)
            ) {
                configuration.content
            }
        }
    }
}

private struct PickerSegmentsRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]

    func body(children: _VariadicView.Children) -> some View {
        HStack(spacing: 1) {
            ForEach(children.indices, id: \.self) { index in
                PickerSegment(
                    child: children[index],
                    selections: selections
                )
            }
        }
    }
}

private struct PickerSegment<SelectionValue>: View
where SelectionValue: Hashable {
    var child: _VariadicView.Children.Element
    var selections: [Binding<SelectionValue>]

    private var tag: SelectionValue? {
        pickerTag(for: child)
    }

    private var isSelected: Bool {
        guard let tag else { return false }
        return PickerSelectionProjection(
            selections: selections
        ).isSelected(tag)
    }

    private func select() {
        guard let tag else { return }
        PickerSelectionProjection(selections: selections).select(tag)
    }

    var body: some View {
        child
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Color.blue.opacity(0.18)
                } else {
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SingleTapGesture<MouseEvent>().onEnded { _ in
                    select()
                },
                including: .all
            )
            .simultaneousGesture(
                SingleTapGesture<TouchEvent>().onEnded { _ in
                    select()
                },
                including: .all
            )
    }
}

private enum PickerPresentation {
    case menu
    case segmented
    case rows
}

private struct PickerStyleBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>
    var presentation: PickerPresentation

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .menu:
            PickerMenuBody(configuration: configuration)
        case .segmented:
            PickerSegmentsBody(configuration: configuration)
        case .rows:
            PickerRowsBody(configuration: configuration)
        }
    }
}

private enum PickerStyleRenderer {
    static func makeView<Style, SelectionValue>(
        value: _GraphValue<_PickerValue<Style, SelectionValue>>,
        inputs: _ViewInputs,
        presentation: PickerPresentation
    ) -> _ViewOutputs
    where Style: PickerStyle, SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PickerStyleRenderer.makeView called outside an active graph."
            )
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<PickerStyleBody<SelectionValue>> = graph.makeRule {
            PickerStyleBody(
                configuration: configuration.value,
                presentation: presentation
            )
        }
        return PickerStyleBody<SelectionValue>._makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func makeViewList<Style, SelectionValue>(
        value: _GraphValue<_PickerValue<Style, SelectionValue>>,
        inputs: _ViewListInputs,
        presentation: PickerPresentation
    ) -> _ViewListOutputs
    where Style: PickerStyle, SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PickerStyleRenderer.makeViewList called outside an active graph."
            )
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<PickerStyleBody<SelectionValue>> = graph.makeRule {
            PickerStyleBody(
                configuration: configuration.value,
                presentation: presentation
            )
        }
        return PickerStyleBody<SelectionValue>._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }
}

public struct DefaultPickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .menu
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .menu
        )
    }
}

public struct MenuPickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .menu
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .menu
        )
    }
}

public struct SegmentedPickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }
}

public struct RadioGroupPickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .rows
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .rows
        )
    }
}

public struct InlinePickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .rows
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .rows
        )
    }
}

public struct PalettePickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }
}

public struct TabsPickerStyle: PickerStyle {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeView(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        PickerStyleRenderer.makeViewList(
            value: value,
            inputs: inputs,
            presentation: .segmented
        )
    }
}

extension PickerStyle where Self == DefaultPickerStyle {
    public static var automatic: DefaultPickerStyle { DefaultPickerStyle() }
}

extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}

extension PickerStyle where Self == SegmentedPickerStyle {
    public static var segmented: SegmentedPickerStyle {
        SegmentedPickerStyle()
    }
}

extension PickerStyle where Self == RadioGroupPickerStyle {
    public static var radioGroup: RadioGroupPickerStyle {
        RadioGroupPickerStyle()
    }
}

extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

extension PickerStyle where Self == PalettePickerStyle {
    public static var palette: PalettePickerStyle { PalettePickerStyle() }
}

extension PickerStyle where Self == TabsPickerStyle {
    public static var tabs: TabsPickerStyle { TabsPickerStyle() }
}
