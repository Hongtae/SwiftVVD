//
//  File: ToolbarContent.swift
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
// Local storage shared by the current sheet and renderer-owned root toolbar
// paths: identity, role placement, default visibility, and an erased view
// payload. The broader toolbar storage surface remains outside this subset.
struct ToolbarStorage {
    struct Configuration: Equatable {
        var customizationID: String?
    }

    struct ID: Hashable {
        var rawValue: AnyHashable
        init(_ rawValue: AnyHashable) { self.rawValue = rawValue }
    }

    struct Item: Identifiable {
        var id: ID
        var placement: ToolbarItemPlacement.Role
        var view: AnyView
        var showsByDefault: Bool
        // Keeps toolbar entry rendering on the original AG path so source aliases
        // such as PrimitiveButtonStyleConfiguration.Label remain connected.
        var generator: TypedUnaryViewGenerator?

        init(id: ID,
             placement: ToolbarItemPlacement.Role,
             view: AnyView,
             showsByDefault: Bool = true,
             generator: TypedUnaryViewGenerator? = nil) {
            self.id = id
            self.placement = placement
            self.view = view
            self.showsByDefault = showsByDefault
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
    var configuration: Configuration? = nil

    mutating func merge(_ other: ToolbarStorage) {
        items.append(contentsOf: other.items)
        if searchItem == nil { searchItem = other.searchItem }
        if let configuration = other.configuration {
            self.configuration = configuration
        }
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

func mergeToolbarOutputs(
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

func toolbarIdentifier<ID>(_ value: ID) -> AnyHashable {
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
