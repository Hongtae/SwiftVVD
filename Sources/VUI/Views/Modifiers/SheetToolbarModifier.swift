//
//  File: SheetToolbarModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Toolbar support primitives

// Role case names supported by the current toolbar placement surface:
//   automatic, confirmationAction, cancellationAction, destructiveAction,
//   principal, navigation, keyboard
// Raw values are local assignments for this toolbar placement surface.
// Principal, navigation, and keyboard behavior belongs to the broader toolbar pipeline.
public struct ToolbarItemPlacement: Equatable, Hashable, Sendable {
    struct Role: RawRepresentable, Equatable, Hashable, Sendable {
        var rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let automatic          = Role(rawValue: 255)
        static let destructiveAction  = Role(rawValue: 0)   // leading slot in dialog
        static let cancellationAction = Role(rawValue: 1)
        static let confirmation       = Role(rawValue: 2)   // internal alias
        static let confirmationAction = Role(rawValue: 5)
        // Reserved values for placements owned by the broader toolbar pipeline.
        static let principal          = Role(rawValue: 10)
        static let navigation         = Role(rawValue: 11)
        static let keyboard           = Role(rawValue: 12)

        // Convenience predicates used by ModalButtonRow and ToolbarFilterModifier.
        var isDestructiveAction: Bool { self == .destructiveAction }
        var isCancellationAction: Bool { self == .cancellationAction }
        var isConfirmationAction: Bool { self == .confirmationAction || self == .confirmation }
        var isModalAction: Bool { isDestructiveAction || isCancellationAction || isConfirmationAction }
    }

    // Stored placement role.
    var role: Role

    init(role: Role) {
        self.role = role
    }

    public static let automatic          = ToolbarItemPlacement(role: .automatic)
    public static let confirmationAction = ToolbarItemPlacement(role: .confirmationAction)
    public static let cancellationAction = ToolbarItemPlacement(role: .cancellationAction)
    public static let destructiveAction  = ToolbarItemPlacement(role: .destructiveAction)
    public static let principal          = ToolbarItemPlacement(role: .principal)
    public static let navigation         = ToolbarItemPlacement(role: .navigation)
    public static let keyboard           = ToolbarItemPlacement(role: .keyboard)
}

// Local toolbar storage for the currently implemented sheet toolbar path:
// identity, role placement, and a view payload for ModalButtonRow rendering.
// The broader toolbar storage surface lives outside this sheet toolbar path.
struct ToolbarStorage {
    struct ID: Hashable {
        var rawValue: AnyHashable
        init(_ rawValue: AnyHashable) { self.rawValue = rawValue }
    }

    struct Item: Identifiable {
        var id: ID
        var placement: ToolbarItemPlacement.Role
        var view: AnyView
        // Keeps toolbar entry rendering on the original AG path so source aliases
        // such as PrimitiveButtonStyleConfiguration.Label remain connected.
        var generator: TypedUnaryViewGenerator?

        init(id: ID,
             placement: ToolbarItemPlacement.Role,
             view: AnyView,
             generator: TypedUnaryViewGenerator? = nil) {
            self.id = id
            self.placement = placement
            self.view = view
            self.generator = generator
        }
    }

    struct SearchItem {
        var content: AnyView
    }

    struct Entry {
        var item: Item
        var placement: ToolbarItemPlacement.Role { item.placement }
    }

    var items: [Item] = []
    var searchItem: SearchItem? = nil

    mutating func merge(_ other: ToolbarStorage) {
        items.append(contentsOf: other.items)
        if searchItem == nil { searchItem = other.searchItem }
    }

    func toolbarItems(in role: ToolbarItemPlacement.Role) -> [Item] {
        items.filter { $0.placement == role }
    }

    func filtered(_ predicate: (Entry) -> Bool) -> ToolbarStorage {
        var copy = self
        copy.items = items.filter { predicate(Entry(item: $0)) }
        if copy.items.isEmpty { copy.searchItem = nil }
        return copy
    }
}

// Internal preference key for toolbar storage. The key name is local to this module.
struct ToolbarKey: PreferenceKey {
    typealias Value = ToolbarStorage
    static var defaultValue: ToolbarStorage { ToolbarStorage() }

    static func reduce(value: inout ToolbarStorage, nextValue: () -> ToolbarStorage) {
        value.merge(nextValue())
    }
}

// MARK: - ToolbarContent protocol

public struct _ToolbarInputs {
    var viewInputs: _ViewInputs

    init(_ viewInputs: _ViewInputs) {
        self.viewInputs = viewInputs
    }
}

public struct _ToolbarOutputs {
    var storage: OptionalAttribute<ToolbarStorage>

    init(storage: OptionalAttribute<ToolbarStorage> = OptionalAttribute()) {
        self.storage = storage
    }
}

public struct _ToolbarItemList {
    var storage: ToolbarStorage

    init(storage: ToolbarStorage = ToolbarStorage()) {
        self.storage = storage
    }
}

private func mergeToolbarOutputs(
    _ outputs: [_ToolbarOutputs],
    in graph: _AGGraph
) -> _ToolbarOutputs {
    let storageAttributes = outputs.compactMap { $0.storage.attribute }
    guard !storageAttributes.isEmpty else {
        return _ToolbarOutputs()
    }
    if storageAttributes.count == 1 {
        return _ToolbarOutputs(storage: OptionalAttribute(storageAttributes[0]))
    }
    let storage: Attribute<ToolbarStorage> = graph.makeRule {
        var merged = ToolbarStorage()
        for attribute in storageAttributes {
            merged.merge(attribute.value)
        }
        return merged
    }
    return _ToolbarOutputs(storage: OptionalAttribute(storage))
}

private func toolbarIdentifier<ID>(_ value: ID) -> AnyHashable {
    if let value = value as? AnyHashable {
        return value
    }
    if let value = value as? any Hashable {
        return AnyHashable(value)
    }
    return AnyHashable(ObjectIdentifier(ID.self))
}

// Toolbar content is constructed either as graph-backed outputs or into a
// resolved item list.
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    @ToolbarContentBuilder var body: Self.Body { get }

    static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs
    static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    )
}

extension ToolbarContent {
    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        fatalError("The dedicated toolbar construction pipeline is not implemented.")
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
        fatalError("The resolved toolbar content pipeline is not implemented.")
    }
}

extension Never: ToolbarContent {
}

// MARK: - ToolbarDefaultItemKind

// Default toolbar item kind wrapper. Case mapping is stored as raw values.
public struct ToolbarDefaultItemKind: Equatable, Sendable {
    var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

// MARK: - ToolbarItem

// ToolbarItem stores identifier, placement, content, default visibility,
// emptiness, and optional default item kind.
public struct ToolbarItem<ID, Content: View>: ToolbarContent {
    // Stable item identity.
    var identifier: ID
    var placement: ToolbarItemPlacement
    var content: Content
    var showsByDefault: Bool
    var isEmpty: Bool
    // Default kind mapping uses the raw-value wrapper.
    var defaultItemKind: ToolbarDefaultItemKind?

    public typealias Body = Never

    public var body: Never {
        fatalError("ToolbarItem may not have Body == Never")
    }

    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ToolbarItem._makeToolbar called outside AG context")
        }
        let contentView = content[\.content]
        let baseInputs = inputs.viewInputs.base
        let storageAttr: Attribute<ToolbarStorage> = graph.makeRule {
            let item = content._attribute.value
            guard !item.isEmpty else { return ToolbarStorage() }
            var storage = ToolbarStorage()
            storage.items.append(ToolbarStorage.Item(
                id: ToolbarStorage.ID(toolbarIdentifier(item.identifier)),
                placement: item.placement.role,
                view: AnyView(item.content),
                generator: TypedUnaryViewGenerator(contentView, baseInputs: baseInputs)
            ))
            return storage
        }
        return _ToolbarOutputs(storage: OptionalAttribute(storageAttr))
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
        let item = content._attribute.value
        guard !item.isEmpty else { return }
        resolved.storage.items.append(ToolbarStorage.Item(
            id: ToolbarStorage.ID(toolbarIdentifier(item.identifier)),
            placement: item.placement.role,
            view: AnyView(item.content),
            generator: TypedUnaryViewGenerator(content[\.content], baseInputs: inputs)
        ))
    }
}

extension ToolbarItem: Identifiable where ID: Hashable {
    public var id: ID { identifier }
}

extension ToolbarItem where ID == Void {
    public init(placement: ToolbarItemPlacement = .automatic,
                showsByDefault: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.identifier = ()
        self.placement = placement
        self.content = content()
        self.showsByDefault = showsByDefault
        self.isEmpty = false
        self.defaultItemKind = nil
    }
}

extension ToolbarItem where ID == String {
    public init(id: String,
                placement: ToolbarItemPlacement = .automatic,
                showsByDefault: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.identifier = id
        self.placement = placement
        self.content = content()
        self.showsByDefault = showsByDefault
        self.isEmpty = false
        self.defaultItemKind = nil
    }
}

// MARK: - TupleToolbarContent

// @ToolbarContentBuilder produces TupleToolbarContent<C> (single) or
// TupleToolbarContent<(C0, C1, ...)> (multiple items, C = tuple).
// Field iteration reflects over the content tuple and visits view-typed fields.
// Public visibility keeps result-builder expansion usable across module boundaries.
public struct TupleToolbarContent<C>: ToolbarContent {
    public var value: C
    public init(_ value: C) { self.value = value }

    public typealias Body = Never

    public var body: Never {
        fatalError("TupleToolbarContent may not have Body == Never")
    }

    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TupleToolbarContent._makeToolbar called outside AG context")
        }
        var allOutputs: [_ToolbarOutputs] = []

        func makeWholeValue<T: ToolbarContent>(_: T.Type) {
            let value: Attribute<T> = graph.makeRule {
                content._attribute.value.value as! T
            }
            allOutputs.append(T._makeToolbar(
                content: _GraphValue(_attribute: value),
                inputs: inputs
            ))
        }
        if let contentType = C.self as? any ToolbarContent.Type {
            _openExistential(contentType, do: makeWholeValue)
            return mergeToolbarOutputs(allOutputs, in: graph)
        }

        func makeChild<T: ToolbarContent>(_: T.Type, offset: Int) {
            let childAttr: Attribute<T> = graph.makeRule {
                withUnsafeBytes(of: content._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: T.self).pointee
                }
            }
            allOutputs.append(T._makeToolbar(
                content: _GraphValue(_attribute: childAttr),
                inputs: inputs
            ))
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let toolbarType = fieldType as? any ToolbarContent.Type {
                func open<T: ToolbarContent>(_: T.Type) {
                    makeChild(T.self, offset: offset)
                }
                _openExistential(toolbarType, do: open)
            }
            return true
        }
        return mergeToolbarOutputs(allOutputs, in: graph)
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("TupleToolbarContent._makeContent called outside AG context")
        }

        func makeWholeValue<T: ToolbarContent>(_: T.Type) {
            let value: Attribute<T> = graph.makeRule {
                content._attribute.value.value as! T
            }
            T._makeContent(
                content: _GraphValue(_attribute: value),
                inputs: inputs,
                resolved: &resolved
            )
        }
        if let contentType = C.self as? any ToolbarContent.Type {
            _openExistential(contentType, do: makeWholeValue)
            return
        }

        func makeChild<T: ToolbarContent>(_: T.Type, offset: Int) {
            let childAttr: Attribute<T> = graph.makeRule {
                withUnsafeBytes(of: content._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: T.self).pointee
                }
            }
            T._makeContent(
                content: _GraphValue(_attribute: childAttr),
                inputs: inputs,
                resolved: &resolved
            )
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let toolbarType = fieldType as? any ToolbarContent.Type {
                func open<T: ToolbarContent>(_: T.Type) {
                    makeChild(T.self, offset: offset)
                }
                _openExistential(toolbarType, do: open)
            }
            return true
        }
    }
}

// MARK: - ToolbarContentBuilder

// The builder uses @resultBuilder for toolbar content builder semantics.
// buildBlock methods are @inlinable so the public TupleToolbarContent type is usable at call sites.
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildBlock(_ content: Never) -> Never {
        content
    }

    @inlinable
    public static func buildBlock<C: ToolbarContent>(_ c: C) -> TupleToolbarContent<C> {
        TupleToolbarContent(c)
    }

    @inlinable
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(
        _ c0: C0, _ c1: C1
    ) -> TupleToolbarContent<(C0, C1)> {
        TupleToolbarContent((c0, c1))
    }

    @inlinable
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleToolbarContent<(C0, C1, C2)> {
        TupleToolbarContent((c0, c1, c2))
    }

    @inlinable
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent,
                                  C2: ToolbarContent, C3: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleToolbarContent<(C0, C1, C2, C3)> {
        TupleToolbarContent((c0, c1, c2, c3))
    }

    @inlinable
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent,
                                  C2: ToolbarContent, C3: ToolbarContent,
                                  C4: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleToolbarContent<(C0, C1, C2, C3, C4)> {
        TupleToolbarContent((c0, c1, c2, c3, c4))
    }

    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
        first: T
    ) -> _ConditionalContent<T, F> {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
        second: F
    ) -> _ConditionalContent<T, F> {
        .init(storage: .falseContent(second))
    }

    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
    public static func buildExpression<C: ToolbarContent>(_ c: C) -> C { c }
}

// MARK: - _ConditionalContent ToolbarContent conformance

extension _ConditionalContent: ToolbarContent
where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    public typealias Body = Never

    public var body: Never {
        fatalError("_ConditionalContent may not have Body == Never")
    }
}

// MARK: - ToolbarItemGroup

// ToolbarItemGroup stores placement, content, and isEmpty. Unlike ToolbarItem,
// it has no identifier, showsByDefault, or defaultItemKind fields.
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    public typealias Body = Never

    public var body: Never {
        fatalError("ToolbarItemGroup may not have Body == Never")
    }

    var placement: ToolbarItemPlacement
    var content: Content
    var isEmpty: Bool

    public init(placement: ToolbarItemPlacement = .automatic,
                @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
        self.isEmpty = false
    }

    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ToolbarItemGroup._makeToolbar called outside AG context")
        }
        let contentView = content[\.content]
        let baseInputs = inputs.viewInputs.base
        let storageAttr: Attribute<ToolbarStorage> = graph.makeRule {
            let group = content._attribute.value
            guard !group.isEmpty else { return ToolbarStorage() }
            var storage = ToolbarStorage()
            // ToolbarItemGroup uses placement.role and has no identifier. Use a stable hash.
            let id = ToolbarStorage.ID(AnyHashable(ObjectIdentifier(Content.self)))
            storage.items.append(ToolbarStorage.Item(
                id: id,
                placement: group.placement.role,
                view: AnyView(group.content),
                generator: TypedUnaryViewGenerator(contentView, baseInputs: baseInputs)
            ))
            return storage
        }
        return _ToolbarOutputs(storage: OptionalAttribute(storageAttr))
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
        let group = content._attribute.value
        guard !group.isEmpty else { return }
        resolved.storage.items.append(ToolbarStorage.Item(
            id: ToolbarStorage.ID(AnyHashable(ObjectIdentifier(Content.self))),
            placement: group.placement.role,
            view: AnyView(group.content),
            generator: TypedUnaryViewGenerator(content[\.content], baseInputs: inputs)
        ))
    }
}

// MARK: - EmptyToolbarContent

// EmptyToolbarContent: ToolbarContent and CustomizableToolbarContent conformance.
// Produces no toolbar items.
public struct EmptyToolbarContent: ToolbarContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("EmptyToolbarContent may not have Body == Never")
    }

    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        _ToolbarOutputs()
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
    }
}

// MARK: - ToolbarModifier

// Toolbar modifier stores an optional customization ID, toolbar content, and
// optional selection binding. The dedicated _makeToolbar path belongs to the
// toolbar content pipeline. Resolved storage is published through ToolbarKey.
struct ToolbarModifier<CustomizationID, Content: ToolbarContent>: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var id: String?
    var content: Content
    // Selection is reserved for tab/picker integration.
    var selection: Binding<Int>?

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("ToolbarModifier._makeView called outside AG context")
        }
        var outputs = body(_Graph(), inputs)

        var toolbarInputs = inputs
        var keys = toolbarInputs.preferences.keys
        keys.add(ToolbarKey.self)
        toolbarInputs.preferences = PreferencesInputs(keys: keys,
                                                       hostKeys: toolbarInputs.preferences.hostKeys)
        let toolbarOutputs = Content._makeToolbar(
            content: modifier[\.content],
            inputs: _ToolbarInputs(toolbarInputs)
        )
        if let storage = toolbarOutputs.storage.attribute {
            outputs.preferences.append(ToolbarKey.self, node: storage.identifier)
        }
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        // Preference bridge for the current toolbar path. Keep .toolbar attached
        // through list materialization so _makeView can emit ToolbarKey.
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension View {
    public func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        modifier(ToolbarModifier<Void, Content>(id: nil, content: content(), selection: nil))
    }
}

struct SearchContentKey: PreferenceKey {
    typealias Value = AnyView?
    static var defaultValue: AnyView? { nil }

    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        if value == nil { value = nextValue() }
    }
}

struct UsesUnbridgedToolbar: ViewInputBoolFlag {
    typealias Value = Bool
    var description: String { "UsesUnbridgedToolbar" }
}

enum Toolbar {
    struct UpdateContext: Equatable {}
}

private struct _ToolbarUpdateContextKey: EnvironmentKey {
    static var defaultValue: Toolbar.UpdateContext? { nil }
}

extension EnvironmentValues {
    var _toolbarUpdateContext: Toolbar.UpdateContext? {
        get { self[_ToolbarUpdateContextKey.self] }
        set { self[_ToolbarUpdateContextKey.self] = newValue }
    }
}

// Simplified primitive reader for the currently implemented sheet toolbar path.
// Only storage is needed for ModalButtonRow.
struct ToolbarPrimitiveReader {
    var storage: ToolbarStorage
}

// ToolbarReader feeds a simplified primitive reader into content.
//
// Cycle-free design:
// - primitiveReaderAttr is an AG *input* node, not a rule.
// - bodyAttr depends on primitiveReaderAttr (input), not on storageAttr.
// - An update rule reads storageAttr and calls primitiveReaderAttr.setValue when
//   the item IDs change, converging after at most two AG evaluation passes.
// - Item-ID comparison is the convergence guard.
struct ToolbarReader<Edges, Content: View>: View {
    typealias Body = Never
    typealias PrimitiveReader = ToolbarPrimitiveReader

    var content: (ToolbarPrimitiveReader) -> Content

    init(_ edges: Edges.Type = Edges.self, @ViewBuilder content: @escaping (ToolbarPrimitiveReader) -> Content) {
        self.content = content
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ToolbarReader._makeView called outside AG context")
        }
        // PrimitiveReader as AG input, not a rule, so it has a stable cached value
        // that is safe to read even when other rules are evaluating.
        let primitiveReaderAttr: Attribute<ToolbarPrimitiveReader> =
            graph.makeInput(value: ToolbarPrimitiveReader(storage: ToolbarStorage()))

        // bodyAttr depends only on primitiveReaderAttr (input): no cycle with storageAttr.
        let bodyAttr: Attribute<Content> = graph.makeRule {
            view._attribute.value.content(primitiveReaderAttr.value)
        }

        var contentInputs = inputs
        var keys = contentInputs.preferences.keys
        keys.add(ToolbarKey.self)
        keys.add(SearchContentKey.self)
        contentInputs.preferences = PreferencesInputs(keys: keys,
                                                      hostKeys: contentInputs.preferences.hostKeys)
        let outputs = Content._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: contentInputs)

        // Collect ToolbarKey preference from content outputs.
        let toolbarNodes = outputs.preferences.values(for: ToolbarKey.self)
        let storageAttr: Attribute<ToolbarStorage> = graph.makeRule {
            var storage = ToolbarKey.defaultValue
            for nodeID in toolbarNodes {
                let value = Attribute<ToolbarStorage>(nodeID).value
                ToolbarKey.reduce(value: &storage) { value }
            }
            return storage
        }

        // Write new storage into primitiveReaderAttr only when item IDs change,
        // which guarantees convergence in at most two passes.
        graph.makeSideEffectRule {
            let newStorage = storageAttr.value
            let newIDs = newStorage.items.map { $0.id }
            let currentIDs = primitiveReaderAttr.value.storage.items.map { $0.id }
            guard newIDs != currentIDs else { return }
            primitiveReaderAttr.setValue(ToolbarPrimitiveReader(storage: newStorage))
        }

        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToolbarReader: PrimitiveView {}

struct AllToolbarEdges {}

struct ToolbarFilterModifier: ViewModifier {
    typealias Body = Never

    enum Predicate: Equatable {
        case role(ToolbarItemPlacement.Role)
        case keyPath(AnyKeyPath)

        static func == (lhs: Predicate, rhs: Predicate) -> Bool {
            switch (lhs, rhs) {
            case (.role(let a), .role(let b)): return a == b
            case (.keyPath(let a), .keyPath(let b)): return a == b
            default: return false
            }
        }

        func matches(_ entry: ToolbarStorage.Entry) -> Bool {
            let role = entry.placement
            switch self {
            case .role(let expected):
                return role == expected
            case .keyPath(let keyPath):
                guard let typed = keyPath as? KeyPath<ToolbarItemPlacement.Role, Bool> else {
                    return false
                }
                return role[keyPath: typed]
            }
        }
    }

    var predicate: Predicate

    init(predicate: Predicate) {
        self.predicate = predicate
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ToolbarFilterModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard !UsesUnbridgedToolbar.evaluate(inputs: inputs.base),
              inputs.preferences.keys.contains(ToolbarKey.self) else {
            return outputs
        }

        let existingNodes = outputs.preferences.values(for: ToolbarKey.self)
        guard !existingNodes.isEmpty else { return outputs }

        let predicateAttr = modifier[\.predicate]._attribute
        let filteredAttr: Attribute<ToolbarStorage> = graph.makeRule {
            var storage = ToolbarKey.defaultValue
            for nodeID in existingNodes {
                let value = Attribute<ToolbarStorage>(nodeID).value
                ToolbarKey.reduce(value: &storage) { value }
            }
            let predicate = predicateAttr.value
            return storage.filtered { predicate.matches($0) }
        }

        outputs.preferences.preferences.removeAll {
            ObjectIdentifier($0.key) == ObjectIdentifier(ToolbarKey.self)
        }
        outputs.preferences.append(ToolbarKey.self, node: filteredAttr.identifier)
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

struct ToolbarScopeModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

struct PlatformGroupFocusSectionModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func toolbarScope() -> some View {
        modifier(ToolbarScopeModifier())
    }

    func platformGroupFocusSection() -> some View {
        modifier(PlatformGroupFocusSectionModifier())
    }
}

// Layout used for search/content/modal-toolbar vertical composition.
struct SheetContentRoot<L: Layout>: Layout {
    var layout: L

    typealias AnimatableData = L.AnimatableData
    var animatableData: L.AnimatableData {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    init(_ layout: L) {
        self.layout = layout
    }

    func makeCache(subviews: Subviews) -> L.Cache {
        layout.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout L.Cache, subviews: Subviews) {
        layout.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout L.Cache) -> ViewSpacing {
        layout.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout L.Cache) -> CGSize {
        switch subviews.count {
        case 2:
            let content = subviews[0].sizeThatFits(proposal)
            let toolbar = subviews[1].sizeThatFits(
                ProposedViewSize(width: proposal.width ?? content.width, height: nil))
            return CGSize(width: max(content.width, toolbar.width),
                          height: content.height + toolbar.height)
        case 3:
            let search = subviews[0].sizeThatFits(.zero)
            let content = subviews[1].sizeThatFits(proposal)
            let toolbar = subviews[2].sizeThatFits(
                ProposedViewSize(width: proposal.width ?? max(search.width, content.width), height: nil))
            return CGSize(width: max(search.width, max(content.width, toolbar.width)),
                          height: search.height + content.height + toolbar.height)
        default:
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout L.Cache) {
        switch subviews.count {
        case 2:
            let toolbarProposal = ProposedViewSize(width: bounds.width, height: nil)
            let toolbar = subviews[1].sizeThatFits(toolbarProposal)
            let contentHeight = max(0, bounds.height - toolbar.height)
            let contentProposal = ProposedViewSize(width: bounds.width, height: contentHeight)
            let content = subviews[0].sizeThatFits(contentProposal)
            let contentX = bounds.minX + (bounds.width - content.width) * 0.5

            subviews[0].place(at: CGPoint(x: contentX, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: contentProposal)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - toolbar.height),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: toolbar.height))
        case 3:
            let search = subviews[0].sizeThatFits(.zero)
            let toolbarProposal = ProposedViewSize(width: bounds.width, height: nil)
            let toolbar = subviews[2].sizeThatFits(toolbarProposal)
            let contentHeight = max(0, bounds.height - search.height - toolbar.height)
            let contentProposal = ProposedViewSize(width: bounds.width, height: contentHeight)
            let content = subviews[1].sizeThatFits(contentProposal)
            let searchX = bounds.minX + (bounds.width - search.width) * 0.5
            let contentX = bounds.minX + (bounds.width - content.width) * 0.5

            subviews[0].place(at: CGPoint(x: searchX, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(search))
            subviews[1].place(at: CGPoint(x: contentX, y: bounds.minY + search.height),
                              anchor: .topLeading,
                              proposal: contentProposal)
            subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - toolbar.height),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: toolbar.height))
        default:
            layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        }
    }

    func explicitAlignment(of guide: HorizontalAlignment,
                           in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout L.Cache) -> CGFloat? {
        layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(of guide: VerticalAlignment,
                           in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout L.Cache) -> CGFloat? {
        layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

// Layout for modal sheet bottom buttons. Baseline-specific alignment can be
// refined separately. This places leading content at the leading edge and action
// buttons from the trailing edge, matching the confirmed slot separation.
struct DialogBottomButtonsHLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData

    var leadingCount: Int

    init(leadingCount: Int = 0) {
        self.leadingCount = leadingCount
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).reduce(0, max)

        let leadingEnd = min(max(leadingCount, 0), subviews.count)
        let leadingIndices = Array(subviews.indices.prefix(leadingEnd))
        let actionIndices = Array(subviews.indices.dropFirst(leadingEnd))

        func width(for indices: [Subviews.Index]) -> CGFloat {
            let spacing = CGFloat(max(0, indices.count - 1)) * ViewSpacing.defaultSpacing
            return indices.map { sizes[$0].width }.reduce(0, +) + spacing
        }

        let leadingWidth = width(for: leadingIndices)
        let actionWidth = width(for: actionIndices)
        let groupSpacing = leadingWidth > 0 && actionWidth > 0 ? ViewSpacing.defaultSpacing : 0
        let intrinsicWidth = leadingWidth + groupSpacing + actionWidth

        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            return CGSize(width: max(proposedWidth, intrinsicWidth), height: height)
        }
        return CGSize(width: intrinsicWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        var leadingX = bounds.minX
        var trailingX = bounds.maxX
        let midY = bounds.midY

        let leadingEnd = min(max(leadingCount, 0), subviews.count)
        for index in subviews.indices.prefix(leadingEnd) {
            let size = sizes[index]
            subviews[index].place(at: CGPoint(x: leadingX, y: midY),
                                  anchor: .leading,
                                  proposal: ProposedViewSize(size))
            leadingX += size.width + Spacing.defaultValue.width
        }

        for index in subviews.indices.dropFirst(leadingEnd).reversed() {
            let size = sizes[index]
            trailingX -= size.width
            subviews[index].place(at: CGPoint(x: trailingX, y: midY),
                                  anchor: .leading,
                                  proposal: ProposedViewSize(size))
            trailingX -= Spacing.defaultValue.width
        }
    }
}

// MARK: - ContainerBackgroundKeys

// ContainerBackgroundKeys namespace for container background preference keys.
// PresentationKey is used by SheetContent.body via renderContainerBackgroundInHostingView.
enum ContainerBackgroundKeys {
    // PresentationKey: signals to the hosting view that the sheet should render
    // its container background. first-writer-wins Optional<Bool> preference.
    struct PresentationKey: PreferenceKey {
        typealias Value = Bool?
        static var defaultValue: Bool? { nil }
        static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
            if value == nil { value = nextValue() }
        }
    }
}

extension View {
    // renderContainerBackgroundInHostingView signals to the host that the presentation
    // should render a container background. Full implementation requires hosting layer.
    // The current path is a no-op passthrough.
    func renderContainerBackgroundInHostingView<K: PreferenceKey>(_ keyType: K.Type) -> some View {
        self
    }
}

// MARK: - SidebarState

// SidebarState: 1-byte enum/struct controlling sidebar visibility in sheets.
// Used by SheetContent.FixedSidebarModifier to write a fixed Binding<SidebarState>.
// rawValue 2 is written as the constant value (Binding.constant(SidebarState(rawValue: 2))).
// Raw values are carried directly until named sidebar states are introduced.
struct SidebarState: RawRepresentable, Equatable {
    var rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
}

// Private env key for Optional<Binding<SidebarState>>.
// The external key name is unavailable. Use local name _SidebarStateBindingKey.
private struct _SidebarStateBindingKey: EnvironmentKey {
    static var defaultValue: Binding<SidebarState>? { nil }
}

extension EnvironmentValues {
    var _sidebarStateBinding: Binding<SidebarState>? {
        get { self[_SidebarStateBindingKey.self] }
        set { self[_SidebarStateBindingKey.self] = newValue }
    }
}

// MARK: - InteractiveResizeDisabledKey

// InteractiveResizeDisabledKey: Optional<Bool> HostPreferenceKey.
// First-writer-wins: once set, subsequent writes are ignored.
// SheetContent.body writes true (disabling interactive resize) when no other writer has set a value.
struct InteractiveResizeDisabledKey: HostPreferenceKey {
    typealias Value = Bool?
    static var defaultValue: Bool? { nil }
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        if value == nil { value = nextValue() }
    }
}

// MARK: - SheetToolbarModifier

// SheetToolbarModifier: ViewModifier applied as the penultimate step in SheetContent.body.
// body(content:) returns StaticIf<_SemanticFeature<Semantics_v6>, readerBody, forceBody>.
// Stateless modifier (no stored fields).
//
// ReaderBody uses ToolbarReader to feed toolbar storage into ModalButtonRow.
// ForceBody keeps the sheet-content layout path available when the semantic gate
// disables the reader branch.
struct SheetToolbarModifier: ViewModifier {
    func body(content: _ViewModifier_Content<SheetToolbarModifier>) -> some View {
        StaticIf<_SemanticFeature<Semantics_v6>, ReaderBody, ForceBody>(
            trueBody: ReaderBody(content: content),
            falseBody: ForceBody(content: content)
        )
    }

    // ReaderBody uses ToolbarReader with the simplified primitive reader.
    struct ReaderBody: View {
        var content: _ViewModifier_Content<SheetToolbarModifier>

        var body: some View {
            ToolbarReader(AllToolbarEdges.self) { reader in
                _VariadicView.Tree(_LayoutRoot(SheetContentRoot(_VStackLayout()))) {
                    _UnaryViewAdaptor(content)
                    modalToolbar(reader.storage)
                }
            }
            .environment(\._toolbarUpdateContext, Optional<Toolbar.UpdateContext>.none)
            .modifier(ToolbarFilterModifier(predicate: .keyPath(\ToolbarItemPlacement.Role.isModalAction)))
            .transformPreference(SearchContentKey.self) { value in
                value = nil
            }
        }

        @ViewBuilder
        private func modalToolbar(_ storage: ToolbarStorage) -> some View {
            let modalStorage = modalOnlyStorage(storage)
            if !modalStorage.items.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    ModalButtonRow(storage: modalStorage)
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                .frame(maxWidth: .infinity)
                .platformGroupFocusSection()
            } else {
                EmptyView()
            }
        }

        private func modalOnlyStorage(_ storage: ToolbarStorage) -> ToolbarStorage {
            var copy = storage
            copy.items = storage.items.filter { $0.placement.isModalAction }
            return copy
        }
    }

    struct ForceBody: View {
        var content: _ViewModifier_Content<SheetToolbarModifier>

        var body: some View {
            _VariadicView.Tree(_LayoutRoot(SheetContentRoot(_VStackLayout()))) {
                _UnaryViewAdaptor(content)
                EmptyView()
            }
            .modifier(ToolbarFilterModifier(predicate: .keyPath(\ToolbarItemPlacement.Role.isModalAction)))
        }
    }

    // ModalButtonRow stores the current toolbar storage.
    struct ModalButtonRow: View {
        var storage: ToolbarStorage

        var confirmation: IDView<ToolbarStoredItemView, ToolbarStorage.ID>? {
            firstView(in: .confirmationAction)
        }

        var leadingItems: [ToolbarStorage.Item] {
            storage.toolbarItems(in: .destructiveAction)
        }

        func firstView(in role: ToolbarItemPlacement.Role) -> IDView<ToolbarStoredItemView, ToolbarStorage.ID>? {
            guard let item = storage.toolbarItems(in: role).first else { return nil }
            return IDView(ToolbarStoredItemView(item: item), id: item.id)
        }

        var body: some View {
            _VariadicView.Tree(_LayoutRoot(DialogBottomButtonsHLayout(leadingCount: leadingItems.count))) {
                ForEach(leadingItems) { item in
                    ToolbarStoredItemView(item: item)
                        .buttonStyle(SheetToolbarButtonStyle(placement: item.placement))
                }
                firstView(in: .cancellationAction)?
                    .buttonStyle(SheetToolbarButtonStyle(placement: .cancellationAction))
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.cancelAction)
                confirmation?
                    .buttonStyle(SheetToolbarButtonStyle(placement: .confirmationAction))
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.defaultAction)
            }
        }
    }
}

// Local sheet modal action button style. The exact platform
// button bridge remains a boundary, but role-specific treatment is encoded here.
private struct SheetToolbarButtonStyle: PrimitiveButtonStyle {
    var placement: ToolbarItemPlacement.Role

    func makeBody(configuration: Configuration) -> some View {
        SheetToolbarButtonBody(configuration: configuration, placement: placement)
    }
}

private struct SheetToolbarButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let placement: ToolbarItemPlacement.Role
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
        .frame(minWidth: 76, minHeight: 32)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(background)
            RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: borderWidth)
        }
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }

    private var foreground: Color {
        if placement.isConfirmationAction { return .white }
        if placement.isDestructiveAction { return Color(red: 1.0, green: 0.12, blue: 0.16) }
        return .black
    }

    private var background: Color {
        if placement.isConfirmationAction {
            return isPressed
                ? Color(red: 0.0, green: 0.36, blue: 0.86)
                : Color(red: 0.0, green: 0.47, blue: 1.0)
        }
        if placement.isDestructiveAction {
            return isPressed
                ? Color(red: 1.0, green: 0.62, blue: 0.64)
                : Color(red: 1.0, green: 0.76, blue: 0.78)
        }
        return Color(white: isPressed ? 0.86 : 0.96)
    }

    private var border: Color {
        if placement.isConfirmationAction { return .clear }
        if placement.isCancellationAction { return Color(red: 0.42, green: 0.62, blue: 0.95) }
        if placement.isDestructiveAction { return .clear }
        return Color(white: 0.64)
    }

    private var borderWidth: CGFloat {
        placement.isCancellationAction ? 2 : 1
    }
}

// Toolbar entry bridge for the current preference path:
// prefer the original unary generator so Button's StaticSourceWriter label
// source remains attached. Keep AnyView as a fallback for erased items.
struct ToolbarStoredItemView: View {
    var item: ToolbarStorage.Item

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let item = view._attribute.value.item
        if let generator = item.generator,
           let outputs = generator.makeView(inputs: inputs) {
            return outputs
        }
        return AnyView._makeView(view: view[\.item.view], inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToolbarStoredItemView: PrimitiveView {}
