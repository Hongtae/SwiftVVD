//
//  File: KeyboardShortcut.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

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

extension KeyEquivalent {
    init?(platformEvent event: VVD.KeyboardEvent) {
        if let character = event.text.first ?? event.key.shortcutCharacter {
            self.init(character)
            return
        }
        self.init(virtualKey: event.key)
    }

    init?(virtualKey: VVD.VirtualKey) {
        if let character = virtualKey.shortcutCharacter {
            self.init(character)
            return
        }
        switch virtualKey {
        case .escape: self = .escape
        case .f1: self.init("\u{F704}")
        case .f2: self.init("\u{F705}")
        case .f3: self.init("\u{F706}")
        case .f4: self.init("\u{F707}")
        case .f5: self.init("\u{F708}")
        case .f6: self.init("\u{F709}")
        case .f7: self.init("\u{F70A}")
        case .f8: self.init("\u{F70B}")
        case .f9: self.init("\u{F70C}")
        case .f10: self.init("\u{F70D}")
        case .f11: self.init("\u{F70E}")
        case .f12: self.init("\u{F70F}")
        case .f13: self.init("\u{F710}")
        case .f14: self.init("\u{F711}")
        case .f15: self.init("\u{F712}")
        case .f16: self.init("\u{F713}")
        case .f17: self.init("\u{F714}")
        case .f18: self.init("\u{F715}")
        case .f19: self.init("\u{F716}")
        case .f20: self.init("\u{F717}")
        case .insert: self.init("\u{F727}")
        case .home: self = .home
        case .pageUp: self = .pageUp
        case .pageDown: self = .pageDown
        case .end: self = .end
        case .delete: self = .deleteForward
        case .left: self = .leftArrow
        case .right: self = .rightArrow
        case .up: self = .upArrow
        case .down: self = .downArrow
        case .backspace: self = .delete
        case .tab: self = .tab
        case .space: self = .space
        case .return, .enter: self = .return
        case .numlock: self = .clear
        default: return nil
        }
    }
}

extension EventModifiers {
    init(platformFlags flags: VVD.KeyboardModifierFlags) {
        self = []
        if flags.contains(.capsLock) { insert(.capsLock) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.numericPad) { insert(.numericPad) }
        if flags.contains(.function) { insert(.function) }
    }
}

extension VVD.VirtualKey {
    var shortcutCharacter: Character? {
        switch self {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        case .i: return "i"
        case .j: return "j"
        case .k: return "k"
        case .l: return "l"
        case .m: return "m"
        case .n: return "n"
        case .o: return "o"
        case .p: return "p"
        case .q: return "q"
        case .r: return "r"
        case .s: return "s"
        case .t: return "t"
        case .u: return "u"
        case .v: return "v"
        case .w: return "w"
        case .x: return "x"
        case .y: return "y"
        case .z: return "z"
        case .num0, .pad0: return "0"
        case .num1, .pad1: return "1"
        case .num2, .pad2: return "2"
        case .num3, .pad3: return "3"
        case .num4, .pad4: return "4"
        case .num5, .pad5: return "5"
        case .num6, .pad6: return "6"
        case .num7, .pad7: return "7"
        case .num8, .pad8: return "8"
        case .num9, .pad9: return "9"
        case .period, .padPeriod: return "."
        case .comma: return ","
        case .slash, .padSlash: return "/"
        case .accentTilde: return "`"
        case .semicolon: return ";"
        case .quote: return "'"
        case .backslash: return "\\"
        case .equal, .padEqual: return "="
        case .hyphen, .padMinus: return "-"
        case .padAsterisk: return "*"
        case .padPlus: return "+"
        case .openBracket: return "["
        case .closeBracket: return "]"
        default: return nil
        }
    }
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

struct HasKeyboardShortcut: ViewInputBoolFlag {}

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
            .modifier(ViewInputFlagModifier(flag: HasKeyboardShortcut()))
            ._trait(KeyboardShortcutPickerOptionTraitKey.self, shortcut)
    }

    public func keyboardShortcut(_ key: KeyEquivalent,
                                 modifiers: EventModifiers = .command,
                                 localization: KeyboardShortcut.Localization) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
}
