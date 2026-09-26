//
//  File: Table.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _TableColumnInputs {
    public init() {}
}

public struct _TableColumnOutputs {
    public init() {}
}

public struct _TableRowInputs {
    public init() {}
}

public struct _TableRowOutputs {
    public init() {}
}

public protocol TableColumnContent<
    TableRowValue,
    TableColumnSortComparator
> {
    associatedtype TableRowValue: Identifiable =
        Self.TableColumnBody.TableRowValue
    associatedtype TableColumnSortComparator: SortComparator =
        Self.TableColumnBody.TableColumnSortComparator
    associatedtype TableColumnBody: TableColumnContent

    var tableColumnBody: Self.TableColumnBody { get }

    static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _TableColumnInputs
    ) -> _TableColumnOutputs

    static func _tableColumnCount(inputs: _TableColumnInputs) -> Int?
}

extension TableColumnContent {
    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _TableColumnInputs
    ) -> _TableColumnOutputs {
        _TableColumnOutputs()
    }

    public static func _tableColumnCount(
        inputs: _TableColumnInputs
    ) -> Int? {
        nil
    }
}

public protocol TableRowContent<TableRowValue> {
    associatedtype TableRowValue: Identifiable = Self.TableRowBody.TableRowValue
    associatedtype TableRowBody: TableRowContent

    var tableRowBody: Self.TableRowBody { get }

    static func _makeRows(
        content: _GraphValue<Self>,
        inputs: _TableRowInputs
    ) -> _TableRowOutputs

    static func _tableRowCount(inputs: _TableRowInputs) -> Int?
    static func _containsOutlineSymbol(inputs: _TableRowInputs) -> Bool
}

extension TableRowContent {
    public static func _makeRows(
        content: _GraphValue<Self>,
        inputs: _TableRowInputs
    ) -> _TableRowOutputs {
        _TableRowOutputs()
    }

    public static func _tableRowCount(inputs: _TableRowInputs) -> Int? {
        nil
    }

    public static func _containsOutlineSymbol(
        inputs: _TableRowInputs
    ) -> Bool {
        false
    }
}

extension Never {
    public typealias TableRowValue = Never
}

extension Never: TableColumnContent {
    public typealias TableColumnSortComparator = Never
    public typealias TableColumnBody = Never

    public var tableColumnBody: Never {
        fatalError("Never has no table column body.")
    }
}

extension Never: TableRowContent {
    public typealias TableRowBody = Never

    public var tableRowBody: Never {
        fatalError("Never has no table row body.")
    }
}

protocol AnySelectionManagerBox {
    var selectedValues: Set<AnyHashable> { get }
    var allowsMultipleSelection: Bool { get }

    func selecting(
        _ value: AnyHashable,
        additive: Bool
    ) -> any AnySelectionManagerBox
}

private struct OptionalSelectionManagerBox<ID>: AnySelectionManagerBox
where ID: Hashable {
    var selection: ID?

    var selectedValues: Set<AnyHashable> {
        selection.map { [AnyHashable($0)] } ?? []
    }

    var allowsMultipleSelection: Bool { false }

    func selecting(
        _ value: AnyHashable,
        additive: Bool
    ) -> any AnySelectionManagerBox {
        guard let value = value.base as? ID else { return self }
        return Self(selection: value)
    }
}

private struct SetSelectionManagerBox<ID>: AnySelectionManagerBox
where ID: Hashable {
    var selection: Set<ID>

    var selectedValues: Set<AnyHashable> {
        Set(selection.map { AnyHashable($0) })
    }

    var allowsMultipleSelection: Bool { true }

    func selecting(
        _ value: AnyHashable,
        additive: Bool
    ) -> any AnySelectionManagerBox {
        guard let value = value.base as? ID else { return self }
        var selection = selection
        if additive {
            if selection.contains(value) {
                selection.remove(value)
            } else {
                selection.insert(value)
            }
        } else {
            selection = [value]
        }
        return Self(selection: selection)
    }
}

struct AnySelectionManager {
    var box: any AnySelectionManagerBox

    func isSelected(_ value: AnyHashable) -> Bool {
        box.selectedValues.contains(value)
    }

    mutating func select(_ value: AnyHashable, additive: Bool) {
        box = box.selecting(value, additive: additive)
    }
}

private struct OptionalTableSelectionProjection<ID>: Projection
where ID: Hashable {
    func get(base: ID?) -> AnySelectionManager {
        AnySelectionManager(
            box: OptionalSelectionManagerBox(selection: base)
        )
    }

    func set(base: inout ID?, newValue: AnySelectionManager) {
        guard let box = newValue.box as? OptionalSelectionManagerBox<ID> else {
            return
        }
        base = box.selection
    }
}

private struct SetTableSelectionProjection<ID>: Projection
where ID: Hashable {
    func get(base: Set<ID>) -> AnySelectionManager {
        AnySelectionManager(box: SetSelectionManagerBox(selection: base))
    }

    func set(base: inout Set<ID>, newValue: AnySelectionManager) {
        guard let box = newValue.box as? SetSelectionManagerBox<ID> else {
            return
        }
        base = box.selection
    }
}

struct _UIAnySortComparator {
    var _base: Any
    var hashableBase: AnyHashable
    var _compare: (Any, Any) -> ComparisonResult
    var setOrder: (inout Any, SortOrder) -> Void
    var getOrder: (Any) -> SortOrder

    init<Comparator>(_ comparator: Comparator)
    where Comparator: SortComparator {
        _base = comparator
        hashableBase = AnyHashable(
            "\(String(reflecting: Comparator.self)):\(String(reflecting: comparator))"
        )
        _compare = { lhs, rhs in
            guard let lhs = lhs as? Comparator.Compared,
                  let rhs = rhs as? Comparator.Compared else {
                return .orderedSame
            }
            return comparator.compare(lhs, rhs)
        }
        setOrder = { base, order in
            guard var comparator = base as? Comparator else { return }
            comparator.order = order
            base = comparator
        }
        getOrder = { base in
            (base as? Comparator)?.order ?? .forward
        }
    }

    var order: SortOrder {
        get { getOrder(_base) }
        set { setOrder(&_base, newValue) }
    }

    func compare(_ lhs: Any, _ rhs: Any) -> ComparisonResult {
        _compare(lhs, rhs)
    }
}

private struct TableSortOrderProjection<Comparator>: Projection
where Comparator: SortComparator {
    func get(base: [Comparator]) -> [_UIAnySortComparator] {
        base.map(_UIAnySortComparator.init)
    }

    func set(base: inout [Comparator], newValue: [_UIAnySortComparator]) {
        base = newValue.compactMap { $0._base as? Comparator }
    }
}

private func sendableTableKeyPath<Root, Value>(
    _ keyPath: KeyPath<Root, Value>
) -> any KeyPath<Root, Value> & Sendable {
    unsafeBitCast(
        keyPath,
        to: (any KeyPath<Root, Value> & Sendable).self
    )
}

struct AnyTableColumnCustomization {
    var perColumnState:
        [TableColumnCustomizationID: TableColumnCustomizationEntry]
    var columnOrder: [TableColumnCustomizationID]?

    init(
        perColumnState: [
            TableColumnCustomizationID: TableColumnCustomizationEntry
        ] = [:],
        columnOrder: [TableColumnCustomizationID]? = nil
    ) {
        self.perColumnState = perColumnState
        self.columnOrder = columnOrder
    }
}

enum TableColumnSizingBehavior {
    struct SizeConstraints {
        var ideal: CGFloat?
        var min: CGFloat
        var max: CGFloat
    }

    case constrained(SizeConstraints)
    case fixedToHeader

    var constraints: SizeConstraints? {
        guard case .constrained(let constraints) = self else { return nil }
        return constraints
    }

    static var automatic: Self {
        .constrained(
            SizeConstraints(ideal: nil, min: 10, max: .infinity)
        )
    }
}

struct TableColumnConfiguration {
    var defaultVisibility: Visibility = .automatic
    var customizationID: TableColumnCustomizationID?
    var disabledCustomizationBehavior = TableColumnCustomizationBehavior()
    var alignment: TableColumnAlignment = .automatic
    var textAlignment: TextAlignment = .leading
}

struct TableColumnDescriptor: Identifiable {
    var id: Int
    var label: AnyView
    var content: (Any) -> AnyView
    var sizingBehavior: TableColumnSizingBehavior
    var comparator: _UIAnySortComparator?
    var configuration: TableColumnConfiguration
}

struct TableRowDescriptor: Identifiable {
    var id: AnyHashable
    var value: Any
    var depth: Int
}

protocol TableColumnContentMaterializing {
    func materializeTableColumns() -> [TableColumnDescriptor]
}

protocol TableRowContentMaterializing {
    func materializeTableRows() -> [TableRowDescriptor]
}

private func materializedColumns(_ content: Any) -> [TableColumnDescriptor] {
    var columns = (content as? any TableColumnContentMaterializing)?
        .materializeTableColumns() ?? []
    for index in columns.indices {
        columns[index].id = index
    }
    return columns
}

private func materializedRows(_ content: Any) -> [TableRowDescriptor] {
    (content as? any TableRowContentMaterializing)?
        .materializeTableRows() ?? []
}

public struct TableColumn<RowValue, Sort, Content, Label>:
    TableColumnContent
where
    RowValue: Identifiable,
    Sort: SortComparator,
    Content: View,
    Label: View
{
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never

    var label: Label
    var content: (RowValue) -> Content
    var sizingBehavior: TableColumnSizingBehavior
    var comparator: _UIAnySortComparator?

    public var tableColumnBody: Never {
        fatalError("TableColumn has no table column body.")
    }
}

extension TableColumn: TableColumnContentMaterializing {
    func materializeTableColumns() -> [TableColumnDescriptor] {
        [
            TableColumnDescriptor(
                id: 0,
                label: AnyView(label),
                content: { value in
                    guard let row = value as? RowValue else {
                        fatalError("Table column received a mismatched row value.")
                    }
                    return AnyView(content(row))
                },
                sizingBehavior: sizingBehavior,
                comparator: comparator,
                configuration: TableColumnConfiguration()
            )
        ]
    }
}

extension TableColumn where Sort == Never, Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = Text(titleKey)
        self.content = content
        sizingBehavior = .automatic
        comparator = nil
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where S: StringProtocol {
        label = Text(title)
        self.content = content
        sizingBehavior = .automatic
        comparator = nil
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = Text(titleResource)
        self.content = content
        sizingBehavior = .automatic
        comparator = nil
    }

    public init(
        _ text: Text,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = text
        self.content = content
        sizingBehavior = .automatic
        comparator = nil
    }
}

extension TableColumn where
    Sort == Never,
    Content == Text,
    Label == Text
{
    public init(
        _ titleKey: LocalizedStringKey,
        value: KeyPath<RowValue, String>
    ) {
        self.init(titleKey) { row in Text(row[keyPath: value]) }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        value: KeyPath<RowValue, String>
    ) where S: StringProtocol {
        self.init(title) { row in Text(row[keyPath: value]) }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        value: KeyPath<RowValue, String>
    ) {
        self.init(titleResource) { row in Text(row[keyPath: value]) }
    }

    public init(_ text: Text, value: KeyPath<RowValue, String>) {
        self.init(text) { row in Text(row[keyPath: value]) }
    }
}

extension TableColumn where RowValue == Sort.Compared, Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = Text(titleKey)
        self.content = content
        sizingBehavior = .automatic
        self.comparator = _UIAnySortComparator(comparator)
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where S: StringProtocol {
        label = Text(title)
        self.content = content
        sizingBehavior = .automatic
        self.comparator = _UIAnySortComparator(comparator)
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = Text(titleResource)
        self.content = content
        sizingBehavior = .automatic
        self.comparator = _UIAnySortComparator(comparator)
    }

    public init(
        _ text: Text,
        sortUsing comparator: Sort,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        label = text
        self.content = content
        sizingBehavior = .automatic
        self.comparator = _UIAnySortComparator(comparator)
    }
}

extension TableColumn where
    Sort == KeyPathComparator<RowValue>,
    Label == Text
{
    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: KeyPath<RowValue, Value>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where Value: Comparable {
        self.init(
            titleKey,
            sortUsing: KeyPathComparator(sendableTableKeyPath(value)),
            content: content
        )
    }

    @_disfavoredOverload
    public init<S, Value>(
        _ title: S,
        value: KeyPath<RowValue, Value>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where S: StringProtocol, Value: Comparable {
        self.init(
            title,
            sortUsing: KeyPathComparator(sendableTableKeyPath(value)),
            content: content
        )
    }

    @_disfavoredOverload
    public init<Value>(
        _ titleResource: LocalizedStringResource,
        value: KeyPath<RowValue, Value>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where Value: Comparable {
        self.init(
            titleResource,
            sortUsing: KeyPathComparator(sendableTableKeyPath(value)),
            content: content
        )
    }

    public init<Value>(
        _ text: Text,
        value: KeyPath<RowValue, Value>,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where Value: Comparable {
        self.init(
            text,
            sortUsing: KeyPathComparator(sendableTableKeyPath(value)),
            content: content
        )
    }

    public init<Value, Comparator>(
        _ titleKey: LocalizedStringKey,
        value: KeyPath<RowValue, Value>,
        comparator: Comparator,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) where Comparator: SortComparator, Comparator.Compared == Value {
        self.init(
            titleKey,
            sortUsing: KeyPathComparator(
                sendableTableKeyPath(value),
                comparator: comparator
            ),
            content: content
        )
    }
}

extension TableColumn where
    Sort == KeyPathComparator<RowValue>,
    Content == Text,
    Label == Text
{
    public init(
        _ titleKey: LocalizedStringKey,
        value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .localizedStandard
    ) {
        self.init(
            titleKey,
            value: value,
            comparator: comparator
        ) { row in
            Text(row[keyPath: value])
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .localizedStandard
    ) where S: StringProtocol {
        self.init(
            Text(title),
            sortUsing: KeyPathComparator(
                sendableTableKeyPath(value),
                comparator: comparator
            )
        ) { row in
            Text(row[keyPath: value])
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .localizedStandard
    ) {
        self.init(
            Text(titleResource),
            sortUsing: KeyPathComparator(
                sendableTableKeyPath(value),
                comparator: comparator
            )
        ) { row in
            Text(row[keyPath: value])
        }
    }

    public init(
        _ text: Text,
        value: KeyPath<RowValue, String>,
        comparator: String.StandardComparator = .localizedStandard
    ) {
        self.init(
            text,
            sortUsing: KeyPathComparator(
                sendableTableKeyPath(value),
                comparator: comparator
            )
        ) { row in
            Text(row[keyPath: value])
        }
    }
}

extension TableColumn {
    @available(
        *,
        unavailable,
        message: "Pass one or more parameters to modify a column's width."
    )
    public func width() -> Self {
        self
    }

    public func width(_ width: CGFloat? = nil) -> Self {
        var copy = self
        if let width {
            copy.sizingBehavior = .constrained(
                .init(ideal: width, min: width, max: width)
            )
        } else {
            copy.sizingBehavior = .automatic
        }
        return copy
    }

    public func width(
        min: CGFloat? = nil,
        ideal: CGFloat? = nil,
        max: CGFloat? = nil
    ) -> Self {
        var copy = self
        copy.sizingBehavior = .constrained(
            .init(
                ideal: ideal,
                min: min ?? 10,
                max: max ?? .infinity
            )
        )
        return copy
    }
}

public struct TupleTableColumnContent<RowValue, Sort, Value>:
    TableColumnContent
where RowValue: Identifiable, Sort: SortComparator {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never

    public var value: Value

    init(
        _ value: Value,
        valueType: RowValue.Type,
        sortType: Sort.Type
    ) {
        self.value = value
    }

    public var tableColumnBody: Never {
        fatalError("TupleTableColumnContent has no table column body.")
    }
}

extension TupleTableColumnContent: TableColumnContentMaterializing {
    func materializeTableColumns() -> [TableColumnDescriptor] {
        Mirror(reflecting: value).children.flatMap { child in
            (child.value as? any TableColumnContentMaterializing)?
                .materializeTableColumns() ?? []
        }
    }
}

@resultBuilder
public struct TableColumnBuilder<RowValue, Sort>
where RowValue: Identifiable, Sort: SortComparator {
    public static func buildExpression<Content, Label>(
        _ column: TableColumn<RowValue, Sort, Content, Label>
    ) -> TableColumn<RowValue, Sort, Content, Label>
    where Content: View, Label: View {
        column
    }

    @_disfavoredOverload
    public static func buildExpression<Content, Label>(
        _ column: TableColumn<RowValue, Never, Content, Label>
    ) -> TableColumn<RowValue, Never, Content, Label>
    where Content: View, Label: View {
        column
    }

    public static func buildExpression<Column>(_ column: Column) -> Column
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Sort
    {
        column
    }

    @_disfavoredOverload
    public static func buildExpression<Column>(_ column: Column) -> Column
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Never
    {
        column
    }

    public static func buildIf<Column>(
        _ column: Column?
    ) -> Column?
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Sort
    {
        column
    }

    @_disfavoredOverload
    public static func buildIf<Column>(
        _ column: Column?
    ) -> Column?
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Never
    {
        column
    }

    public static func buildEither<TrueContent, FalseContent>(
        first content: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableColumnContent,
        FalseContent: TableColumnContent,
        TrueContent.TableRowValue == RowValue,
        TrueContent.TableColumnSortComparator == Sort,
        FalseContent.TableRowValue == RowValue,
        FalseContent.TableColumnSortComparator == Sort
    {
        _ConditionalContent(storage: .trueContent(content))
    }

    @_disfavoredOverload
    public static func buildEither<TrueContent, FalseContent>(
        first content: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableColumnContent,
        FalseContent: TableColumnContent,
        TrueContent.TableRowValue == RowValue,
        TrueContent.TableColumnSortComparator == Never,
        FalseContent.TableRowValue == RowValue,
        FalseContent.TableColumnSortComparator == Never
    {
        _ConditionalContent(storage: .trueContent(content))
    }

    public static func buildEither<TrueContent, FalseContent>(
        second content: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableColumnContent,
        FalseContent: TableColumnContent,
        TrueContent.TableRowValue == RowValue,
        TrueContent.TableColumnSortComparator == Sort,
        FalseContent.TableRowValue == RowValue,
        FalseContent.TableColumnSortComparator == Sort
    {
        _ConditionalContent(storage: .falseContent(content))
    }

    @_disfavoredOverload
    public static func buildEither<TrueContent, FalseContent>(
        second content: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableColumnContent,
        FalseContent: TableColumnContent,
        TrueContent.TableRowValue == RowValue,
        TrueContent.TableColumnSortComparator == Never,
        FalseContent.TableRowValue == RowValue,
        FalseContent.TableColumnSortComparator == Never
    {
        _ConditionalContent(storage: .falseContent(content))
    }

    public static func buildBlock<Column>(_ column: Column) -> Column
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Sort
    {
        column
    }

    @_disfavoredOverload
    public static func buildBlock<Column>(_ column: Column) -> Column
    where
        Column: TableColumnContent,
        Column.TableRowValue == RowValue,
        Column.TableColumnSortComparator == Never
    {
        column
    }

    public static func buildBlock<C0, C1>(
        _ c0: C0,
        _ c1: C1
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1>(
        _ c0: C0,
        _ c1: C1
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue,
        C5.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4, C5>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never,
        C5.TableRowValue == RowValue,
        C5.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue,
        C5.TableRowValue == RowValue,
        C6.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never,
        C5.TableRowValue == RowValue,
        C5.TableColumnSortComparator == Never,
        C6.TableRowValue == RowValue,
        C6.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue,
        C5.TableRowValue == RowValue,
        C6.TableRowValue == RowValue,
        C7.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never,
        C5.TableRowValue == RowValue,
        C5.TableColumnSortComparator == Never,
        C6.TableRowValue == RowValue,
        C6.TableColumnSortComparator == Never,
        C7.TableRowValue == RowValue,
        C7.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C8: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue,
        C5.TableRowValue == RowValue,
        C6.TableRowValue == RowValue,
        C7.TableRowValue == RowValue,
        C8.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7, c8),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C8: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never,
        C5.TableRowValue == RowValue,
        C5.TableColumnSortComparator == Never,
        C6.TableRowValue == RowValue,
        C6.TableColumnSortComparator == Never,
        C7.TableRowValue == RowValue,
        C7.TableColumnSortComparator == Never,
        C8.TableRowValue == RowValue,
        C8.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7, c8),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8,
        _ c9: C9
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C8: TableColumnContent,
        C9: TableColumnContent,
        C0.TableRowValue == RowValue,
        C1.TableRowValue == RowValue,
        C2.TableRowValue == RowValue,
        C3.TableRowValue == RowValue,
        C4.TableRowValue == RowValue,
        C5.TableRowValue == RowValue,
        C6.TableRowValue == RowValue,
        C7.TableRowValue == RowValue,
        C8.TableRowValue == RowValue,
        C9.TableRowValue == RowValue
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9),
            valueType: RowValue.self,
            sortType: Sort.self
        )
    }

    @_disfavoredOverload
    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8,
        _ c9: C9
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        C0: TableColumnContent,
        C1: TableColumnContent,
        C2: TableColumnContent,
        C3: TableColumnContent,
        C4: TableColumnContent,
        C5: TableColumnContent,
        C6: TableColumnContent,
        C7: TableColumnContent,
        C8: TableColumnContent,
        C9: TableColumnContent,
        C0.TableRowValue == RowValue,
        C0.TableColumnSortComparator == Never,
        C1.TableRowValue == RowValue,
        C1.TableColumnSortComparator == Never,
        C2.TableRowValue == RowValue,
        C2.TableColumnSortComparator == Never,
        C3.TableRowValue == RowValue,
        C3.TableColumnSortComparator == Never,
        C4.TableRowValue == RowValue,
        C4.TableColumnSortComparator == Never,
        C5.TableRowValue == RowValue,
        C5.TableColumnSortComparator == Never,
        C6.TableRowValue == RowValue,
        C6.TableColumnSortComparator == Never,
        C7.TableRowValue == RowValue,
        C7.TableColumnSortComparator == Never,
        C8.TableRowValue == RowValue,
        C8.TableColumnSortComparator == Never,
        C9.TableRowValue == RowValue,
        C9.TableColumnSortComparator == Never
    {
        TupleTableColumnContent(
            (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9),
            valueType: RowValue.self,
            sortType: Never.self
        )
    }

}

public struct TableRow<Value>: TableRowContent where Value: Identifiable {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never

    var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var tableRowBody: Never {
        fatalError("TableRow has no table row body.")
    }

    public static func _tableRowCount(inputs: _TableRowInputs) -> Int? {
        1
    }
}

extension TableRow: TableRowContentMaterializing {
    func materializeTableRows() -> [TableRowDescriptor] {
        [
            TableRowDescriptor(
                id: AnyHashable(value.id),
                value: value,
                depth: 0
            )
        ]
    }
}

public struct TupleTableRowContent<Value, Content>: TableRowContent
where Value: Identifiable {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never

    public var value: Content

    init(_ value: Content, ofType: Value.Type) {
        self.value = value
    }

    public var tableRowBody: Never {
        fatalError("TupleTableRowContent has no table row body.")
    }
}

extension TupleTableRowContent: TableRowContentMaterializing {
    func materializeTableRows() -> [TableRowDescriptor] {
        Mirror(reflecting: value).children.flatMap { child in
            (child.value as? any TableRowContentMaterializing)?
                .materializeTableRows() ?? []
        }
    }
}

@resultBuilder
public struct TableRowBuilder<Value> where Value: Identifiable {
    public static func buildExpression<Content>(_ content: Content) -> Content
    where Content: TableRowContent, Content.TableRowValue == Value {
        content
    }

    public static func buildIf<Content>(
        _ content: Content?
    ) -> Content?
    where Content: TableRowContent, Content.TableRowValue == Value {
        content
    }

    public static func buildEither<TrueContent, FalseContent>(
        first content: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableRowContent,
        FalseContent: TableRowContent,
        TrueContent.TableRowValue == Value,
        FalseContent.TableRowValue == Value
    {
        _ConditionalContent(storage: .trueContent(content))
    }

    public static func buildEither<TrueContent, FalseContent>(
        second content: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent>
    where
        TrueContent: TableRowContent,
        FalseContent: TableRowContent,
        TrueContent.TableRowValue == Value,
        FalseContent.TableRowValue == Value
    {
        _ConditionalContent(storage: .falseContent(content))
    }

    public static func buildBlock<Content>(_ content: Content) -> Content
    where Content: TableRowContent, Content.TableRowValue == Value {
        content
    }

    public static func buildBlock<C0, C1>(
        _ c0: C0,
        _ c1: C1
    ) -> TupleTableRowContent<Value, (C0, C1)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> TupleTableRowContent<Value, (C0, C1, C2)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C5: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value,
        C5.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C5: TableRowContent,
        C6: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value,
        C5.TableRowValue == Value,
        C6.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C5: TableRowContent,
        C6: TableRowContent,
        C7: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value,
        C5.TableRowValue == Value,
        C6.TableRowValue == Value,
        C7.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C5: TableRowContent,
        C6: TableRowContent,
        C7: TableRowContent,
        C8: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value,
        C5.TableRowValue == Value,
        C6.TableRowValue == Value,
        C7.TableRowValue == Value,
        C8.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7, c8), ofType: Value.self)
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8,
        _ c9: C9
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        C0: TableRowContent,
        C1: TableRowContent,
        C2: TableRowContent,
        C3: TableRowContent,
        C4: TableRowContent,
        C5: TableRowContent,
        C6: TableRowContent,
        C7: TableRowContent,
        C8: TableRowContent,
        C9: TableRowContent,
        C0.TableRowValue == Value,
        C1.TableRowValue == Value,
        C2.TableRowValue == Value,
        C3.TableRowValue == Value,
        C4.TableRowValue == Value,
        C5.TableRowValue == Value,
        C6.TableRowValue == Value,
        C7.TableRowValue == Value,
        C8.TableRowValue == Value,
        C9.TableRowValue == Value
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), ofType: Value.self)
    }

}

extension _ConditionalContent: TableColumnContent
where
    TrueContent: TableColumnContent,
    FalseContent: TableColumnContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue,
    TrueContent.TableColumnSortComparator ==
        FalseContent.TableColumnSortComparator
{
    public typealias TableRowValue = TrueContent.TableRowValue
    public typealias TableColumnSortComparator =
        TrueContent.TableColumnSortComparator
    public typealias TableColumnBody = Never

    public var tableColumnBody: Never {
        fatalError("_ConditionalContent has no table column body.")
    }
}

extension _ConditionalContent: TableColumnContentMaterializing
where
    TrueContent: TableColumnContent,
    FalseContent: TableColumnContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue,
    TrueContent.TableColumnSortComparator ==
        FalseContent.TableColumnSortComparator
{
    func materializeTableColumns() -> [TableColumnDescriptor] {
        switch storage {
        case .trueContent(let content):
            return (content as? any TableColumnContentMaterializing)?
                .materializeTableColumns() ?? []
        case .falseContent(let content):
            return (content as? any TableColumnContentMaterializing)?
                .materializeTableColumns() ?? []
        }
    }
}

extension Optional: TableColumnContent where Wrapped: TableColumnContent {
    public typealias TableRowValue = Wrapped.TableRowValue
    public typealias TableColumnSortComparator =
        Wrapped.TableColumnSortComparator
    public typealias TableColumnBody = Never

    public var tableColumnBody: Never {
        fatalError("Optional has no table column body.")
    }
}

extension Optional: TableColumnContentMaterializing
where Wrapped: TableColumnContent {
    func materializeTableColumns() -> [TableColumnDescriptor] {
        guard let wrapped = self else { return [] }
        return (wrapped as? any TableColumnContentMaterializing)?
            .materializeTableColumns() ?? []
    }
}

extension Group: TableColumnContent where Content: TableColumnContent {
    public typealias TableRowValue = Content.TableRowValue
    public typealias TableColumnSortComparator =
        Content.TableColumnSortComparator
    public typealias TableColumnBody = Never

    @_disfavoredOverload
    public init<RowValue, Sort>(
        @TableColumnBuilder<RowValue, Sort> content: () -> Content
    ) where
        RowValue == Content.TableRowValue,
        Sort == Content.TableColumnSortComparator
    {
        self.init(_content: content())
    }

    public var tableColumnBody: Never {
        fatalError("Group has no table column body.")
    }
}

extension Group: TableColumnContentMaterializing
where Content: TableColumnContent {
    func materializeTableColumns() -> [TableColumnDescriptor] {
        (content as? any TableColumnContentMaterializing)?
            .materializeTableColumns() ?? []
    }
}

extension _ConditionalContent: TableRowContent
where
    TrueContent: TableRowContent,
    FalseContent: TableRowContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    public typealias TableRowValue = TrueContent.TableRowValue
    public typealias TableRowBody = Never

    public var tableRowBody: Never {
        fatalError("_ConditionalContent has no table row body.")
    }
}

extension _ConditionalContent: TableRowContentMaterializing
where
    TrueContent: TableRowContent,
    FalseContent: TableRowContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    func materializeTableRows() -> [TableRowDescriptor] {
        switch storage {
        case .trueContent(let content):
            return (content as? any TableRowContentMaterializing)?
                .materializeTableRows() ?? []
        case .falseContent(let content):
            return (content as? any TableRowContentMaterializing)?
                .materializeTableRows() ?? []
        }
    }
}

extension Optional: TableRowContent where Wrapped: TableRowContent {
    public typealias TableRowValue = Wrapped.TableRowValue
    public typealias TableRowBody = Never

    public var tableRowBody: Never {
        fatalError("Optional has no table row body.")
    }
}

extension Optional: TableRowContentMaterializing
where Wrapped: TableRowContent {
    func materializeTableRows() -> [TableRowDescriptor] {
        guard let wrapped = self else { return [] }
        return (wrapped as? any TableRowContentMaterializing)?
            .materializeTableRows() ?? []
    }
}

extension Group: TableRowContent where Content: TableRowContent {
    public typealias TableRowValue = Content.TableRowValue
    public typealias TableRowBody = Never

    @_disfavoredOverload
    public init<RowValue>(
        @TableRowBuilder<RowValue> content: () -> Content
    ) where RowValue == Content.TableRowValue {
        self.init(_content: content())
    }

    public var tableRowBody: Never {
        fatalError("Group has no table row body.")
    }
}

extension Group: TableRowContentMaterializing
where Content: TableRowContent {
    func materializeTableRows() -> [TableRowDescriptor] {
        (content as? any TableRowContentMaterializing)?
            .materializeTableRows() ?? []
    }
}

public struct TableForEachContent<Data>: TableRowContent
where Data: RandomAccessCollection, Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element
    public typealias TableRowBody = ForEach<
        Data,
        Data.Element.ID,
        TableRow<Data.Element>
    >

    var data: Data

    public var tableRowBody: TableRowBody {
        ForEach(
            data: data,
            content: { value in TableRow(value) },
            idGenerator: .keyPath(\.id),
            reuseID: nil
        )
    }
}

extension ForEach: TableRowContent
where Content: TableRowContent {
    public typealias TableRowValue = Content.TableRowValue
    public typealias TableRowBody = Never

    public var tableRowBody: Never {
        fatalError("ForEach has no table row body.")
    }
}

extension ForEach: TableRowContentMaterializing
where Content: TableRowContent & TableRowContentMaterializing {
    func materializeTableRows() -> [TableRowDescriptor] {
        data.flatMap { content($0).materializeTableRows() }
    }
}

extension ForEach
where
    ID == Data.Element.ID,
    Content: TableRowContent,
    Data.Element: Identifiable
{
    @_disfavoredOverload
    public init<RowValue>(
        _ data: Data,
        @TableRowBuilder<RowValue> content: @escaping (Data.Element) -> Content
    ) where RowValue == Content.TableRowValue {
        self.init(
            data: data,
            content: content,
            idGenerator: .keyPath(\.id),
            reuseID: nil
        )
    }

    @_disfavoredOverload
    public init(_ data: Data)
    where Content == TableRow<Data.Element> {
        self.init(data) { TableRow($0) }
    }
}

extension ForEach where Content: TableRowContent {
    @_disfavoredOverload
    public init<RowValue>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @TableRowBuilder<RowValue> content: @escaping (Data.Element) -> Content
    ) where RowValue == Content.TableRowValue {
        self.init(
            data: data,
            content: content,
            idGenerator: .keyPath(id),
            reuseID: nil
        )
    }
}

extension ForEach
where Data == Range<Int>, ID == Int, Content: TableRowContent {
    @_disfavoredOverload
    public init<RowValue>(
        _ data: Range<Int>,
        @TableRowBuilder<RowValue> content: @escaping (Int) -> Content
    ) where RowValue == Content.TableRowValue {
        self.init(
            data: data,
            content: content,
            idGenerator: .offset,
            reuseID: nil
        )
    }
}

extension TableForEachContent: TableRowContentMaterializing {
    func materializeTableRows() -> [TableRowDescriptor] {
        data.map {
            TableRowDescriptor(
                id: AnyHashable($0.id),
                value: $0,
                depth: 0
            )
        }
    }
}

public struct Table<Value, Rows, Columns>
where
    Value == Rows.TableRowValue,
    Rows: TableRowContent,
    Columns: TableColumnContent,
    Rows.TableRowValue == Columns.TableRowValue
{
    var columns: Columns
    var rows: Rows
    var selection: Binding<AnySelectionManager>?
    var sortOrder: Binding<[_UIAnySortComparator]>?
    var columnCustomization: Binding<AnyTableColumnCustomization>?

    private init(
        columns: Columns,
        rows: Rows,
        selection: Binding<AnySelectionManager>?,
        sortOrder: Binding<[_UIAnySortComparator]>?,
        columnCustomization: Binding<AnyTableColumnCustomization>?
    ) {
        self.columns = columns
        self.rows = rows
        self.selection = selection
        self.sortOrder = sortOrder
        self.columnCustomization = columnCustomization
    }
}

extension Table {
    public init(
        of valueType: Value.Type,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: nil,
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init(
        of valueType: Value.Type,
        selection: Binding<Value.ID?>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init(
        of valueType: Value.Type,
        selection: Binding<Set<Value.ID>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init<Sort>(
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: nil,
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Sort>(
        of valueType: Value.Type,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: nil,
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Sort>(
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Sort>(
        of valueType: Value.Type,
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Sort>(
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Sort>(
        of valueType: Value.Type,
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }
}

extension Table {
    public init(
        of valueType: Value.Type,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: nil,
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init(
        of valueType: Value.Type,
        selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init(
        of valueType: Value.Type,
        selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Sort>(
        of valueType: Value.Type = Value.self,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: nil,
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Sort>(
        of valueType: Value.Type = Value.self,
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Sort>(
        of valueType: Value.Type = Value.self,
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where
        Sort: SortComparator,
        Columns.TableRowValue == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: rows(),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }
}

extension Table {
    public init<Data>(
        _ data: Data,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: nil,
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init<Data>(
        _ data: Data,
        selection: Binding<Value.ID?>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init<Data>(
        _ data: Data,
        selection: Binding<Set<Value.ID>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: nil,
            columnCustomization: nil
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: nil,
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: nil
        )
    }
}

extension Table {
    public init<Data>(
        _ data: Data,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: nil,
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Data>(
        _ data: Data,
        selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Data>(
        _ data: Data,
        selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Columns.TableRowValue == Data.Element
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: nil,
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: nil,
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(
                OptionalTableSelectionProjection()
            ),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }

    public init<Data, Sort>(
        _ data: Data,
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where
        Rows == TableForEachContent<Data>,
        Data: RandomAccessCollection,
        Sort: SortComparator,
        Columns.TableRowValue == Data.Element,
        Data.Element == Sort.Compared
    {
        self.init(
            columns: columns(),
            rows: TableForEachContent(data: data),
            selection: selection.projecting(SetTableSelectionProjection()),
            sortOrder: sortOrder.projecting(TableSortOrderProjection()),
            columnCustomization: columnCustomization.projecting(
                TableColumnCustomizationProjection()
            )
        )
    }
}

extension Table: PubliclyPrimitiveView {
    var internalBody: some View {
        let columns = materializedColumns(columns)
        let rows = materializedRows(rows)
        return ResolvedTableStyle(
            configuration: TableStyleConfiguration(
                selection: selection,
                sortOrder: sortOrder,
                columnCustomization: columnCustomization
            )
        )
        .viewAlias(TableStyleConfiguration.RowsAlias.self) {
            TableRenderedBody(
                rows: rows,
                columns: columns,
                selection: selection,
                sortOrder: sortOrder
            )
        }
        .viewAlias(TableStyleConfiguration.ColumnsAlias.self) {
            EmptyView()
        }
    }
}

@available(*, unavailable)
extension Table: Sendable {}
