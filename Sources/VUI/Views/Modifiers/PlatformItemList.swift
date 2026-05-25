//
//  File: PlatformItemList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - PlatformItemListFlags
// Controls which platform item types PlatformItemListGenerator collects from the content view.
protocol PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { get }
    // Text/Label become disabled platform items in menu item-list collection.
    static var collectsStaticItemContributors: Bool { get }
}

extension PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { false }
    static var collectsStaticItemContributors: Bool { false }
}

// Used for alert/context-menu actions: collects all item types.
struct AllPlatformItemListFlags: PlatformItemListFlags {
    // Materialize Button values as platform items.
    static var installsPlatformItemButtonStyle: Bool { true }
    static var collectsStaticItemContributors: Bool { true }
}

// Used for alert message: collects text items only.
struct TextPlatformItemListFlags: PlatformItemListFlags {
    static var collectsStaticItemContributors: Bool { true }
}

// Used by PlatformItemListMenuStyle / View.platformItemChildren for nested Menu content.
struct SelectionPlatformItemListFlags: PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { true }
    static var collectsStaticItemContributors: Bool { true }
}

struct PlatformItemListCollectionOptions: ViewInput {
    struct Value: Equatable {
        var collectsStaticItemContributors: Bool = false
        var suppressesContributors: Bool = false
    }

    static var defaultValue: Value { Value() }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { a == b }
}

func platformItemListShouldCollectStaticItemContributors(_ inputs: _ViewInputs) -> Bool {
    guard inputs.preferences.keys.contains(PlatformItemList.Key.self) else {
        return false
    }
    let options = inputs[PlatformItemListCollectionOptions.self]
    return options.collectsStaticItemContributors && !options.suppressesContributors
}

func platformItemListRenderOnlyInputs(_ inputs: _ViewInputs) -> _ViewInputs {
    var inputs = inputs
    var options = inputs[PlatformItemListCollectionOptions.self]
    options.suppressesContributors = true
    inputs[PlatformItemListCollectionOptions.self] = options
    return inputs
}

// MARK: - PlatformItemListGenerator
// Creates a subgraph for Content._makeView and collects PlatformItemList.Key preferences.
struct PlatformItemListGenerator<Flags: PlatformItemListFlags, Content: View>: StatefulRule {
    typealias Value = PlatformItemList

    // PlatformItemList.Key preference attributes from Content._makeView subgraph.
    // Dynamic menu content can remove branch subgraphs while an open menu is
    // refreshing. Keep weak AG references so removed branch preference nodes are
    // ignored instead of being read after their slots are freed.
    let preferenceNodes: [WeakAttribute<PlatformItemList>]
    // Cached item list from the most recent update.
    var itemList: Optional<PlatformItemList>

    init(content: Attribute<Content>, inputs: _ViewInputs, inputsIncludeGeometry: Bool) {
        guard let graph = AttributeGraph.current else {
            fatalError("PlatformItemListGenerator.init called outside AG context")
        }
        var itemInputs = inputs
        var keys = itemInputs.preferences.keys
        keys.insert(PlatformItemList.Key.self)
        itemInputs.preferences = PreferencesInputs(keys: keys,
                                                   hostKeys: itemInputs.preferences.hostKeys)
        itemInputs[PlatformItemListCollectionOptions.self] =
            PlatformItemListCollectionOptions.Value(
                collectsStaticItemContributors: Flags.collectsStaticItemContributors
            )
        // Request divider entries as platform item-list system items.
        itemInputs.requestedDividerRepresentation = PlatformItemListDividerRepresentable.self
        if Flags.installsPlatformItemButtonStyle {
            let styleAttr: Attribute<ButtonStyleModifier<PlatformItemListButtonStyle>> = graph.makeRule {
                ButtonStyleModifier(style: PlatformItemListButtonStyle())
            }
            let style = AnyStyleModifier(value: styleAttr.identifier,
                                         _type: StyleModifierType<ButtonStyleModifier<PlatformItemListButtonStyle>>.self)
            var stack = itemInputs.base.customInputs.value(
                forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)
            stack = .node(style, stack)
            itemInputs.base.customInputs.setValue(stack,
                                                  forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)
            // Platform item generation materializes nested Menu values through
            // PlatformItemListMenuStyle, preserving submenu children and primary action.
            itemInputs.base.customInputs.setValue(PlatformItemListMenuStyle(),
                                                  forKey: _MenuStyleKey.self)
        }
        let view = _GraphValue<Content>(_attribute: content)
        let outputs = Content._makeView(view: view, inputs: itemInputs)
        self.preferenceNodes = outputs.preferences
            .values(for: PlatformItemList.Key.self)
            .map { Attribute<PlatformItemList>($0).asWeak() }
        self.itemList = nil
    }

    // Explicit flags variant (used for TextPlatformItemListFlags message path).
    init(flags: Flags.Type, content: Attribute<Content>, inputs: _ViewInputs,
         inputsIncludeGeometry: Bool) {
        self.init(content: content, inputs: inputs, inputsIncludeGeometry: inputsIncludeGeometry)
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("PlatformItemListGenerator.updateValue called outside AG context")
        }
        var combined = PlatformItemList()
        for node in preferenceNodes where node.isValid(in: graph) {
            combined.merge(node.toStrong().value)
        }
        itemList = combined
        AttributeGraph.setStatefulOutput(combined)
    }
}

// MARK: - PlatformItemList

// PlatformItemList shared by alert, confirmationDialog, contextMenu, and Menu.
struct PlatformItemList {
    // Open-menu refresh updates existing platform items in place, so collected rows
    // need producer-stable identity instead of a fresh UUID on every evaluation.
    struct StableIdentity: Hashable {
        var source: UInt32
        var slot: Int
    }

    struct Item: Identifiable {
        enum SystemItem: Int, Sendable {
            case divider = 3
        }

        var id: AnyHashable
        var label: AnyView
        var image: AnyView?
        var action: (() -> Void)?
        var role: ButtonRole?
        var keyboardShortcut: KeyboardShortcut?
        var isEnabled: Bool
        var systemItem: SystemItem?
        var children: [Item]
        var selectionBehavior: SelectionBehavior?
        var secondaryNavigationBehavior: SecondaryNavigationBehavior?
        var presentationRole: PresentationRole?

        enum SelectionBehavior: Sendable {
            case none
            case toggle(Bool)
        }

        enum SecondaryNavigationBehavior: Sendable {
            case none
            case submenu
        }

        // Titled Section materializes a header-like nil-action row between separators.
        enum PresentationRole: Sendable {
            case sectionHeader
        }

        init(id: AnyHashable = UUID(),
             label: AnyView,
             image: AnyView? = nil,
             action: (() -> Void)?,
             role: ButtonRole?,
             keyboardShortcut: KeyboardShortcut? = nil,
             isEnabled: Bool = true,
             systemItem: SystemItem? = nil,
             children: [Item] = [],
             selectionBehavior: SelectionBehavior? = nil,
             secondaryNavigationBehavior: SecondaryNavigationBehavior? = nil,
             presentationRole: PresentationRole? = nil) {
            self.id = id
            self.label = label
            self.image = image
            self.action = action
            self.role = role
            self.keyboardShortcut = keyboardShortcut
            self.isEnabled = isEnabled
            self.systemItem = systemItem
            self.children = children
            self.selectionBehavior = selectionBehavior
            self.secondaryNavigationBehavior = secondaryNavigationBehavior
            self.presentationRole = presentationRole
        }

        init(systemItem: SystemItem) {
            self.init(label: AnyView(EmptyView()),
                      action: nil,
                      role: nil,
                      systemItem: systemItem)
        }
    }

    private var items: [Item] = []
    var textFieldItems: [AnyView] = []

    var flattenedItems: [Item] { items }
    var buttonItems: [Item] { items.filter { $0.systemItem == nil } }
    var menuItems: [Item] { items }
    var mergedContentItem: Item? { items.first }

    static func stableID(_ source: AGAttribute, slot: Int = 0) -> AnyHashable {
        AnyHashable(StableIdentity(source: source.rawValue, slot: slot))
    }

    mutating func append(_ item: Item) {
        items.append(item)
    }

    mutating func merge(_ other: PlatformItemList) {
        items.append(contentsOf: other.items)
        textFieldItems.append(contentsOf: other.textFieldItems)
    }

    mutating func modify(_ transform: (inout Item) -> Void) {
        for index in items.indices {
            transform(&items[index])
        }
    }

    struct Key: PreferenceKey {
        typealias Value = PlatformItemList
        static var defaultValue: PlatformItemList { PlatformItemList() }

        static func reduce(value: inout PlatformItemList, nextValue: () -> PlatformItemList) {
            value.merge(nextValue())
        }
    }
}
