//
//  File: ToolbarItem.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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
