//
//  File: ListStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol ListStyle {
    static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

public struct _ListValue<Style, SelectionValue>
where Style: ListStyle, SelectionValue: Hashable {
    let style: Style
    let configuration: _ListStyleConfiguration<
        SelectionManagerBox<SelectionValue>
    >

    init(
        style: Style,
        configuration: _ListStyleConfiguration<
            SelectionManagerBox<SelectionValue>
        >
    ) {
        self.style = style
        self.configuration = configuration
    }
}

struct ListStyleContent: ViewAlias, PrimitiveView {
    typealias Body = Never
}

struct _ListStyleConfiguration<Selection> {
    var selection: Binding<Selection>?
    var content: ListStyleContent
}

private protocol AnyListStyleType {
    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedList<SelectionValue>>,
        style: AnyListStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedList<SelectionValue>>,
        style: AnyListStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

private struct AnyListStyle {
    var value: AGAttribute
    var type: any AnyListStyleType.Type
}

private struct ListStyleType<Style: ListStyle>: AnyListStyleType {
    private static func makeValue<SelectionValue>(
        view: _GraphValue<ResolvedList<SelectionValue>>,
        style: AnyListStyle,
        graph: _AGGraph
    ) -> _GraphValue<_ListValue<Style, SelectionValue>>
    where SelectionValue: Hashable {
        let style = Attribute<Style>(style.value)
        let configuration = view[\.configuration]._attribute
        let value: Attribute<_ListValue<Style, SelectionValue>> =
            graph.makeRule {
                _ListValue(
                    style: style.value,
                    configuration: configuration.value
                )
            }
        return _GraphValue(_attribute: value)
    }

    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedList<SelectionValue>>,
        style: AnyListStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("ListStyleType.makeView called outside an active graph.")
        }
        return Style._makeView(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedList<SelectionValue>>,
        style: AnyListStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ListStyleType.makeViewList called outside an active graph."
            )
        }
        return Style._makeViewList(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }
}

private struct ListStyleInput: ViewInput {
    static var defaultValue: AnyListStyle? { nil }
    static func valuesEqual(_ lhs: AnyListStyle?, _ rhs: AnyListStyle?) -> Bool {
        false
    }
}

struct ListStyleWriter<Style: ListStyle>: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var style: Style

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[ListStyleInput.self] = AnyListStyle(
            value: modifier[\.style]._attribute.identifier,
            type: ListStyleType<Style>.self
        )
    }
}

struct ResolvedList<SelectionValue>: View, PrimitiveView
where SelectionValue: Hashable {
    typealias Body = Never

    var configuration: _ListStyleConfiguration<
        SelectionManagerBox<SelectionValue>
    >

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ResolvedList._makeView called outside an active graph.")
        }
        let style = inputs.base[ListStyleInput.self] ?? defaultStyle(in: graph)
        return style.type.makeView(view: view, style: style, inputs: inputs)
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedList._makeViewList called outside an active graph."
            )
        }
        let style = inputs.base[ListStyleInput.self] ?? defaultStyle(in: graph)
        return style.type.makeViewList(
            view: view,
            style: style,
            inputs: inputs
        )
    }

    private static func defaultStyle(in graph: _AGGraph) -> AnyListStyle {
        let style: Attribute<DefaultListStyle> = graph.makeRule {
            DefaultListStyle()
        }
        return AnyListStyle(
            value: style.identifier,
            type: ListStyleType<DefaultListStyle>.self
        )
    }
}

extension View {
    public func listStyle<Style>(_ style: Style) -> some View
    where Style: ListStyle {
        modifier(ListStyleWriter(style: style))
    }
}

struct ListCoreOptions: OptionSet, Hashable, Sendable {
    var rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let insetDefaults = ListCoreOptions(rawValue: 3)
    static let bordered = ListCoreOptions(rawValue: 16)
    static let alternatingRowBackgrounds = ListCoreOptions(rawValue: 32)
}

public struct AlternatingRowBackgroundBehavior: Hashable, Sendable {
    enum Guts: Hashable, Sendable {
        case automatic
        case enabled
        case disabled
    }

    var guts: Guts

    public static let automatic = AlternatingRowBackgroundBehavior(
        guts: .automatic
    )
    public static let enabled = AlternatingRowBackgroundBehavior(guts: .enabled)
    public static let disabled = AlternatingRowBackgroundBehavior(
        guts: .disabled
    )
}

public struct ListSectionSpacing: Sendable {
    enum Storage: Sendable {
        case `default`
        case compact
        case custom(CGFloat)
    }

    var storage: Storage

    public static let `default` = ListSectionSpacing(storage: .default)
    public static let compact = ListSectionSpacing(storage: .compact)

    public static func custom(_ spacing: CGFloat) -> ListSectionSpacing {
        ListSectionSpacing(storage: .custom(spacing))
    }

    func resolved(default defaultSpacing: CGFloat) -> CGFloat {
        switch storage {
        case .default:
            defaultSpacing
        case .compact:
            6
        case .custom(let spacing):
            spacing
        }
    }
}

public struct ListItemTint: Sendable {
    enum Effect: Sendable {
        case color(Color)
        case monochrome
    }

    var effect: Effect
    var isFixed: Bool

    public static func fixed(_ tint: Color) -> ListItemTint {
        ListItemTint(effect: .color(tint), isFixed: true)
    }

    public static func preferred(_ tint: Color) -> ListItemTint {
        ListItemTint(effect: .color(tint), isFixed: false)
    }

    public static let monochrome = ListItemTint(
        effect: .monochrome,
        isFixed: true
    )
}

struct ListSeparatorConfiguration {
    struct Appearance {
        var visibility: Visibility
        var color: Color?

        static var automatic: Appearance {
            Appearance(visibility: .automatic, color: nil)
        }

        static var hidden: Appearance {
            Appearance(visibility: .hidden, color: nil)
        }
    }

    struct RowKey: _ViewTraitKey {
        static var defaultValue: ListSeparatorConfiguration {
            ListSeparatorConfiguration(top: .hidden, bottom: .automatic)
        }
    }

    struct SectionKey: _ViewTraitKey {
        static var defaultValue: ListSeparatorConfiguration {
            ListSeparatorConfiguration(top: .hidden, bottom: .hidden)
        }
    }

    var top: Appearance
    var bottom: Appearance

    init(
        top: Appearance = .automatic,
        bottom: Appearance = .automatic
    ) {
        self.top = top
        self.bottom = bottom
    }

    mutating func setVisibility(
        _ visibility: Visibility,
        edges: VerticalEdge.Set
    ) {
        if edges.contains(.top) {
            top.visibility = visibility
        }
        if edges.contains(.bottom) {
            bottom.visibility = visibility
        }
    }

    mutating func setColor(
        _ color: Color?,
        edges: VerticalEdge.Set
    ) {
        if edges.contains(.top) {
            top.color = color
        }
        if edges.contains(.bottom) {
            bottom.color = color
        }
    }
}

private struct AlternatingRowBackgroundBehaviorKey: EnvironmentKey {
    static var defaultValue: AlternatingRowBackgroundBehavior { .automatic }
}

private struct ListSectionSpacingEnvironmentKey: EnvironmentKey {
    static var defaultValue: ListSectionSpacing? { nil }
}

private struct ListSectionSpacingTraitKey: _ViewTraitKey {
    static var defaultValue: ListSectionSpacing? { nil }
}

private struct ListItemTintTraitKey: _ViewTraitKey {
    static var defaultValue: ListItemTint? { nil }
}

private struct IsSelectionEnabledTraitKey: _ViewTraitKey {
    static var defaultValue: Bool { true }
}

private struct SectionActionsTraitKey: _ViewTraitKey {
    static var defaultValue: AnyView? { nil }
}

struct ListSectionMarginsTraitKey: _ViewTraitKey {
    static var defaultValue: OptionalEdgeInsets { OptionalEdgeInsets() }
}

extension EnvironmentValues {
    var alternatingRowBackgroundBehavior: AlternatingRowBackgroundBehavior {
        get { self[AlternatingRowBackgroundBehaviorKey.self] }
        set { self[AlternatingRowBackgroundBehaviorKey.self] = newValue }
    }

    var listSectionSpacing: ListSectionSpacing? {
        get { self[ListSectionSpacingEnvironmentKey.self] }
        set { self[ListSectionSpacingEnvironmentKey.self] = newValue }
    }
}

private struct ListAppearance: Equatable {
    var outerInsets: EdgeInsets
    var rowInsets: EdgeInsets
    var sectionMargins: EdgeInsets
    var rowSpacing: CGFloat
    var sectionSpacing: CGFloat
    var pinsHeaders: Bool
    var drawsBorder: Bool
    var alternatesRowBackgrounds: Bool
}

private protocol ListStyleAppearanceProviding: ListStyle {
    var listAppearance: ListAppearance { get }
}

private struct MakeListBody<Style, SelectionValue>: Rule
where
    Style: ListStyleAppearanceProviding,
    SelectionValue: Hashable
{
    var _value: Attribute<_ListValue<Style, SelectionValue>>

    var value: ListStyleBody<SelectionValue> {
        let value = _value.value
        return ListStyleBody(
            configuration: value.configuration,
            appearance: value.style.listAppearance
        )
    }
}

private extension ListStyleAppearanceProviding {
    static func makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("ListStyle._makeView called outside an active graph.")
        }
        let body: Attribute<ListStyleBody<SelectionValue>> = graph.makeRule(
            MakeListBody(_value: value._attribute)
        )
        return ListStyleBody<SelectionValue>._makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("ListStyle._makeViewList called outside an active graph.")
        }
        let body: Attribute<ListStyleBody<SelectionValue>> = graph.makeRule(
            MakeListBody(_value: value._attribute)
        )
        return ListStyleBody<SelectionValue>._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }
}

private struct ListStyleBody<SelectionValue>: View
where SelectionValue: Hashable {
    @Environment(\.alternatingRowBackgroundBehavior)
    private var alternatingRowBackgroundBehavior
    @Environment(\.listSectionSpacing)
    private var listSectionSpacing

    var configuration: _ListStyleConfiguration<
        SelectionManagerBox<SelectionValue>
    >
    var appearance: ListAppearance

    private var resolvedAppearance: ListAppearance {
        var appearance = appearance
        switch alternatingRowBackgroundBehavior.guts {
        case .automatic:
            break
        case .enabled:
            appearance.alternatesRowBackgrounds = true
        case .disabled:
            appearance.alternatesRowBackgrounds = false
        }
        if let listSectionSpacing {
            appearance.sectionSpacing = listSectionSpacing.resolved(
                default: appearance.sectionSpacing
            )
        }
        return appearance
    }

    @ViewBuilder
    private var scrollBody: some View {
        let appearance = resolvedAppearance
        ScrollView(.vertical) {
            Group(sections: configuration.content) { sections in
                LazyVStack(
                    alignment: .leading,
                    spacing: appearance.sectionSpacing,
                    pinnedViews: appearance.pinsHeaders
                        ? [.sectionHeaders]
                        : []
                ) {
                    ForEach(sections) { section in
                        RenderedListSection(
                            section: section,
                            selection: configuration.selection,
                            appearance: appearance
                        )
                    }
                }
                .padding(appearance.outerInsets)
            }
        }
    }

    @ViewBuilder
    var body: some View {
        if resolvedAppearance.drawsBorder {
            scrollBody.overlay {
                Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1)
            }
        } else {
            scrollBody
        }
    }
}

private struct ListSeparatorView: View {
    var appearance: ListSeparatorConfiguration.Appearance

    @ViewBuilder
    var body: some View {
        if let color = appearance.color {
            Divider().overlay { color }
        } else {
            Divider()
        }
    }
}

private struct RenderedListSection<SelectionValue>: View
where SelectionValue: Hashable {
    @Environment(\.defaultMinListHeaderHeight)
    private var defaultMinListHeaderHeight

    var section: SectionConfiguration
    var selection: Binding<SelectionManagerBox<SelectionValue>>?
    var appearance: ListAppearance

    private var separators: ListSeparatorConfiguration {
        section.containerValues.base[ListSeparatorConfiguration.SectionKey.self]
    }

    private var actions: AnyView? {
        section.containerValues.base[SectionActionsTraitKey.self]
    }

    private var sectionMargins: EdgeInsets {
        let margins = section.containerValues.base[
            ListSectionMarginsTraitKey.self
        ]
        return EdgeInsets(
            top: margins.top ?? appearance.sectionMargins.top,
            leading: margins.leading ?? appearance.sectionMargins.leading,
            bottom: margins.bottom ?? appearance.sectionMargins.bottom,
            trailing: margins.trailing ?? appearance.sectionMargins.trailing
        )
    }

    private var headerProminence: Prominence {
        section.containerValues.base[HeaderProminenceKey.self]
    }

    @ViewBuilder
    private var styledHeader: some View {
        if headerProminence == .increased {
            section.header.font(.headline)
        } else {
            section.header
        }
    }

    @ViewBuilder
    private var header: some View {
        if let actions {
            HStack {
                styledHeader
                Spacer()
                actions
            }
        } else {
            styledHeader
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if separators.top.visibility == .visible {
                ListSeparatorView(appearance: separators.top)
            }
            Section {
                ForEach(section.content) { row in
                    RenderedListRow(
                        row: row,
                        selection: selection,
                        appearance: appearance
                    )
                }
            } header: {
                header.frame(
                    minHeight: defaultMinListHeaderHeight,
                    alignment: .leading
                )
            } footer: {
                section.footer
            }
            if separators.bottom.visibility == .visible {
                ListSeparatorView(appearance: separators.bottom)
            }
        }
        .padding(sectionMargins)
    }
}

private struct RenderedListRow<SelectionValue>: View
where SelectionValue: Hashable {
    @Environment(\.defaultMinListRowHeight)
    private var defaultMinListRowHeight
    @Environment(\.listRowSpacing)
    private var environmentRowSpacing

    var row: Subview
    var selection: Binding<SelectionManagerBox<SelectionValue>>?
    var appearance: ListAppearance

    private var tag: SelectionValue? {
        switch row.containerValues.base[TagValueTraitKey<SelectionValue>.self] {
        case .untagged:
            nil
        case .tagged(let value):
            value
        }
    }

    private var rowInsets: EdgeInsets {
        row.containerValues.base[ListRowInsetsTraitKey.self]
            ?? appearance.rowInsets
    }

    private var isSelected: Bool {
        guard let selection, let tag else { return false }
        return selection.wrappedValue.isSelected(tag)
    }

    private var isSelectionEnabled: Bool {
        row.containerValues.base[IsSelectionEnabledTraitKey.self]
    }

    private var separators: ListSeparatorConfiguration {
        row.containerValues.base[ListSeparatorConfiguration.RowKey.self]
    }

    private var rowSpacing: CGFloat {
        environmentRowSpacing ?? appearance.rowSpacing
    }

    private var rowOffset: Int? {
        row.containerValues.base[DynamicViewContentOffsetTraitKey.self]
    }

    @ViewBuilder
    private var background: some View {
        if let background = row.containerValues.base[
            ListRowBackgroundTraitKey.self
        ] {
            background
        } else if isSelected {
            Color.blue.opacity(0.25)
        } else if appearance.alternatesRowBackgrounds,
                  let rowOffset,
                  !rowOffset.isMultiple(of: 2) {
            Color.gray.opacity(0.12)
        } else {
            Color.clear
        }
    }

    private func select(_ value: SelectionValue, additive: Bool) {
        guard var manager = selection?.wrappedValue else { return }
        manager.select(value, additive: additive)
        selection?.wrappedValue = manager
    }

    @ViewBuilder
    private var selectableRow: some View {
        let content = row
            .padding(rowInsets)
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: defaultMinListRowHeight,
                alignment: .leading
            )
            .background { background }
            .contentShape(Rectangle())

        if let tag, selection != nil, isSelectionEnabled {
            content
                .gesture(
                    SingleTapGesture<MouseEvent>().onEnded { event in
                        select(tag, additive: event.modifiers.contains(.command))
                    },
                    including: .all
                )
                .simultaneousGesture(
                    SingleTapGesture<TouchEvent>().onEnded { _ in
                        select(tag, additive: false)
                    },
                    including: .all
                )
        } else {
            content
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if separators.top.visibility != .hidden {
                ListSeparatorView(appearance: separators.top)
            }
            selectableRow
            if separators.bottom.visibility != .hidden {
                ListSeparatorView(appearance: separators.bottom)
            }
        }
        .padding(.bottom, rowSpacing)
    }
}

public struct DefaultListStyle: ListStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension DefaultListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        ListAppearance(
            outerInsets: EdgeInsets(),
            rowInsets: EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16),
            sectionMargins: EdgeInsets(),
            rowSpacing: 0,
            sectionSpacing: 8,
            pinsHeaders: false,
            drawsBorder: false,
            alternatesRowBackgrounds: false
        )
    }
}

public struct PlainListStyle: ListStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension PlainListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        DefaultListStyle().listAppearance
    }
}

public struct InsetListStyle: ListStyle, Sendable {
    var options: ListCoreOptions

    public init() {
        options = .insetDefaults
    }

    init(alternatesRowBackgrounds: Bool) {
        options = .insetDefaults
        if alternatesRowBackgrounds {
            options.insert(.alternatingRowBackgrounds)
        }
    }

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension InsetListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        ListAppearance(
            outerInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            rowInsets: EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8),
            sectionMargins: EdgeInsets(),
            rowSpacing: 0,
            sectionSpacing: 8,
            pinsHeaders: false,
            drawsBorder: false,
            alternatesRowBackgrounds: options.contains(
                .alternatingRowBackgrounds
            )
        )
    }
}

public struct SidebarListStyle: ListStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension SidebarListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        ListAppearance(
            outerInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            rowInsets: EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8),
            sectionMargins: EdgeInsets(),
            rowSpacing: 0,
            sectionSpacing: 8,
            pinsHeaders: true,
            drawsBorder: false,
            alternatesRowBackgrounds: false
        )
    }
}

public struct GroupedListStyle: ListStyle, Sendable {
    var sectionInset: EdgeInsets?

    public init() {
        sectionInset = nil
    }

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension GroupedListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        ListAppearance(
            outerInsets: sectionInset
                ?? EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
            rowInsets: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12),
            sectionMargins: EdgeInsets(),
            rowSpacing: 0,
            sectionSpacing: 16,
            pinsHeaders: false,
            drawsBorder: false,
            alternatesRowBackgrounds: false
        )
    }
}

public struct InsetGroupedListStyle: ListStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension InsetGroupedListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        GroupedListStyle().listAppearance
    }
}

public struct BorderedListStyle: ListStyle, Sendable {
    var options: ListCoreOptions

    public init() {
        options = [.insetDefaults, .bordered]
    }

    init(alternatesRowBackgrounds: Bool) {
        options = [.insetDefaults, .bordered]
        if alternatesRowBackgrounds {
            options.insert(.alternatingRowBackgrounds)
        }
    }

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_ListValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        makeViewList(value: value, inputs: inputs)
    }
}

extension BorderedListStyle: ListStyleAppearanceProviding {
    fileprivate var listAppearance: ListAppearance {
        var appearance = InsetListStyle(
            alternatesRowBackgrounds: options.contains(
                .alternatingRowBackgrounds
            )
        ).listAppearance
        appearance.drawsBorder = true
        return appearance
    }
}

extension ListStyle where Self == DefaultListStyle {
    public static var automatic: DefaultListStyle { DefaultListStyle() }
}

extension ListStyle where Self == PlainListStyle {
    public static var plain: PlainListStyle { PlainListStyle() }
}

extension ListStyle where Self == InsetListStyle {
    public static var inset: InsetListStyle { InsetListStyle() }
}

extension ListStyle where Self == SidebarListStyle {
    public static var sidebar: SidebarListStyle { SidebarListStyle() }
}

extension ListStyle where Self == GroupedListStyle {
    public static var grouped: GroupedListStyle { GroupedListStyle() }
}

extension ListStyle where Self == InsetGroupedListStyle {
    public static var insetGrouped: InsetGroupedListStyle {
        InsetGroupedListStyle()
    }
}

extension ListStyle where Self == BorderedListStyle {
    public static var bordered: BorderedListStyle {
        BorderedListStyle(alternatesRowBackgrounds: false)
    }
}

private struct DefaultMinListRowHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat { 24 }
}

private struct DefaultMinListHeaderHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

private struct ListRowSpacingKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

extension EnvironmentValues {
    public var defaultMinListRowHeight: CGFloat {
        get { self[DefaultMinListRowHeightKey.self] }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }

    public var defaultMinListHeaderHeight: CGFloat? {
        get { self[DefaultMinListHeaderHeightKey.self] }
        set { self[DefaultMinListHeaderHeightKey.self] = newValue }
    }

    var listRowSpacing: CGFloat? {
        get { self[ListRowSpacingKey.self] }
        set { self[ListRowSpacingKey.self] = newValue }
    }
}

private struct ListRowInsetsTraitKey: _ViewTraitKey {
    static var defaultValue: EdgeInsets? { nil }
}

private struct ListRowBackgroundTraitKey: _ViewTraitKey {
    static var defaultValue: AnyView? { nil }
}

extension View {
    public func alternatingRowBackgrounds(
        _ behavior: AlternatingRowBackgroundBehavior = .enabled
    ) -> some View {
        environment(\.alternatingRowBackgroundBehavior, behavior)
    }

    public func selectionDisabled(_ isDisabled: Bool = true) -> some View {
        _trait(IsSelectionEnabledTraitKey.self, !isDisabled)
    }

    public func sectionActions<Content>(
        @ViewBuilder content: () -> Content
    ) -> some View where Content: View {
        let actions = content()
        return modifier(
            StaticSourceWriter<SectionStyleConfiguration.Actions, Content>(
                source: actions
            )
        )
        ._trait(SectionActionsTraitKey.self, AnyView(actions))
    }

    public func listItemTint(_ tint: ListItemTint?) -> some View {
        _trait(ListItemTintTraitKey.self, tint)
    }

    public func listItemTint(_ tint: Color?) -> some View {
        listItemTint(tint.map { ListItemTint.fixed($0) })
    }

    public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        _trait(ListRowInsetsTraitKey.self, insets)
    }

    public func listRowInsets(
        _ edges: Edge.Set = .all,
        _ length: CGFloat?
    ) -> some View {
        let value = length.map { length in
            EdgeInsets(
                top: edges.contains(.top) ? length : 0,
                leading: edges.contains(.leading) ? length : 0,
                bottom: edges.contains(.bottom) ? length : 0,
                trailing: edges.contains(.trailing) ? length : 0
            )
        }
        return listRowInsets(value)
    }

    public func listRowBackground<Background>(
        _ view: Background?
    ) -> some View where Background: View {
        _trait(ListRowBackgroundTraitKey.self, view.map { AnyView($0) })
    }

    public func listRowSeparator(
        _ visibility: Visibility,
        edges: VerticalEdge.Set = .all
    ) -> some View {
        modifier(
            TraitTransformerModifier<ListSeparatorConfiguration.RowKey> {
                configuration in
                configuration.setVisibility(visibility, edges: edges)
            }
        )
    }

    public func listRowSeparatorTint(
        _ color: Color?,
        edges: VerticalEdge.Set = .all
    ) -> some View {
        modifier(
            TraitTransformerModifier<ListSeparatorConfiguration.RowKey> {
                configuration in
                configuration.setColor(color, edges: edges)
            }
        )
    }

    public func listSectionSeparator(
        _ visibility: Visibility,
        edges: VerticalEdge.Set = .all
    ) -> some View {
        modifier(
            TraitTransformerModifier<ListSeparatorConfiguration.SectionKey> {
                configuration in
                configuration.setVisibility(visibility, edges: edges)
            }
        )
    }

    public func listSectionSeparatorTint(
        _ color: Color?,
        edges: VerticalEdge.Set = .all
    ) -> some View {
        modifier(
            TraitTransformerModifier<ListSeparatorConfiguration.SectionKey> {
                configuration in
                configuration.setColor(color, edges: edges)
            }
        )
    }

    public func listRowSpacing(_ spacing: CGFloat?) -> some View {
        environment(\.listRowSpacing, spacing)
    }

    public func listSectionSpacing(
        _ spacing: ListSectionSpacing
    ) -> some View {
        _trait(ListSectionSpacingTraitKey.self, Optional(spacing))
            .environment(\.listSectionSpacing, spacing)
    }

    public func listSectionSpacing(_ spacing: CGFloat) -> some View {
        listSectionSpacing(.custom(spacing))
    }

    public func listSectionMargins(
        _ edges: Edge.Set = .all,
        _ length: CGFloat?
    ) -> some View {
        modifier(
            TraitTransformerModifier<ListSectionMarginsTraitKey> { margins in
                for edge in Edge.allCases where edges.contains(Edge.Set(edge)) {
                    margins[edge] = length
                }
            }
        )
    }
}
