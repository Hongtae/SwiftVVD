//
//  File: KeyBindingPresets.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

/// A platform-neutral key and modifier combination used by key-binding files.
///
/// `KeyBinding` accepts either a ``VVD/VirtualKey`` or a literal `Character`.
/// Virtual keys are useful for letters, function keys, arrows, and navigation
/// keys. Literal characters preserve bindings such as `{`, `|`, and `}`.
public typealias KeyBinding = VVD.WindowMenu.Shortcut

private let keyBindingVirtualKeysByName: [String: VirtualKey] = [
    "none": .none,
    "escape": .escape,
    "f1": .f1, "f2": .f2, "f3": .f3, "f4": .f4,
    "f5": .f5, "f6": .f6, "f7": .f7, "f8": .f8,
    "f9": .f9, "f10": .f10, "f11": .f11, "f12": .f12,
    "f13": .f13, "f14": .f14, "f15": .f15, "f16": .f16,
    "f17": .f17, "f18": .f18, "f19": .f19, "f20": .f20,
    "num0": .num0, "num1": .num1, "num2": .num2,
    "num3": .num3, "num4": .num4, "num5": .num5,
    "num6": .num6, "num7": .num7, "num8": .num8,
    "num9": .num9,
    "a": .a, "b": .b, "c": .c, "d": .d, "e": .e,
    "f": .f, "g": .g, "h": .h, "i": .i, "j": .j,
    "k": .k, "l": .l, "m": .m, "n": .n, "o": .o,
    "p": .p, "q": .q, "r": .r, "s": .s, "t": .t,
    "u": .u, "v": .v, "w": .w, "x": .x, "y": .y,
    "z": .z,
    "period": .period,
    "comma": .comma,
    "slash": .slash,
    "tab": .tab,
    "accentTilde": .accentTilde,
    "backspace": .backspace,
    "semicolon": .semicolon,
    "quote": .quote,
    "backslash": .backslash,
    "equal": .equal,
    "hyphen": .hyphen,
    "space": .space,
    "openBracket": .openBracket,
    "closeBracket": .closeBracket,
    "capslock": .capslock,
    "return": .return,
    "fn": .fn,
    "insert": .insert,
    "home": .home,
    "pageUp": .pageUp,
    "pageDown": .pageDown,
    "end": .end,
    "delete": .delete,
    "left": .left,
    "right": .right,
    "up": .up,
    "down": .down,
    "leftShift": .leftShift,
    "rightShift": .rightShift,
    "leftOption": .leftOption,
    "rightOption": .rightOption,
    "leftControl": .leftControl,
    "rightControl": .rightControl,
    "leftCommand": .leftCommand,
    "rightCommand": .rightCommand,
    "pad0": .pad0, "pad1": .pad1, "pad2": .pad2,
    "pad3": .pad3, "pad4": .pad4, "pad5": .pad5,
    "pad6": .pad6, "pad7": .pad7, "pad8": .pad8,
    "pad9": .pad9,
    "enter": .enter,
    "numlock": .numlock,
    "padSlash": .padSlash,
    "padAsterisk": .padAsterisk,
    "padPlus": .padPlus,
    "padMinus": .padMinus,
    "padEqual": .padEqual,
    "padPeriod": .padPeriod,
]

private let keyBindingNamesByVirtualKey: [VirtualKey: String] = Dictionary(
    uniqueKeysWithValues: keyBindingVirtualKeysByName.map { name, key in
        (key, name)
    }
)

private extension VirtualKey {
    init?(keyBindingName: String) {
        guard let key = keyBindingVirtualKeysByName[keyBindingName] else {
            return nil
        }
        self = key
    }

    var keyBindingName: String? {
        keyBindingNamesByVirtualKey[self]
    }

    var keyBindingUsesNumericPad: Bool {
        switch self {
        case .pad0, .pad1, .pad2, .pad3, .pad4,
             .pad5, .pad6, .pad7, .pad8, .pad9,
             .enter, .numlock, .padSlash, .padAsterisk, .padPlus,
             .padMinus, .padEqual, .padPeriod:
            true
        default:
            false
        }
    }
}

/// Stable identifiers for framework-provided command shortcuts.
///
/// Application-defined `keyboardShortcut` values remain literal and do not
/// pass through this table.
public enum KeyBindingID: String, CaseIterable, Codable, Sendable {
    case pasteboardCut = "pasteboard.cut"
    case pasteboardCopy = "pasteboard.copy"
    case pasteboardPaste = "pasteboard.paste"
    case pasteboardSelectAll = "pasteboard.selectAll"
    case textEditingFind = "textEditing.find"
    case textEditingFindAndReplace = "textEditing.findAndReplace"
    case textEditingFindNext = "textEditing.findNext"
    case textEditingFindPrevious = "textEditing.findPrevious"
    case textEditingUseSelectionForFind = "textEditing.useSelectionForFind"
    case textEditingJumpToSelection = "textEditing.jumpToSelection"
    case textEditingShowSpellingAndGrammar =
        "textEditing.showSpellingAndGrammar"
    case textEditingCheckDocumentNow = "textEditing.checkDocumentNow"
    case textFormattingAlignLeft = "textFormatting.alignLeft"
    case textFormattingAlignCenter = "textFormatting.alignCenter"
    case textFormattingAlignRight = "textFormatting.alignRight"
    case textFormattingCopyRuler = "textFormatting.copyRuler"
    case textFormattingPasteRuler = "textFormatting.pasteRuler"
    case toolbarToggleVisibility = "toolbar.toggleVisibility"
    case sidebarToggle = "sidebar.toggle"
    case inspectorToggle = "inspector.toggle"
}

public enum KeyBindingPreset: String, CaseIterable, Codable, Sendable {
    case apple
    case windows
    case linux

    /// The fallback used only when an application has not selected a user
    /// key-binding file.
    public static var platformDefault: Self {
#if os(Windows)
        .windows
#elseif os(Linux) || os(Android)
        .linux
#else
        .apple
#endif
    }
}

public enum KeyBindingError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidPresets(missing: [String], unknown: [String])
    case invalidBindings(
        source: String,
        missing: [String],
        unknown: [String]
    )
    case invalidKey(source: String, binding: String, key: String)
    case invalidModifier(
        source: String,
        binding: String,
        modifier: String
    )
    case duplicateModifier(
        source: String,
        binding: String,
        modifier: String
    )
}

private struct KeyBindingRecord: Codable, Sendable {
    let key: String
    let modifiers: [String]
}

struct KeyBindingPresets: Sendable {
    private struct Source: Decodable {
        let version: Int
        let presets: [String: Preset]
    }

    private struct Preset: Decodable {
        let bindings: [String: KeyBindingRecord]
    }

    static let bundled: Self = {
        guard let url = Bundle.module.url(
            forResource: "keybindings",
            withExtension: "json",
            subdirectory: "Presets"
        ) else {
            fatalError("The bundled key-binding presets are missing.")
        }
        do {
            return try Self(data: Data(contentsOf: url))
        } catch {
            fatalError("Invalid bundled key-binding presets: \(error)")
        }
    }()

    private let bindings: [
        KeyBindingPreset: [KeyBindingID: KeyBinding]
    ]

    init(data: Data) throws {
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard source.version == 1 else {
            throw KeyBindingError.unsupportedVersion(source.version)
        }

        let expectedPresets = Set(
            KeyBindingPreset.allCases.map(\.rawValue)
        )
        let sourcePresets = Set(source.presets.keys)
        guard sourcePresets == expectedPresets else {
            throw KeyBindingError.invalidPresets(
                missing: expectedPresets.subtracting(sourcePresets).sorted(),
                unknown: sourcePresets.subtracting(expectedPresets).sorted()
            )
        }

        let expectedBindings = Set(KeyBindingID.allCases.map(\.rawValue))
        var bindings: [
            KeyBindingPreset: [KeyBindingID: KeyBinding]
        ] = [:]

        for preset in KeyBindingPreset.allCases {
            let sourcePreset = source.presets[preset.rawValue]!
            let sourceBindings = Set(sourcePreset.bindings.keys)
            guard sourceBindings == expectedBindings else {
                throw KeyBindingError.invalidBindings(
                    source: preset.rawValue,
                    missing: expectedBindings
                        .subtracting(sourceBindings)
                        .sorted(),
                    unknown: sourceBindings
                        .subtracting(expectedBindings)
                        .sorted()
                )
            }

            var presetBindings: [KeyBindingID: KeyBinding] = [:]
            for identifier in KeyBindingID.allCases {
                let record = sourcePreset.bindings[identifier.rawValue]!
                presetBindings[identifier] = try Self.binding(
                    from: record,
                    source: preset.rawValue,
                    binding: identifier
                )
            }
            bindings[preset] = presetBindings
        }
        self.bindings = bindings
    }

    func binding(
        for identifier: KeyBindingID,
        preset: KeyBindingPreset
    ) -> KeyBinding {
        guard let binding = bindings[preset]?[identifier] else {
            fatalError(
                "Validated key-binding presets lost "
                    + "\(preset.rawValue).\(identifier.rawValue)."
            )
        }
        return binding
    }

    func shortcut(
        for identifier: KeyBindingID,
        preset: KeyBindingPreset
    ) -> KeyboardShortcut {
        do {
            return try Self.keyboardShortcut(
                from: binding(for: identifier, preset: preset),
                source: preset.rawValue,
                binding: identifier
            )
        } catch {
            fatalError("Validated key binding became invalid: \(error)")
        }
    }

    fileprivate static func binding(
        from record: KeyBindingRecord,
        source: String,
        binding: KeyBindingID
    ) throws -> KeyBinding {
        let key = try bindingKey(
            record.key,
            source: source,
            binding: binding
        )
        let modifiers = try keyboardModifiers(
            record.modifiers,
            source: source,
            binding: binding
        )
        let result = KeyBinding(key, modifiers: modifiers)
        _ = try keyboardShortcut(
            from: result,
            source: source,
            binding: binding
        )
        return result
    }

    private static func bindingKey(
        _ value: String,
        source: String,
        binding: KeyBindingID
    ) throws -> WindowMenu.Shortcut.Key {
        if let key = VirtualKey(keyBindingName: value) {
            return .virtual(key)
        }
        guard value.count == 1, let character = value.first else {
            throw KeyBindingError.invalidKey(
                source: source,
                binding: binding.rawValue,
                key: value
            )
        }
        return .character(character)
    }

    private static func keyboardModifiers(
        _ values: [String],
        source: String,
        binding: KeyBindingID
    ) throws -> KeyboardModifierFlags {
        var modifiers: KeyboardModifierFlags = []
        var seen: Set<String> = []
        for value in values {
            guard seen.insert(value).inserted else {
                throw KeyBindingError.duplicateModifier(
                    source: source,
                    binding: binding.rawValue,
                    modifier: value
                )
            }
            let modifier: KeyboardModifierFlags = switch value {
            case "capsLock": .capsLock
            case "shift": .shift
            case "control": .control
            case "option": .option
            case "command": .command
            case "numericPad": .numericPad
            case "function": .function
            default:
                throw KeyBindingError.invalidModifier(
                    source: source,
                    binding: binding.rawValue,
                    modifier: value
                )
            }
            modifiers.insert(modifier)
        }
        return modifiers
    }

    fileprivate static func keyboardShortcut(
        from keyBinding: KeyBinding,
        source: String,
        binding: KeyBindingID
    ) throws -> KeyboardShortcut {
        let key: KeyEquivalent
        switch keyBinding.key {
        case let .character(character):
            key = KeyEquivalent(character)
        case let .virtual(virtualKey):
            guard let equivalent = KeyEquivalent(virtualKey: virtualKey) else {
                throw KeyBindingError.invalidKey(
                    source: source,
                    binding: binding.rawValue,
                    key: virtualKey.keyBindingName ?? String(describing: virtualKey)
                )
            }
            key = equivalent
        }

        let allModifiers: KeyboardModifierFlags = [
            .capsLock,
            .shift,
            .control,
            .option,
            .command,
            .numericPad,
            .function,
        ]
        let unknownModifiers = keyBinding.modifiers.rawValue
            & ~allModifiers.rawValue
        guard unknownModifiers == 0 else {
            throw KeyBindingError.invalidModifier(
                source: source,
                binding: binding.rawValue,
                modifier: "rawValue \(unknownModifiers)"
            )
        }

        var modifiers = EventModifiers(platformFlags: keyBinding.modifiers)
        if case let .virtual(virtualKey) = keyBinding.key,
           virtualKey.keyBindingUsesNumericPad {
            modifiers.insert(.numericPad)
        }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    fileprivate static func equivalent(
        _ lhs: KeyBinding,
        _ rhs: KeyBinding,
        binding: KeyBindingID
    ) -> Bool {
        guard let lhs = try? keyboardShortcut(
            from: lhs,
            source: "user",
            binding: binding
        ), let rhs = try? keyboardShortcut(
            from: rhs,
            source: "user",
            binding: binding
        ) else {
            return lhs == rhs
        }
        return lhs == rhs
    }

    fileprivate static func record(
        from keyBinding: KeyBinding,
        binding: KeyBindingID
    ) throws -> KeyBindingRecord {
        _ = try keyboardShortcut(
            from: keyBinding,
            source: "user",
            binding: binding
        )

        let modifierNames: [(KeyboardModifierFlags, String)] = [
            (.capsLock, "capsLock"),
            (.shift, "shift"),
            (.control, "control"),
            (.option, "option"),
            (.command, "command"),
            (.numericPad, "numericPad"),
            (.function, "function"),
        ]
        let key: String
        switch keyBinding.key {
        case let .character(character):
            key = String(character)
        case let .virtual(virtualKey):
            guard let name = virtualKey.keyBindingName else {
                throw KeyBindingError.invalidKey(
                    source: "user",
                    binding: binding.rawValue,
                    key: String(describing: virtualKey)
                )
            }
            key = name
        }
        return KeyBindingRecord(
            key: key,
            modifiers: modifierNames.compactMap { modifier, name in
                keyBinding.modifiers.contains(modifier) ? name : nil
            }
        )
    }
}

/// A user-owned key-binding file.
///
/// The application may select any such file on any platform. Platform
/// detection is used only when no user file is supplied.
///
/// ```swift
/// var userBindings = UserKeyBindings(basePreset: .windows)
/// userBindings[.textEditingFind] = KeyBinding(
///     .f,
///     modifiers: [.control, .shift]
/// )
/// let data = try userBindings.jsonData()
/// ```
public struct UserKeyBindings: Sendable {
    private struct Source: Codable {
        let basePreset: KeyBindingPreset
        let bindings: [String: KeyBindingRecord]?

        enum CodingKeys: String, CodingKey {
            case basePreset = "base-preset"
            case bindings
        }
    }

    public let basePreset: KeyBindingPreset

    /// Sparse values that differ from the selected base preset.
    public private(set) var bindings: [KeyBindingID: KeyBinding]

    public init(
        basePreset: KeyBindingPreset,
        bindings: [KeyBindingID: KeyBinding] = [:]
    ) {
        self.basePreset = basePreset
        self.bindings = bindings.filter { identifier, binding in
            !KeyBindingPresets.equivalent(
                binding,
                KeyBindingPresets.bundled.binding(
                    for: identifier,
                    preset: basePreset
                ),
                binding: identifier
            )
        }
    }

    /// Returns the effective binding and records only values that differ
    /// from the base preset.
    public subscript(identifier: KeyBindingID) -> KeyBinding {
        get {
            bindings[identifier]
                ?? KeyBindingPresets.bundled.binding(
                    for: identifier,
                    preset: basePreset
                )
        }
        set {
            let inherited = KeyBindingPresets.bundled.binding(
                for: identifier,
                preset: basePreset
            )
            if KeyBindingPresets.equivalent(
                newValue,
                inherited,
                binding: identifier
            ) {
                bindings.removeValue(forKey: identifier)
            } else {
                bindings[identifier] = newValue
            }
        }
    }

    /// Removes an override so the binding inherits from `basePreset` again.
    public mutating func removeOverride(for identifier: KeyBindingID) {
        bindings.removeValue(forKey: identifier)
    }

    /// Decodes and validates a user key-binding JSON document.
    public init(jsonData data: Data) throws {
        let source = try JSONDecoder().decode(Source.self, from: data)
        let sourceBindings = source.bindings ?? [:]
        let unknown = sourceBindings.keys
            .filter { KeyBindingID(rawValue: $0) == nil }
            .sorted()
        guard unknown.isEmpty else {
            throw KeyBindingError.invalidBindings(
                source: "user",
                missing: [],
                unknown: unknown
            )
        }

        var bindings: [KeyBindingID: KeyBinding] = [:]
        for (rawIdentifier, record) in sourceBindings {
            let identifier = KeyBindingID(rawValue: rawIdentifier)!
            bindings[identifier] = try KeyBindingPresets.binding(
                from: record,
                source: "user",
                binding: identifier
            )
        }
        self.init(basePreset: source.basePreset, bindings: bindings)
    }

    /// Encodes this value as pretty-printed, sorted JSON with a final newline.
    public func jsonData() throws -> Data {
        let sourceBindings = bindings.isEmpty ? nil : try Dictionary(
            uniqueKeysWithValues: bindings.map { identifier, binding in
                (
                    identifier.rawValue,
                    try KeyBindingPresets.record(
                        from: binding,
                        binding: identifier
                    )
                )
            }
        )
        let source = Source(
            basePreset: basePreset,
            bindings: sourceBindings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(source)
        data.append(0x0A)
        return data
    }
}

/// Resolves either the current platform preset or one app-selected user file.
struct KeyBindingConfiguration: Sendable {
    static let platformDefault = KeyBindingConfiguration(
        presets: .bundled,
        userKeyBindings: nil,
        platformPreset: .platformDefault
    )

    let basePreset: KeyBindingPreset

    private let presets: KeyBindingPresets
    private let userBindings: [KeyBindingID: KeyBinding]

    init(
        presets: KeyBindingPresets = .bundled,
        userKeyBindings: UserKeyBindings?,
        platformPreset: KeyBindingPreset = .platformDefault
    ) {
        self.presets = presets
        self.basePreset = userKeyBindings?.basePreset ?? platformPreset
        self.userBindings = userKeyBindings?.bindings ?? [:]
    }

    init(
        presets: KeyBindingPresets = .bundled,
        userData: Data?,
        platformPreset: KeyBindingPreset = .platformDefault
    ) throws {
        let userKeyBindings = try userData.map(
            UserKeyBindings.init(jsonData:)
        )
        self.init(
            presets: presets,
            userKeyBindings: userKeyBindings,
            platformPreset: platformPreset
        )
    }

    func shortcut(for identifier: KeyBindingID) -> KeyboardShortcut {
        guard let userBinding = userBindings[identifier] else {
            return presets.shortcut(for: identifier, preset: basePreset)
        }
        do {
            return try KeyBindingPresets.keyboardShortcut(
                from: userBinding,
                source: "user",
                binding: identifier
            )
        } catch {
            fatalError("Validated user key binding became invalid: \(error)")
        }
    }
}

private let currentKeyBindingConfiguration = Mutex(
    KeyBindingConfiguration.platformDefault
)

/// Loads an app-selected user key-binding document.
///
/// The document is standard JSON without comments and has this shape:
///
/// ```json
/// {
///   "base-preset": "windows",
///   "bindings": {
///     "textEditing.find": {
///       "key": "f",
///       "modifiers": ["control", "shift"]
///     },
///     "sidebar.toggle": {
///       "key": "s",
///       "modifiers": ["control", "option"]
///     }
///   }
/// }
/// ```
///
/// `base-preset` is required and must be `apple`, `windows`, or `linux`. It is
/// interpreted literally on every host, so a file based on `windows` remains
/// Control-based when loaded on an Apple platform. The optional `bindings`
/// object contains sparse overrides; every omitted binding is inherited from
/// the named base preset.
///
/// Each override requires a `key` and a `modifiers` array. A key may be one
/// literal Swift `Character`, or one of these `VirtualKey` case names:
///
/// - `escape`, `f1` through `f20`
/// - `num0` through `num9`, `a` through `z`
/// - `period`, `comma`, `slash`, `tab`, `accentTilde`, `backspace`
/// - `semicolon`, `quote`, `backslash`, `equal`, `hyphen`, `space`
/// - `openBracket`, `closeBracket`, `return`
/// - `insert`, `home`, `pageUp`, `pageDown`, `end`, `delete`
/// - `left`, `right`, `up`, `down`
/// - `pad0` through `pad9`, `enter`, `numlock`, `padSlash`
/// - `padAsterisk`, `padPlus`, `padMinus`, `padEqual`, `padPeriod`
///
/// Names are case-sensitive. For example, `"left"` means the left-arrow
/// virtual key, while `"{"` is a literal character. Virtual modifier keys,
/// `none`, `fn`, and `capslock` cannot be primary shortcut keys.
///
/// Supported modifier names are `capsLock`, `shift`, `control`, `option`,
/// `command`, `numericPad`, and `function`. Modifier order does not matter,
/// but duplicate or unknown modifiers are invalid. Numeric keypad virtual
/// keys imply `numericPad` when matching input, even if it is omitted here.
///
/// The currently supported binding identifiers are:
///
/// - `textEditing.find`
/// - `textEditing.findAndReplace`
/// - `textEditing.findNext`
/// - `textEditing.findPrevious`
/// - `textEditing.useSelectionForFind`
/// - `textEditing.jumpToSelection`
/// - `textEditing.showSpellingAndGrammar`
/// - `textEditing.checkDocumentNow`
/// - `textFormatting.alignLeft`
/// - `textFormatting.alignCenter`
/// - `textFormatting.alignRight`
/// - `textFormatting.copyRuler`
/// - `textFormatting.pasteRuler`
/// - `toolbar.toggleVisibility`
/// - `sidebar.toggle`
/// - `inspector.toggle`
///
/// Passing `nil` restores the current platform preset. Unknown fields are
/// ignored by JSON decoding, but unknown binding identifiers, malformed
/// values, and missing `base-preset` values throw without replacing the
/// currently active configuration.
public func loadKeyBindings(_ userOverrides: Data?) throws {
    let configuration = try KeyBindingConfiguration(userData: userOverrides)
    currentKeyBindingConfiguration.withLock {
        $0 = configuration
    }
    if let windowsController = appContext?.appWindowsController {
        Task { @MainActor [weak windowsController] in
            windowsController?.scheduleRootCommandsRefreshForKeyBindings()
        }
    }
}

/// Loads an app-selected user key-binding file.
///
/// Passing `nil` restores the current platform preset.
public func loadKeyBindings(contentsOf userOverridesURL: URL?) throws {
    let data: Data?
    if let userOverridesURL {
        data = try Data(contentsOf: userOverridesURL)
    } else {
        data = nil
    }
    try loadKeyBindings(data)
}

func builtInKeyboardShortcut(_ identifier: KeyBindingID) -> KeyboardShortcut {
    currentKeyBindingConfiguration.withLock {
        $0.shortcut(for: identifier)
    }
}

extension PlatformItemList.Item {
    // Framework bindings retain their semantic identifier so a configuration
    // reload can resolve the shortcut without rebuilding the source Commands.
    var resolvedKeyboardShortcut: KeyboardShortcut? {
        builtInKeyBinding.map(builtInKeyboardShortcut) ?? keyboardShortcut
    }
}

extension PlatformItemList {
    mutating func resolveBuiltInKeyboardShortcuts() {
        for index in items.indices {
            if let identifier = items[index].builtInKeyBinding {
                items[index].keyboardShortcut = builtInKeyboardShortcut(
                    identifier
                )
            }
            items[index].children?.resolveBuiltInKeyboardShortcuts()
            items[index].labelGroupChildren?
                .resolveBuiltInKeyboardShortcuts()
        }
    }
}

private struct BuiltInKeyboardShortcutModifier: ViewModifier {
    var identifier: KeyBindingID

    func body(content: Content) -> some View {
        content.transformPlatformItemList(
            AllPlatformItemListFlags.self
        ) { list in
            let shortcut = builtInKeyboardShortcut(identifier)
            list.modify { item in
                item.keyboardShortcut = shortcut
                item.builtInKeyBinding = identifier
            }
        }
    }
}

extension View {
    func builtInKeyboardShortcut(_ identifier: KeyBindingID) -> some View {
        modifier(BuiltInKeyboardShortcutModifier(identifier: identifier))
    }
}
