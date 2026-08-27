//
//  File: WindowMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A platform-neutral snapshot of the system menu associated with a window.
///
/// System menu backends replace the complete snapshot atomically. This keeps
/// ownership of platform menu handles and action callbacks inside the backend
/// instead of exposing incremental native mutations to callers.
public struct WindowMenu {
    public typealias ID = String
    public typealias Action = @MainActor () -> Void

    /// A semantic role used by platforms that expose special menu locations.
    public enum Role: Sendable, Hashable {
        case application
        case file
        case edit
        case format
        case view
        case window
        case help
        case services
        case custom
    }

    public enum State: Sendable, Hashable {
        case off
        case on
        case mixed
    }

    public struct Shortcut: Sendable, Hashable {
        public enum Key: Sendable, Hashable {
            case character(Character)
            case virtual(VirtualKey)
        }

        public var key: Key
        public var modifiers: KeyboardModifierFlags

        public init(
            _ key: Key,
            modifiers: KeyboardModifierFlags = [.command]
        ) {
            self.key = key
            self.modifiers = modifiers
        }

        public init(
            _ character: Character,
            modifiers: KeyboardModifierFlags = [.command]
        ) {
            self.init(.character(character), modifiers: modifiers)
        }

        public init(
            _ key: VirtualKey,
            modifiers: KeyboardModifierFlags = [.command]
        ) {
            self.init(.virtual(key), modifiers: modifiers)
        }
    }

    public struct Item {
        public var id: ID?
        public var title: String
        /// A mnemonic used by platforms with keyboard-access menu labels.
        public var accessKey: Character?
        public var image: Image?
        public var imageIsTemplate: Bool
        public var scalesImageToFit: Bool
        public var state: State
        public var isEnabled: Bool
        public var isHidden: Bool
        public var isAlternate: Bool
        public var indentationLevel: Int
        public var allowsShortcutWhenHidden: Bool
        public var shortcut: Shortcut?
        public var toolTip: String?
        public var action: Action?

        public init(
            id: ID? = nil,
            title: String,
            accessKey: Character? = nil,
            image: Image? = nil,
            imageIsTemplate: Bool = false,
            scalesImageToFit: Bool = true,
            state: State = .off,
            isEnabled: Bool = true,
            isHidden: Bool = false,
            isAlternate: Bool = false,
            indentationLevel: Int = 0,
            allowsShortcutWhenHidden: Bool = false,
            shortcut: Shortcut? = nil,
            toolTip: String? = nil,
            action: Action? = nil
        ) {
            self.id = id
            self.title = title
            self.accessKey = accessKey
            self.image = image
            self.imageIsTemplate = imageIsTemplate
            self.scalesImageToFit = scalesImageToFit
            self.state = state
            self.isEnabled = isEnabled
            self.isHidden = isHidden
            self.isAlternate = isAlternate
            self.indentationLevel = indentationLevel
            self.allowsShortcutWhenHidden = allowsShortcutWhenHidden
            self.shortcut = shortcut
            self.toolTip = toolTip
            self.action = action
        }

        public init(
            id: ID? = nil,
            title: String,
            accessKey: Character? = nil,
            image: Image? = nil,
            imageIsTemplate: Bool = false,
            scalesImageToFit: Bool = true,
            state: State = .off,
            isEnabled: Bool = true,
            isHidden: Bool = false,
            isAlternate: Bool = false,
            indentationLevel: Int = 0,
            allowsShortcutWhenHidden: Bool = false,
            shortcut: Shortcut? = nil,
            toolTip: String? = nil,
            action: @escaping Action
        ) {
            self.init(
                id: id,
                title: title,
                accessKey: accessKey,
                image: image,
                imageIsTemplate: imageIsTemplate,
                scalesImageToFit: scalesImageToFit,
                state: state,
                isEnabled: isEnabled,
                isHidden: isHidden,
                isAlternate: isAlternate,
                indentationLevel: indentationLevel,
                allowsShortcutWhenHidden: allowsShortcutWhenHidden,
                shortcut: shortcut,
                toolTip: toolTip,
                action: action as Action?
            )
        }
    }

    public indirect enum Element {
        case item(Item)
        case submenu(Menu)
        case separator
    }

    public struct Menu {
        public var id: ID?
        public var title: String
        public var role: Role
        /// A mnemonic used by platforms with keyboard-access menu labels.
        public var accessKey: Character?
        public var image: Image?
        public var imageIsTemplate: Bool
        public var scalesImageToFit: Bool
        public var isEnabled: Bool
        public var isHidden: Bool
        /// Lets a backend use its responder validation system for this menu.
        /// Backends without that facility continue to use explicit item state.
        public var usesPlatformItemValidation: Bool
        public var elements: [Element]

        public init(
            id: ID? = nil,
            title: String,
            role: Role = .custom,
            accessKey: Character? = nil,
            image: Image? = nil,
            imageIsTemplate: Bool = false,
            scalesImageToFit: Bool = true,
            isEnabled: Bool = true,
            isHidden: Bool = false,
            usesPlatformItemValidation: Bool = false,
            elements: [Element] = []
        ) {
            self.id = id
            self.title = title
            self.role = role
            self.accessKey = accessKey
            self.image = image
            self.imageIsTemplate = imageIsTemplate
            self.scalesImageToFit = scalesImageToFit
            self.isEnabled = isEnabled
            self.isHidden = isHidden
            self.usesPlatformItemValidation = usesPlatformItemValidation
            self.elements = elements
        }

        public init(
            id: ID? = nil,
            title: String,
            role: Role = .custom,
            accessKey: Character? = nil,
            image: Image? = nil,
            imageIsTemplate: Bool = false,
            scalesImageToFit: Bool = true,
            isEnabled: Bool = true,
            isHidden: Bool = false,
            usesPlatformItemValidation: Bool = false,
            @ElementsBuilder elements: () -> [Element]
        ) {
            self.init(
                id: id,
                title: title,
                role: role,
                accessKey: accessKey,
                image: image,
                imageIsTemplate: imageIsTemplate,
                scalesImageToFit: scalesImageToFit,
                isEnabled: isEnabled,
                isHidden: isHidden,
                usesPlatformItemValidation: usesPlatformItemValidation,
                elements: elements()
            )
        }
    }

    public var menus: [Menu]

    public init(menus: [Menu] = []) {
        self.menus = menus
    }

    public init(@MenusBuilder menus: () -> [Menu]) {
        self.menus = menus()
    }

    @resultBuilder
    public enum MenusBuilder {
        public static func buildExpression(_ expression: Menu) -> [Menu] {
            [expression]
        }

        public static func buildBlock(_ components: [Menu]...) -> [Menu] {
            components.flatMap { $0 }
        }

        public static func buildOptional(_ component: [Menu]?) -> [Menu] {
            component ?? []
        }

        public static func buildEither(first component: [Menu]) -> [Menu] {
            component
        }

        public static func buildEither(second component: [Menu]) -> [Menu] {
            component
        }

        public static func buildArray(_ components: [[Menu]]) -> [Menu] {
            components.flatMap { $0 }
        }
    }

    @resultBuilder
    public enum ElementsBuilder {
        public static func buildExpression(_ expression: Item) -> [Element] {
            [.item(expression)]
        }

        public static func buildExpression(_ expression: Menu) -> [Element] {
            [.submenu(expression)]
        }

        public static func buildExpression(
            _ expression: Element
        ) -> [Element] {
            [expression]
        }

        public static func buildBlock(_ components: [Element]...) -> [Element] {
            components.flatMap { $0 }
        }

        public static func buildOptional(
            _ component: [Element]?
        ) -> [Element] {
            component ?? []
        }

        public static func buildEither(
            first component: [Element]
        ) -> [Element] {
            component
        }

        public static func buildEither(
            second component: [Element]
        ) -> [Element] {
            component
        }

        public static func buildArray(
            _ components: [[Element]]
        ) -> [Element] {
            components.flatMap { $0 }
        }
    }
}

@MainActor
public protocol WindowMenuControllerDelegate: AnyObject {
    /// Requests a refreshed snapshot before a platform menu is displayed.
    func windowMenuController(
        _ controller: any WindowMenuController,
        needsUpdateMenu menuID: WindowMenu.ID?
    )
}

@MainActor
public protocol WindowMenuController: AnyObject {
    var delegate: (any WindowMenuControllerDelegate)? { get set }
    var menu: WindowMenu? { get }

    /// Replaces the complete platform menu, or detaches it when `menu` is nil.
    ///
    /// Controllers own all native handles and callback targets derived from the
    /// snapshot. Callers never mutate those platform objects incrementally.
    func setMenu(_ menu: WindowMenu?)
}
