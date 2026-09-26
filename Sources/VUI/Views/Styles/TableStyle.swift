//
//  File: TableStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TableColumnCustomizationBehavior:
    SetAlgebra,
    Sendable
{
    public typealias Element = TableColumnCustomizationBehavior
    public typealias ArrayLiteralElement = Element

    private var rawValue: UInt8

    public init() {
        rawValue = 0
    }

    private init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(arrayLiteral elements: Element...) {
        self.init()
        for element in elements {
            formUnion(element)
        }
    }

    public static var all: Self {
        [.reorder, .resize, .visibility]
    }

    public static let reorder = Self(rawValue: 1 << 0)
    public static let resize = Self(rawValue: 1 << 1)
    public static let visibility = Self(rawValue: 1 << 2)

    public func contains(_ member: Self) -> Bool {
        intersection(member) == member
    }

    public func union(_ other: Self) -> Self {
        Self(rawValue: rawValue | other.rawValue)
    }

    public func intersection(_ other: Self) -> Self {
        Self(rawValue: rawValue & other.rawValue)
    }

    public func symmetricDifference(_ other: Self) -> Self {
        Self(rawValue: rawValue ^ other.rawValue)
    }

    public mutating func insert(
        _ newMember: Self
    ) -> (inserted: Bool, memberAfterInsert: Self) {
        let inserted = !contains(newMember)
        formUnion(newMember)
        return (inserted, newMember)
    }

    public mutating func remove(_ member: Self) -> Self? {
        guard contains(member) else { return nil }
        rawValue &= ~member.rawValue
        return member
    }

    public mutating func update(with newMember: Self) -> Self? {
        let previous = contains(newMember) ? newMember : nil
        formUnion(newMember)
        return previous
    }

    public mutating func formUnion(_ other: Self) {
        rawValue |= other.rawValue
    }

    public mutating func formIntersection(_ other: Self) {
        rawValue &= other.rawValue
    }

    public mutating func formSymmetricDifference(_ other: Self) {
        rawValue ^= other.rawValue
    }
}

public struct TableColumnAlignment: Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case automatic
        case leading
        case center
        case trailing
        case numeric(Locale.NumberingSystem?)
    }

    private var storage: Storage

    public static var automatic: Self { Self(storage: .automatic) }
    public static var leading: Self { Self(storage: .leading) }
    public static var center: Self { Self(storage: .center) }
    public static var trailing: Self { Self(storage: .trailing) }
    public static var numeric: Self { Self(storage: .numeric(nil)) }

    public static func numeric(
        _ numberingSystem: Locale.NumberingSystem
    ) -> Self {
        Self(storage: .numeric(numberingSystem))
    }

    var resolvedAlignment: Alignment {
        switch storage {
        case .automatic, .leading, .numeric:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }
}

struct TableColumnCustomizationID: Hashable, Sendable, Codable {
    enum Base: Hashable, Sendable, Codable {
        case explicit(String)
        case transient(TransientHint)
    }

    struct TransientHint: Hashable, Sendable, Codable {
        var name: String
        var id: String
    }

    var base: Base

    init(_ explicitID: String) {
        base = .explicit(explicitID)
    }
}

struct TableColumnCustomizationEntry: Equatable, Sendable, Codable {
    enum Visibility: Equatable, Sendable, Codable {
        case automatic
        case visible
        case hidden

        init(_ visibility: VUI.Visibility) {
            switch visibility {
            case .automatic: self = .automatic
            case .visible: self = .visible
            case .hidden: self = .hidden
            }
        }

        var publicValue: VUI.Visibility {
            switch self {
            case .automatic: .automatic
            case .visible: .visible
            case .hidden: .hidden
            }
        }
    }

    var currentWidth: CGFloat?
    var visibility: Visibility

    init(
        currentWidth: CGFloat? = nil,
        visibility: Visibility = .automatic
    ) {
        self.currentWidth = currentWidth
        self.visibility = visibility
    }
}

public struct TableColumnCustomization<RowValue>:
    Equatable,
    Sendable,
    Codable
where RowValue: Identifiable {
    fileprivate var perColumnState:
        [TableColumnCustomizationID: TableColumnCustomizationEntry]
    fileprivate var columnOrder: [TableColumnCustomizationID]?

    public init() {
        perColumnState = [:]
        columnOrder = nil
    }

    public subscript(visibility id: String) -> Visibility {
        get {
            perColumnState[TableColumnCustomizationID(id)]?
                .visibility.publicValue ?? .automatic
        }
        set {
            let id = TableColumnCustomizationID(id)
            var entry = perColumnState[id] ?? TableColumnCustomizationEntry()
            entry.visibility = TableColumnCustomizationEntry.Visibility(newValue)
            perColumnState[id] = entry
        }
    }

    public mutating func resetOrder() {
        columnOrder = nil
    }

}

struct TableColumnCustomizationProjection<RowValue>: Projection
where RowValue: Identifiable {
    func get(
        base: TableColumnCustomization<RowValue>
    ) -> AnyTableColumnCustomization {
        AnyTableColumnCustomization(
            perColumnState: base.perColumnState,
            columnOrder: base.columnOrder
        )
    }

    func set(
        base: inout TableColumnCustomization<RowValue>,
        newValue: AnyTableColumnCustomization
    ) {
        base.perColumnState = newValue.perColumnState
        base.columnOrder = newValue.columnOrder
    }
}

private struct ModifiedTableColumnContent<Base>: TableColumnContent
where Base: TableColumnContent {
    typealias TableRowValue = Base.TableRowValue
    typealias TableColumnSortComparator = Base.TableColumnSortComparator
    typealias TableColumnBody = Never

    var base: Base
    var transform: (inout TableColumnConfiguration) -> Void

    var tableColumnBody: Never {
        fatalError("ModifiedTableColumnContent has no table column body.")
    }
}

extension ModifiedTableColumnContent: TableColumnContentMaterializing
where Base: TableColumnContentMaterializing {
    func materializeTableColumns() -> [TableColumnDescriptor] {
        var columns = base.materializeTableColumns()
        for index in columns.indices {
            transform(&columns[index].configuration)
        }
        return columns
    }
}

extension TableColumnContent {
    public func defaultVisibility(
        _ visibility: Visibility
    ) -> some TableColumnContent<
        Self.TableRowValue,
        Self.TableColumnSortComparator
    > {
        ModifiedTableColumnContent(base: self) {
            $0.defaultVisibility = visibility
        }
    }

    public func customizationID(
        _ id: String
    ) -> some TableColumnContent<
        Self.TableRowValue,
        Self.TableColumnSortComparator
    > {
        ModifiedTableColumnContent(base: self) {
            $0.customizationID = TableColumnCustomizationID(id)
        }
    }

    public func disabledCustomizationBehavior(
        _ behavior: TableColumnCustomizationBehavior
    ) -> some TableColumnContent<
        Self.TableRowValue,
        Self.TableColumnSortComparator
    > {
        ModifiedTableColumnContent(base: self) {
            $0.disabledCustomizationBehavior = behavior
        }
    }

    public func alignment(
        _ alignment: TableColumnAlignment
    ) -> some TableColumnContent<
        Self.TableRowValue,
        Self.TableColumnSortComparator
    > {
        ModifiedTableColumnContent(base: self) {
            $0.alignment = alignment
        }
    }
}

public protocol TableStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Self.Configuration) -> Self.Body

    typealias Configuration = TableStyleConfiguration
}

public struct TableStyleConfiguration {
    struct RowsAlias: View, ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct ColumnsAlias: View, ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var selection: Binding<AnySelectionManager>?
    var sortOrder: Binding<[_UIAnySortComparator]>?
    var columnCustomization: Binding<AnyTableColumnCustomization>?
    var rows: RowsAlias
    var columns: ColumnsAlias

    init(
        selection: Binding<AnySelectionManager>?,
        sortOrder: Binding<[_UIAnySortComparator]>?,
        columnCustomization: Binding<AnyTableColumnCustomization>?
    ) {
        self.selection = selection
        self.sortOrder = sortOrder
        self.columnCustomization = columnCustomization
        rows = RowsAlias()
        columns = ColumnsAlias()
    }
}

struct TableStyleModifier<Style>: StyleModifier
where Style: TableStyle {
    typealias Body = Never
    typealias StyleConfiguration = TableStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(configuration: TableStyleConfiguration) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct ResolvedTableStyle: StyleableView {
    var configuration: TableStyleConfiguration

    typealias DefaultStyleModifier = TableStyleModifier<AutomaticTableStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        TableStyleModifier(style: AutomaticTableStyle())
    }
}

public struct AutomaticTableStyle: TableStyle, Sendable {
    init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.rows
    }
}

public struct InsetTableStyle: TableStyle, Sendable {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.rows
    }
}

public struct BorderedTableStyle: TableStyle, Sendable {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.rows
    }
}

extension TableStyle where Self == AutomaticTableStyle {
    public static var automatic: AutomaticTableStyle {
        AutomaticTableStyle()
    }
}

extension TableStyle where Self == InsetTableStyle {
    public static var inset: InsetTableStyle {
        InsetTableStyle()
    }
}

extension TableStyle where Self == BorderedTableStyle {
    public static var bordered: BorderedTableStyle {
        BorderedTableStyle()
    }
}

extension View {
    public func tableStyle<Style>(_ style: Style) -> some View
    where Style: TableStyle {
        modifier(TableStyleModifier(style: style))
    }
}

private struct TableColumnHeadersVisibilityKey: EnvironmentKey {
    static var defaultValue: Visibility { .automatic }
}

extension EnvironmentValues {
    var tableColumnHeadersVisibility: Visibility {
        get { self[TableColumnHeadersVisibilityKey.self] }
        set { self[TableColumnHeadersVisibilityKey.self] = newValue }
    }
}

extension View {
    public func tableColumnHeaders(
        _ visibility: Visibility
    ) -> some View {
        environment(\.tableColumnHeadersVisibility, visibility)
    }
}

struct TableRenderedBody: View {
    @Environment(\.tableColumnHeadersVisibility)
    private var headersVisibility

    var rows: [TableRowDescriptor]
    var columns: [TableColumnDescriptor]
    var selection: Binding<AnySelectionManager>?
    var sortOrder: Binding<[_UIAnySortComparator]>?

    private var visibleColumns: [TableColumnDescriptor] {
        columns.filter { $0.configuration.defaultVisibility != .hidden }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if headersVisibility != .hidden {
                    TableRenderedHeader(
                        columns: visibleColumns,
                        sortOrder: sortOrder
                    )
                }
                ForEach(rows) { row in
                    TableRenderedRow(
                        row: row,
                        columns: visibleColumns,
                        selection: selection
                    )
                }
            }
        }
    }
}

private struct TableRenderedHeader: View {
    var columns: [TableColumnDescriptor]
    var sortOrder: Binding<[_UIAnySortComparator]>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(columns) { column in
                    TableRenderedHeaderCell(
                        column: column,
                        sortOrder: sortOrder
                    )
                }
            }
            Divider()
        }
    }
}

private struct TableRenderedHeaderCell: View {
    var column: TableColumnDescriptor
    var sortOrder: Binding<[_UIAnySortComparator]>?

    private func selectComparator() {
        guard var comparator = column.comparator else { return }
        comparator.order = .forward
        sortOrder?.wrappedValue = [comparator]
    }

    @ViewBuilder
    private var label: some View {
        let label = column.label
            .font(.headline)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(
                minWidth: column.sizingBehavior.constraints?.min,
                idealWidth: column.sizingBehavior.constraints?.ideal,
                maxWidth: column.sizingBehavior.constraints?.max,
                alignment: column.configuration.alignment.resolvedAlignment
            )
            .contentShape(Rectangle())

        if column.comparator != nil, sortOrder != nil {
            label
                .gesture(
                    SingleTapGesture<MouseEvent>().onEnded { _ in
                        selectComparator()
                    },
                    including: .all
                )
                .simultaneousGesture(
                    SingleTapGesture<TouchEvent>().onEnded { _ in
                        selectComparator()
                    },
                    including: .all
                )
        } else {
            label
        }
    }

    var body: some View {
        label.background(Color.gray.opacity(0.1))
    }
}

private struct TableRenderedRow: View {
    @Environment(\.defaultMinListRowHeight)
    private var defaultMinRowHeight

    var row: TableRowDescriptor
    var columns: [TableColumnDescriptor]
    var selection: Binding<AnySelectionManager>?

    private var isSelected: Bool {
        selection?.wrappedValue.isSelected(row.id) ?? false
    }

    private func select(additive: Bool) {
        guard var manager = selection?.wrappedValue else { return }
        manager.select(row.id, additive: additive)
        selection?.wrappedValue = manager
    }

    private var content: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                column.content(row.value)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(
                        minWidth: column.sizingBehavior.constraints?.min,
                        idealWidth: column.sizingBehavior.constraints?.ideal,
                        maxWidth: column.sizingBehavior.constraints?.max,
                        minHeight: defaultMinRowHeight,
                        alignment: column.configuration.alignment
                            .resolvedAlignment
                    )
            }
        }
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var selectableContent: some View {
        if selection != nil {
            content
                .gesture(
                    SingleTapGesture<MouseEvent>().onEnded { event in
                        select(additive: event.modifiers.contains(.command))
                    },
                    including: .all
                )
                .simultaneousGesture(
                    SingleTapGesture<TouchEvent>().onEnded { _ in
                        select(additive: false)
                    },
                    including: .all
                )
        } else {
            content
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            selectableContent
            Divider()
        }
    }
}
