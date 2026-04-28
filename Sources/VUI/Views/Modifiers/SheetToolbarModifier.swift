//
//  File: SheetToolbarModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Toolbar support primitives

// Roles used by toolbar items and modal button placement.
// Raw values are internal assignments.
public struct ToolbarItemPlacement: Equatable, Hashable, Sendable {
    struct Role: RawRepresentable, Equatable, Hashable, Sendable {
        var rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let automatic          = Role(rawValue: 255)
        static let destructiveAction  = Role(rawValue: 0)   // leading slot in dialog
        static let cancellationAction = Role(rawValue: 1)
        static let confirmation       = Role(rawValue: 2)   // internal alias
        static let confirmationAction = Role(rawValue: 5)
        static let principal          = Role(rawValue: 10)
        static let navigation         = Role(rawValue: 11)
        static let keyboard           = Role(rawValue: 12)

        // Convenience predicates used by ModalButtonRow and ToolbarFilterModifier.
        var isDestructiveAction: Bool { self == .destructiveAction }
        var isCancellationAction: Bool { self == .cancellationAction }
        var isConfirmationAction: Bool { self == .confirmationAction || self == .confirmation }
        var isModalAction: Bool { isDestructiveAction || isCancellationAction || isConfirmationAction }
    }

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

// Minimal KeyboardShortcut representation used by the sheet modal button row trait.
struct KeyboardShortcut: Equatable, Hashable {
    enum Special: Equatable, Hashable {
        case cancelAction
        case defaultAction
    }

    var key: String?
    var special: Special?

    static let cancelAction = KeyboardShortcut(key: nil, special: .cancelAction)
    static let defaultAction = KeyboardShortcut(key: nil, special: .defaultAction)
}

struct KeyboardShortcutPickerOptionTraitKey: _ViewTraitKey {
    typealias Value = KeyboardShortcut?
    static var defaultValue: KeyboardShortcut? { nil }
}

// Toolbar storage for items rendered by the sheet toolbar path.
// It keeps identity, role placement, and a view payload for ModalButtonRow rendering.
struct ToolbarStorage {
    struct ID: Hashable {
        var rawValue: AnyHashable
        init(_ rawValue: AnyHashable) { self.rawValue = rawValue }
    }

    struct Item: Identifiable {
        var id: ID
        var placement: ToolbarItemPlacement.Role
        var view: AnyView

        init(id: ID, placement: ToolbarItemPlacement.Role, view: AnyView) {
            self.id = id
            self.placement = placement
            self.view = view
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

// Internal preference key for toolbar storage.
struct ToolbarKey: PreferenceKey {
    typealias Value = ToolbarStorage
    static var defaultValue: ToolbarStorage { ToolbarStorage() }

    static func reduce(value: inout ToolbarStorage, nextValue: () -> ToolbarStorage) {
        value.merge(nextValue())
    }
}

// MARK: - ToolbarContent protocol

// ToolbarContent items are currently collected via View._makeView + ToolbarKey preferences.
public protocol ToolbarContent {
    // TODO: add a dedicated toolbar-output path.
}

// MARK: - ToolbarDefaultItemKind

// Placeholder for default toolbar item kinds.
public struct ToolbarDefaultItemKind: Equatable, Sendable {
    var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

// MARK: - ToolbarItem

// Toolbar item content. Also conforms to View until the dedicated ToolbarContent
// materialization path is implemented.
public struct _ToolbarItemDefaultID: Hashable, Sendable {
    public init() {}
}

public struct ToolbarItem<ID: Hashable, Content: View>: View, ToolbarContent, Identifiable {
    public var id: ID { identifier }

    var identifier: ID
    var placement: ToolbarItemPlacement
    var content: Content
    var showsByDefault: Bool
    var isEmpty: Bool
    var defaultItemKind: ToolbarDefaultItemKind?

    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ToolbarItem._makeView called outside AG context")
        }
        let storageAttr: Attribute<ToolbarStorage> = graph.makeRule {
            let item = view._attribute.value
            guard !item.isEmpty else { return ToolbarStorage() }
            var storage = ToolbarStorage()
            storage.items.append(ToolbarStorage.Item(
                id: ToolbarStorage.ID(AnyHashable(item.identifier)),
                placement: item.placement.role,
                view: AnyView(item.content)
            ))
            return storage
        }
        var outputs = _ViewOutputs()
        outputs.preferences.append(ToolbarKey.self, node: storageAttr.identifier)
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToolbarItem: _PrimitiveView {}

extension ToolbarItem where ID == _ToolbarItemDefaultID {
    public init(placement: ToolbarItemPlacement = .automatic,
                showsByDefault: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.identifier = _ToolbarItemDefaultID()
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
// Uses TupleView-style field reflection to find View-typed fields in C.
// TupleToolbarContent is public because result-builder output types are part of
// the source-level API surface.
public struct TupleToolbarContent<C>: View, ToolbarContent {
    public var value: C
    public init(_ value: C) { self.value = value }

    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("TupleToolbarContent._makeView called outside AG context")
        }
        var allOutputs: [_ViewOutputs] = []
        func makeChild<V: View>(_: V.Type, offset: Int) {
            let childAttr: Attribute<V> = graph.makeRule {
                withUnsafeBytes(of: view._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: V.self).pointee
                }
            }
            allOutputs.append(V._makeView(view: _GraphValue(_attribute: childAttr), inputs: inputs))
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let vt = fieldType as? any View.Type {
                func open<V: View>(_: V.Type) { makeChild(V.self, offset: offset) }
                _openExistential(vt, do: open)
            }
            return true
        }
        if allOutputs.isEmpty { return _ViewOutputs() }
        var merged = allOutputs[0]
        for i in 1..<allOutputs.count {
            merged.preferences = PreferencesOutputs.merge(
                [merged.preferences, allOutputs[i].preferences], in: graph)
        }
        return merged
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("TupleToolbarContent._makeViewList called outside AG context")
        }
        var children: [_ViewListOutputs] = []
        func makeChild<V: View>(_: V.Type, offset: Int) {
            let childAttr: Attribute<V> = graph.makeRule {
                withUnsafeBytes(of: view._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: V.self).pointee
                }
            }
            children.append(V._makeViewList(view: _GraphValue(_attribute: childAttr), inputs: inputs))
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let vt = fieldType as? any View.Type {
                func open<V: View>(_: V.Type) { makeChild(V.self, offset: offset) }
                _openExistential(vt, do: open)
            }
            return true
        }
        let count = children.count
        return _ViewListOutputs(
            views: .staticList(.merged(children)),
            nextImplicitID: count,
            staticCount: count
        )
    }
}

extension TupleToolbarContent: _PrimitiveView {}

// MARK: - ToolbarContentBuilder

// Builds TupleToolbarContent values for one or more toolbar items.
// buildBlock methods are @inlinable so TupleToolbarContent is usable at call sites.
@resultBuilder
public struct ToolbarContentBuilder {
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

extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {}

// MARK: - ToolbarItemGroup

// Toolbar item group with placement, content, and an empty-state flag.
public struct ToolbarItemGroup<Content: View>: View, ToolbarContent {
    public typealias Body = Never

    var placement: ToolbarItemPlacement
    var content: Content
    var isEmpty: Bool

    public init(placement: ToolbarItemPlacement = .automatic,
                @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
        self.isEmpty = false
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ToolbarItemGroup._makeView called outside AG context")
        }
        let storageAttr: Attribute<ToolbarStorage> = graph.makeRule {
            let group = view._attribute.value
            guard !group.isEmpty else { return ToolbarStorage() }
            var storage = ToolbarStorage()
            // ToolbarItemGroup uses placement.role. Use a stable hash for identity.
            let id = ToolbarStorage.ID(AnyHashable(ObjectIdentifier(Content.self)))
            storage.items.append(ToolbarStorage.Item(
                id: id,
                placement: group.placement.role,
                view: AnyView(group.content)
            ))
            return storage
        }
        var outputs = _ViewOutputs()
        outputs.preferences.append(ToolbarKey.self, node: storageAttr.identifier)
        return outputs
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToolbarItemGroup: _PrimitiveView {}

// MARK: - EmptyToolbarContent

// EmptyToolbarContent: ToolbarContent and CustomizableToolbarContent conformance.
// Produces no toolbar items.
public struct EmptyToolbarContent: View, ToolbarContent {
    public typealias Body = Never

    public init() {}

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs()
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
    }
}

extension EmptyToolbarContent: _PrimitiveView {}

// MARK: - ToolbarModifier

// Modifier that materializes toolbar content and merges ToolbarKey preferences.
// TODO: Move this to a dedicated toolbar-output path.
struct ToolbarModifier<CustomizationID, Content: ToolbarContent & View>: ViewModifier {
    typealias Body = Never

    var id: String?
    var content: Content
    // Selection is reserved for tab and picker integration.
    var selection: Binding<Int>?

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ToolbarModifier._makeView called outside AG context")
        }
        var outputs = body(_Graph(), inputs)

        var toolbarInputs = inputs
        var keys = toolbarInputs.preferences.keys
        keys.insert(ToolbarKey.self)
        toolbarInputs.preferences = PreferencesInputs(keys: keys,
                                                       hostKeys: toolbarInputs.preferences.hostKeys)
        let toolbarOutputs = Content._makeView(
            view: modifier[\.content],
            inputs: toolbarInputs
        )
        outputs.preferences = PreferencesOutputs.merge(
            [outputs.preferences, toolbarOutputs.preferences],
            in: graph
        )
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

extension View {
    // Requires Content to also conform to View until toolbar content has a dedicated output path.
    public func toolbar<Content: ToolbarContent & View>(
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
    static var defaultValue: Bool { false }
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

// Primitive reader payload for ToolbarReader.
// Only storage is needed for ModalButtonRow.
struct ToolbarPrimitiveReader {
    var storage: ToolbarStorage
}

// Cycle-free design:
// - primitiveReaderAttr is an AG *input* node, not a rule.
// - bodyAttr depends on primitiveReaderAttr (input), not on storageAttr.
// - An update rule reads storageAttr and calls primitiveReaderAttr.setValue when
//   the item IDs change, converging after at most two AG evaluation passes.
struct ToolbarReader<Edges, Content: View>: View {
    typealias Body = Never
    typealias PrimitiveReader = ToolbarPrimitiveReader

    var content: (ToolbarPrimitiveReader) -> Content

    init(_ edges: Edges.Type = Edges.self, @ViewBuilder content: @escaping (ToolbarPrimitiveReader) -> Content) {
        self.content = content
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
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
        keys.insert(ToolbarKey.self)
        keys.insert(SearchContentKey.self)
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
        let _ = graph.makeRule {
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

extension ToolbarReader: _PrimitiveView {}

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
        guard let graph = AttributeGraph.current else {
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
            let toolbar = subviews[1].sizeThatFits(.zero)
            return CGSize(width: max(content.width, toolbar.width),
                          height: content.height + toolbar.height)
        case 3:
            let search = subviews[0].sizeThatFits(.zero)
            let content = subviews[1].sizeThatFits(proposal)
            let toolbar = subviews[2].sizeThatFits(.zero)
            return CGSize(width: max(search.width, max(content.width, toolbar.width)),
                          height: search.height + content.height + toolbar.height)
        default:
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout L.Cache) {
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
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

// Layout for modal sheet bottom buttons. The exact baseline math is still a
// follow-up item; this places leading content at the leading edge and action
// buttons from the trailing edge.
struct DialogBottomButtonsHLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData

    enum ButtonPlacement: UInt8, LayoutValueKey {
        case leading = 0
        case cancel = 1
        case confirmation = 2

        static var defaultValue: ButtonPlacement { .leading }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            width += size.width
            height = max(height, size.height)
        }
        if subviews.count > 1 { width += CGFloat(subviews.count - 1) * ViewSpacing.defaultSpacing }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var leadingX = bounds.minX
        var trailingX = bounds.maxX
        let midY = bounds.midY

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            switch subview[ButtonPlacement.self] {
            case .leading:
                subview.place(at: CGPoint(x: leadingX, y: midY),
                              anchor: .leading,
                              proposal: ProposedViewSize(size))
                leadingX += size.width + ViewSpacing.defaultSpacing
            case .cancel, .confirmation:
                trailingX -= size.width
                subview.place(at: CGPoint(x: trailingX, y: midY),
                              anchor: .leading,
                              proposal: ProposedViewSize(size))
                trailingX -= ViewSpacing.defaultSpacing
            }
        }
    }
}

// MARK: - ContainerBackgroundKeys

// ContainerBackgroundKeys: namespace for container background preference keys.
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
    // Currently a no-op passthrough.
    func renderContainerBackgroundInHostingView<K: PreferenceKey>(_ keyType: K.Type) -> some View {
        self
    }
}

// MARK: - SidebarState

// SidebarState: 1-byte enum/struct controlling sidebar visibility in sheets.
// Used by SheetContent.FixedSidebarModifier to write a fixed Binding<SidebarState>.
// rawValue 2 is written as the constant value (Binding.constant(SidebarState(rawValue: 2))).
// Specific named cases can be added when more sidebar states are supported.
struct SidebarState: RawRepresentable, Equatable {
    var rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
}

// Private env key for Optional<Binding<SidebarState>>.
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
struct SheetToolbarModifier: ViewModifier {
    func body(content: _ViewModifier_Content<SheetToolbarModifier>) -> some View {
        StaticIf<_SemanticFeature<Semantics_v6>, ReaderBody, ForceBody>(
            trueBody: ReaderBody(content: content),
            falseBody: ForceBody(content: content)
        )
    }

    // ReaderBody feeds toolbar storage into the modal toolbar row.
    struct ReaderBody: View {
        var content: _ViewModifier_Content<SheetToolbarModifier>

        var body: some View {
            ToolbarReader(AllToolbarEdges.self) { reader in
                _VariadicView.Tree(_LayoutRoot(SheetContentRoot(_VStackLayout()))) {
                    content
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
                }
                .fixedSize()
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
                content
                EmptyView()
            }
            .modifier(ToolbarFilterModifier(predicate: .keyPath(\ToolbarItemPlacement.Role.isModalAction)))
        }
    }

    struct ModalButtonRow: View {
        var storage: ToolbarStorage

        var confirmation: IDView<AnyView, ToolbarStorage.ID>? {
            firstView(in: .confirmationAction)
        }

        var leadingItems: [ToolbarStorage.Item] {
            storage.toolbarItems(in: .destructiveAction)
        }

        func firstView(in role: ToolbarItemPlacement.Role) -> IDView<AnyView, ToolbarStorage.ID>? {
            guard let item = storage.toolbarItems(in: role).first else { return nil }
            return IDView(item.view, id: item.id)
        }

        var body: some View {
            _VariadicView.Tree(_LayoutRoot(DialogBottomButtonsHLayout())) {
                ForEach(leadingItems) { item in
                    item.view
                        .layoutValue(key: DialogBottomButtonsHLayout.ButtonPlacement.self, value: .leading)
                }
                firstView(in: .cancellationAction)?
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.cancelAction)
                    .layoutValue(key: DialogBottomButtonsHLayout.ButtonPlacement.self, value: .cancel)
                confirmation?
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.defaultAction)
                    .layoutValue(key: DialogBottomButtonsHLayout.ButtonPlacement.self, value: .confirmation)
            }
        }
    }
}
