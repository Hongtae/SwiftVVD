//
//  File: KeyboardShortcut.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct EventModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let capsLock = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let control = EventModifiers(rawValue: 1 << 2)
    public static let option = EventModifiers(rawValue: 1 << 3)
    public static let command = EventModifiers(rawValue: 1 << 4)
    public static let numericPad = EventModifiers(rawValue: 1 << 5)
    public static let function = EventModifiers(rawValue: 1 << 6)
    public static let all: EventModifiers = [
        .capsLock, .shift, .control, .option, .command, .numericPad, .function
    ]
}

public struct KeyEquivalent: Sendable, Hashable {
    public var character: Character

    public init(_ character: Character) {
        self.character = character
    }

    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let delete = KeyEquivalent("\u{7F}")
    public static let deleteForward = KeyEquivalent("\u{F728}")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
    public static let clear = KeyEquivalent("\u{F739}")
    public static let tab = KeyEquivalent("\t")
    public static let space = KeyEquivalent(" ")
    public static let `return` = KeyEquivalent("\r")
}

extension KeyEquivalent: ExpressibleByExtendedGraphemeClusterLiteral {
    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }
}

extension KeyEquivalent: ExpressibleByUnicodeScalarLiteral {
    public init(unicodeScalarLiteral value: Character) {
        self.init(value)
    }
}

public struct KeyboardShortcut: Sendable, Hashable {
    public struct Localization: Sendable, Hashable {
        enum Style: Sendable, Hashable {
            case automatic
            case withoutMirroring
            case custom
        }

        let style: Style

        public static let automatic = Localization(style: .automatic)
        public static let withoutMirroring = Localization(style: .withoutMirroring)
        public static let custom = Localization(style: .custom)
    }

    enum Special: Sendable, Hashable {
        case cancelAction
        case defaultAction
    }

    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public var localization: Localization
    var special: Special?

    public static let defaultAction = KeyboardShortcut(
        .return,
        modifiers: [],
        localization: .automatic,
        special: .defaultAction
    )
    public static let cancelAction = KeyboardShortcut(
        .escape,
        modifiers: [],
        localization: .automatic,
        special: .cancelAction
    )

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.init(key, modifiers: modifiers, localization: .automatic)
    }

    public init(_ key: KeyEquivalent,
                modifiers: EventModifiers = .command,
                localization: KeyboardShortcut.Localization) {
        self.init(key, modifiers: modifiers, localization: localization, special: nil)
    }

    init(_ key: KeyEquivalent,
         modifiers: EventModifiers,
         localization: KeyboardShortcut.Localization,
         special: Special?) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
        self.special = special
    }

    var displayLabel: String {
        switch special {
        case .cancelAction?:
            return "Cancel"
        case .defaultAction?:
            return "Default"
        case nil:
            var parts: [String] = []
            if modifiers.contains(.control) { parts.append("Ctrl") }
            if modifiers.contains(.option) { parts.append("Alt") }
            if modifiers.contains(.shift) { parts.append("Shift") }
            if modifiers.contains(.command) { parts.append("Cmd") }
            parts.append(String(key.character).uppercased())
            return parts.joined(separator: "+")
        }
    }
}

struct KeyboardShortcutKey: EnvironmentKey {
    static var defaultValue: KeyboardShortcut? { nil }
}

extension EnvironmentValues {
    public var keyboardShortcut: KeyboardShortcut? {
        get { self[KeyboardShortcutKey.self] }
        set { self[KeyboardShortcutKey.self] = newValue }
    }
}

struct HasKeyboardShortcut: ViewInputFlag {
    typealias Value = Bool
    static var defaultValue: Bool { false }
    var description: String { "HasKeyboardShortcut" }
}

// Stores the shortcut trait consumed by platform item collection.
struct KeyboardShortcutPickerOptionTraitKey: _ViewTraitKey {
    typealias Value = KeyboardShortcut?
    static var defaultValue: KeyboardShortcut? { nil }
}

extension View {
    public func keyboardShortcut(_ key: KeyEquivalent,
                                 modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }

    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(shortcut as KeyboardShortcut?)
    }

    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        environment(\.keyboardShortcut, shortcut)
            .modifier(ViewInputFlagModifier<HasKeyboardShortcut>(value: true))
            ._trait(KeyboardShortcutPickerOptionTraitKey.self, shortcut)
    }

    public func keyboardShortcut(_ key: KeyEquivalent,
                                 modifiers: EventModifiers = .command,
                                 localization: KeyboardShortcut.Localization) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
}
