//
//  File: List.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum SelectionManagerBox<SelectionValue>: Equatable
where SelectionValue: Hashable {
    case set(Set<SelectionValue>)
    case optional(SelectionValue?)
    case required(SelectionValue)

    init(optional: SelectionValue?) {
        self = .optional(optional)
    }

    init(required: SelectionValue) {
        self = .required(required)
    }

    func isSelected(_ value: SelectionValue) -> Bool {
        switch self {
        case .set(let values):
            values.contains(value)
        case .optional(let selected):
            selected == value
        case .required(let selected):
            selected == value
        }
    }

    mutating func select(_ value: SelectionValue) {
        switch self {
        case .set(var values):
            values.insert(value)
            self = .set(values)
        case .optional:
            self = .optional(value)
        case .required:
            self = .required(value)
        }
    }

    mutating func select(_ value: SelectionValue, additive: Bool) {
        guard allowsMultipleSelection else {
            select(value)
            return
        }
        if additive {
            if isSelected(value) {
                deselect(value)
            } else {
                select(value)
            }
        } else {
            _ = deselectAll()
            select(value)
        }
    }

    mutating func deselect(_ value: SelectionValue) {
        switch self {
        case .set(var values):
            values.remove(value)
            self = .set(values)
        case .optional(let selected):
            if selected == value {
                self = .optional(nil)
            }
        case .required:
            break
        }
    }

    var isEmpty: Bool {
        switch self {
        case .set(let values):
            values.isEmpty
        case .optional(let value):
            value == nil
        case .required:
            false
        }
    }

    @discardableResult
    mutating func deselectAll() -> Bool {
        let hadSelection = !isEmpty
        switch self {
        case .set:
            self = .set([])
        case .optional:
            self = .optional(nil)
        case .required:
            break
        }
        return hadSelection && isEmpty
    }

    var allowsMultipleSelection: Bool {
        if case .set = self { true } else { false }
    }

    var allowsEmptySelection: Bool {
        if case .required = self { false } else { true }
    }
}

private struct SetSelectionManagerProjection<SelectionValue>: Projection
where SelectionValue: Hashable {
    func get(base: Set<SelectionValue>) -> SelectionManagerBox<SelectionValue> {
        .set(base)
    }

    func set(
        base: inout Set<SelectionValue>,
        newValue: SelectionManagerBox<SelectionValue>
    ) {
        guard case .set(let value) = newValue else { return }
        base = value
    }
}

private struct OptionalSelectionManagerProjection<SelectionValue>: Projection
where SelectionValue: Hashable {
    func get(base: SelectionValue?) -> SelectionManagerBox<SelectionValue> {
        .optional(base)
    }

    func set(
        base: inout SelectionValue?,
        newValue: SelectionManagerBox<SelectionValue>
    ) {
        guard case .optional(let value) = newValue else { return }
        base = value
    }
}

private struct NonOptionalSelectionManagerProjection<SelectionValue>: Projection
where SelectionValue: Hashable {
    func get(base: SelectionValue) -> SelectionManagerBox<SelectionValue> {
        .required(base)
    }

    func set(
        base: inout SelectionValue,
        newValue: SelectionManagerBox<SelectionValue>
    ) {
        guard case .required(let value) = newValue else { return }
        base = value
    }
}

public struct List<SelectionValue, Content>: View
where SelectionValue: Hashable, Content: View {
    var selection: Binding<SelectionManagerBox<SelectionValue>>?
    var content: Content
    @Namespace private var namespace

    public init(
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder content: () -> Content
    ) {
        self.selection = selection?.projecting(
            SetSelectionManagerProjection()
        )
        self.content = content()
        _namespace = Namespace()
    }

    public init(
        selection: Binding<SelectionValue?>?,
        @ViewBuilder content: () -> Content
    ) {
        self.selection = selection?.projecting(
            OptionalSelectionManagerProjection()
        )
        self.content = content()
        _namespace = Namespace()
    }

    @_disfavoredOverload
    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.selection = selection.projecting(
            NonOptionalSelectionManagerProjection()
        )
        self.content = content()
        _namespace = Namespace()
    }

    public var body: some View {
        ResettableLazyLayoutRoot {
            ResolvedList(
                configuration: _ListStyleConfiguration(
                    selection: selection,
                    content: ListStyleContent()
                )
            )
            .viewAlias(ListStyleContent.self) {
                content
            }
        }
    }
}

@available(*, unavailable)
extension List: Sendable {}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {
        selection = nil
        self.content = content()
        _namespace = Namespace()
    }
}

extension List {
    public init<Data, RowContent>(
        _ data: Data,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, Data.Element.ID, RowContent>,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        RowContent: View
    {
        self.init(
            data,
            id: \.id,
            selection: selection,
            rowContent: rowContent
        )
    }

    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, ID, RowContent>,
        Data: RandomAccessCollection,
        ID: Hashable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, id: id, content: rowContent)
        }
    }

    public init<Data, RowContent>(
        _ data: Data,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, Data.Element.ID, RowContent>,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        RowContent: View
    {
        self.init(
            data,
            id: \.id,
            selection: selection,
            rowContent: rowContent
        )
    }

    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, ID, RowContent>,
        Data: RandomAccessCollection,
        ID: Hashable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, id: id, content: rowContent)
        }
    }

    @_disfavoredOverload
    public init<Data, RowContent>(
        _ data: Data,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, Data.Element.ID, RowContent>,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, content: rowContent)
        }
    }

    @_disfavoredOverload
    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, ID, RowContent>,
        Data: RandomAccessCollection,
        ID: Hashable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, id: id, content: rowContent)
        }
    }

    public init<RowContent>(
        _ data: Range<Int>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where
        Content == ForEach<Range<Int>, Int, HStack<RowContent>>,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data) { item in
                HStack {
                    rowContent(item)
                }
            }
        }
    }

    public init<RowContent>(
        _ data: Range<Int>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where
        Content == ForEach<Range<Int>, Int, RowContent>,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, content: rowContent)
        }
    }

    @_disfavoredOverload
    public init<RowContent>(
        _ data: Range<Int>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where
        Content == ForEach<Range<Int>, Int, HStack<RowContent>>,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data) { item in
                HStack {
                    rowContent(item)
                }
            }
        }
    }
}

extension List where SelectionValue == Never {
    public init<Data, RowContent>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, Data.Element.ID, RowContent>,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        RowContent: View
    {
        self.init(data, id: \.id, rowContent: rowContent)
    }

    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where
        Content == ForEach<Data, ID, RowContent>,
        Data: RandomAccessCollection,
        ID: Hashable,
        RowContent: View
    {
        self.init {
            ForEach(data, id: id, content: rowContent)
        }
    }

    public init<RowContent>(
        _ data: Range<Int>,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where
        Content == ForEach<Range<Int>, Int, RowContent>,
        RowContent: View
    {
        self.init {
            ForEach(data, content: rowContent)
        }
    }
}

extension List {
    @_disfavoredOverload
    public init<Data, RowContent>(
        _ data: Binding<Data>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>,
            Data.Element.ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        Data.Index: Hashable,
        RowContent: View
    {
        self.init(
            data,
            id: \.id,
            selection: selection,
            rowContent: rowContent
        )
    }

    @_disfavoredOverload
    public init<Data, ID, RowContent>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, ID)>,
            ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Index: Hashable,
        ID: Hashable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, id: id, content: rowContent)
        }
    }

    @_disfavoredOverload
    public init<Data, RowContent>(
        _ data: Binding<Data>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>,
            Data.Element.ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        Data.Index: Hashable,
        RowContent: View
    {
        self.init(
            data,
            id: \.id,
            selection: selection,
            rowContent: rowContent
        )
    }

    @_disfavoredOverload
    public init<Data, ID, RowContent>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, ID)>,
            ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Index: Hashable,
        ID: Hashable,
        RowContent: View
    {
        self.init(selection: selection) {
            ForEach(data, id: id, content: rowContent)
        }
    }
}

extension List where SelectionValue == Never {
    @_disfavoredOverload
    public init<Data, RowContent>(
        _ data: Binding<Data>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>,
            Data.Element.ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Element: Identifiable,
        Data.Index: Hashable,
        RowContent: View
    {
        self.init(data, id: \.id, rowContent: rowContent)
    }

    @_disfavoredOverload
    public init<Data, ID, RowContent>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    ) where
        Content == ForEach<
            LazyMapSequence<Data.Indices, (Data.Index, ID)>,
            ID,
            RowContent
        >,
        Data: MutableCollection,
        Data: RandomAccessCollection,
        Data.Index: Hashable,
        ID: Hashable,
        RowContent: View
    {
        self.init {
            ForEach(data, id: id, content: rowContent)
        }
    }
}
