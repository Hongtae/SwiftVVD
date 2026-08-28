//
//  File: ToolbarModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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
        guard let graph = _AGGraph.current else {
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
        let contentStorage = toolbarOutputs.storage.attribute
        let storage: Attribute<ToolbarStorage> = graph.makeRule {
            var storage = contentStorage?.value ?? ToolbarStorage()
            storage.configuration = ToolbarStorage.Configuration(
                customizationID: modifier._attribute.value.id
            )
            return storage
        }
        outputs.preferences.append(ToolbarKey.self, node: storage.identifier)
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

    public func toolbar<Content: CustomizableToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        modifier(
            ToolbarModifier<String, Content>(
                id: id,
                content: content(),
                selection: nil
            )
        )
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
