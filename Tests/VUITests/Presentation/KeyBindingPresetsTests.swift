import Foundation
import XCTest
@testable import VUI
@testable import VVD

final class KeyBindingPresetsTests: XCTestCase {
    func testBundledPresetsUsePlatformNamedModifierConventions() {
        let presets = KeyBindingPresets.bundled
        let apple: [KeyBindingID: KeyboardShortcut] = [
            .textEditingFind: KeyboardShortcut("f", modifiers: .command),
            .textEditingFindAndReplace: KeyboardShortcut(
                "f", modifiers: [.command, .option]
            ),
            .textEditingFindNext: KeyboardShortcut("g", modifiers: .command),
            .textEditingFindPrevious: KeyboardShortcut(
                "g", modifiers: [.command, .shift]
            ),
            .textEditingUseSelectionForFind: KeyboardShortcut(
                "e", modifiers: .command
            ),
            .textEditingJumpToSelection: KeyboardShortcut(
                "j", modifiers: .command
            ),
            .textEditingShowSpellingAndGrammar: KeyboardShortcut(
                ":", modifiers: .command
            ),
            .textEditingCheckDocumentNow: KeyboardShortcut(
                ";", modifiers: .command
            ),
            .textFormattingAlignLeft: KeyboardShortcut(
                "{", modifiers: .command
            ),
            .textFormattingAlignCenter: KeyboardShortcut(
                "|", modifiers: .command
            ),
            .textFormattingAlignRight: KeyboardShortcut(
                "}", modifiers: .command
            ),
            .textFormattingCopyRuler: KeyboardShortcut(
                "c", modifiers: [.command, .control]
            ),
            .textFormattingPasteRuler: KeyboardShortcut(
                "v", modifiers: [.command, .control]
            ),
            .toolbarToggleVisibility: KeyboardShortcut(
                "t", modifiers: [.command, .option]
            ),
            .sidebarToggle: KeyboardShortcut(
                "s", modifiers: [.command, .control]
            ),
            .inspectorToggle: KeyboardShortcut(
                "i", modifiers: [.command, .control]
            ),
        ]
        let controlBased: [KeyBindingID: KeyboardShortcut] = [
            .textEditingFind: KeyboardShortcut("f", modifiers: .control),
            .textEditingFindAndReplace: KeyboardShortcut(
                "f", modifiers: [.control, .option]
            ),
            .textEditingFindNext: KeyboardShortcut("g", modifiers: .control),
            .textEditingFindPrevious: KeyboardShortcut(
                "g", modifiers: [.control, .shift]
            ),
            .textEditingUseSelectionForFind: KeyboardShortcut(
                "e", modifiers: .control
            ),
            .textEditingJumpToSelection: KeyboardShortcut(
                "j", modifiers: .control
            ),
            .textEditingShowSpellingAndGrammar: KeyboardShortcut(
                ":", modifiers: .control
            ),
            .textEditingCheckDocumentNow: KeyboardShortcut(
                ";", modifiers: .control
            ),
            .textFormattingAlignLeft: KeyboardShortcut(
                "{", modifiers: .control
            ),
            .textFormattingAlignCenter: KeyboardShortcut(
                "|", modifiers: .control
            ),
            .textFormattingAlignRight: KeyboardShortcut(
                "}", modifiers: .control
            ),
            .textFormattingCopyRuler: KeyboardShortcut(
                "c", modifiers: [.control, .option]
            ),
            .textFormattingPasteRuler: KeyboardShortcut(
                "v", modifiers: [.control, .option]
            ),
            .toolbarToggleVisibility: KeyboardShortcut(
                "t", modifiers: [.control, .option]
            ),
            .sidebarToggle: KeyboardShortcut(
                "s", modifiers: [.control, .option]
            ),
            .inspectorToggle: KeyboardShortcut(
                "i", modifiers: [.control, .option]
            ),
        ]

        XCTAssertEqual(Set(apple.keys), Set(KeyBindingID.allCases))
        XCTAssertEqual(Set(controlBased.keys), Set(KeyBindingID.allCases))
        for identifier in KeyBindingID.allCases {
            XCTAssertEqual(
                presets.shortcut(for: identifier, preset: .apple),
                apple[identifier]
            )
            for preset in [KeyBindingPreset.windows, .linux] {
                XCTAssertEqual(
                    presets.shortcut(for: identifier, preset: preset),
                    controlBased[identifier]
                )
            }
        }
    }

    func testMissingUserFileUsesCurrentPlatformPreset() {
        let presets = KeyBindingPresets.bundled
        let configuration = KeyBindingConfiguration(
            presets: presets,
            userKeyBindings: nil
        )

        XCTAssertEqual(configuration.basePreset, .platformDefault)
        for identifier in KeyBindingID.allCases {
            XCTAssertEqual(
                configuration.shortcut(for: identifier),
                presets.shortcut(
                    for: identifier,
                    preset: .platformDefault
                )
            )
        }
    }

    func testMinimalUserFileLoadsChosenBasePreset() throws {
        let userKeyBindings = UserKeyBindings(basePreset: .windows)
        let data = try userKeyBindings.jsonData()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["base-preset"] as? String, "windows")
        XCTAssertNil(object["bindings"])

        let loaded = try UserKeyBindings(jsonData: data)
        XCTAssertEqual(loaded.basePreset, .windows)
        XCTAssertTrue(loaded.bindings.isEmpty)
    }

    func testSelectedUserFileBasePresetOverridesHostPlatform() throws {
        let presets = KeyBindingPresets.bundled
        let userData = try UserKeyBindings(
            basePreset: .windows
        ).jsonData()
        let configuration = try KeyBindingConfiguration(
            presets: presets,
            userData: userData,
            platformPreset: .apple
        )

        XCTAssertEqual(configuration.basePreset, .windows)
        for identifier in KeyBindingID.allCases {
            XCTAssertEqual(
                configuration.shortcut(for: identifier),
                presets.shortcut(for: identifier, preset: .windows)
            )
        }
    }

    func testUserFileAppliesSparseBindingsOverItsBasePreset() throws {
        let override = KeyBinding(
            .q,
            modifiers: [.control, .shift]
        )
        var userKeyBindings = UserKeyBindings(basePreset: .linux)
        userKeyBindings[.textEditingFind] = override
        let userData = try userKeyBindings.jsonData()
        let presets = KeyBindingPresets.bundled
        let configuration = try KeyBindingConfiguration(
            presets: presets,
            userData: userData,
            platformPreset: .apple
        )

        XCTAssertEqual(
            configuration.shortcut(for: .textEditingFind),
            KeyboardShortcut("q", modifiers: [.control, .shift])
        )
        XCTAssertEqual(
            configuration.shortcut(for: .textEditingFindNext),
            presets.shortcut(for: .textEditingFindNext, preset: .linux)
        )
    }

    func testVirtualAndLiteralKeysRoundTripThroughJSON() throws {
        var userKeyBindings = UserKeyBindings(basePreset: .windows)
        userKeyBindings[.textEditingFind] = KeyBinding(
            .f12,
            modifiers: .control
        )
        userKeyBindings[.textFormattingAlignLeft] = KeyBinding(
            "{",
            modifiers: .control
        )

        let data = try userKeyBindings.jsonData()
        let loaded = try UserKeyBindings(jsonData: data)

        XCTAssertEqual(
            loaded[.textEditingFind],
            KeyBinding(.f12, modifiers: .control)
        )
        XCTAssertEqual(
            loaded[.textFormattingAlignLeft],
            KeyBinding("{", modifiers: .control)
        )

        let configuration = KeyBindingConfiguration(
            userKeyBindings: loaded,
            platformPreset: .apple
        )
        XCTAssertEqual(
            configuration.shortcut(for: .textEditingFind),
            KeyboardShortcut("\u{F70F}", modifiers: .control)
        )
        XCTAssertEqual(
            configuration.shortcut(for: .textFormattingAlignLeft),
            KeyboardShortcut("{", modifiers: .control)
        )
    }

    func testPlatformEventMapsNamedVirtualShortcutKeys() {
        XCTAssertEqual(
            KeyEquivalent(platformEvent: keyboardEvent(key: .f1)),
            KeyEquivalent("\u{F704}")
        )
        XCTAssertEqual(
            KeyEquivalent(platformEvent: keyboardEvent(key: .insert)),
            KeyEquivalent("\u{F727}")
        )
        XCTAssertNil(
            KeyEquivalent(platformEvent: keyboardEvent(key: .leftShift))
        )
    }

    func testNumericPadVirtualKeyAddsMatchingModifier() {
        var userKeyBindings = UserKeyBindings(basePreset: .windows)
        userKeyBindings[.textEditingFind] = KeyBinding(
            .pad1,
            modifiers: .control
        )
        let shortcut = KeyBindingConfiguration(
            userKeyBindings: userKeyBindings
        ).shortcut(
            for: .textEditingFind
        )

        XCTAssertEqual(shortcut.key, "1")
        let expectedModifiers: EventModifiers = [.control, .numericPad]
        XCTAssertEqual(shortcut.modifiers, expectedModifiers)

        userKeyBindings[.textEditingFind] = KeyBinding(
            .numlock,
            modifiers: .control
        )
        let numLockShortcut = KeyBindingConfiguration(
            userKeyBindings: userKeyBindings
        ).shortcut(for: .textEditingFind)
        XCTAssertEqual(numLockShortcut.key, .clear)
        XCTAssertEqual(numLockShortcut.modifiers, expectedModifiers)
    }

    func testPresetConfigurationRejectsIncompleteAndUnknownBindings() throws {
        var source = completePresetSource()
        var presets = try XCTUnwrap(source["presets"] as? [String: Any])
        var apple = try XCTUnwrap(presets["apple"] as? [String: Any])
        var bindings = try XCTUnwrap(
            apple["bindings"] as? [String: Any]
        )
        bindings.removeValue(forKey: KeyBindingID.textEditingFind.rawValue)
        bindings["unknown.command"] = [
            "key": "u",
            "modifiers": ["command"],
        ]
        apple["bindings"] = bindings
        presets["apple"] = apple
        source["presets"] = presets

        let data = try JSONSerialization.data(withJSONObject: source)
        XCTAssertThrowsError(try KeyBindingPresets(data: data)) { error in
            XCTAssertEqual(
                error as? KeyBindingError,
                .invalidBindings(
                    source: "apple",
                    missing: [KeyBindingID.textEditingFind.rawValue],
                    unknown: ["unknown.command"]
                )
            )
        }
    }

    func testConfigurationRejectsUnknownAndDuplicateModifiers() throws {
        var source = completePresetSource()
        try setModifiers(
            ["control", "mystery"],
            for: .textEditingFind,
            preset: .windows,
            in: &source
        )
        var data = try JSONSerialization.data(withJSONObject: source)
        XCTAssertThrowsError(try KeyBindingPresets(data: data)) { error in
            XCTAssertEqual(
                error as? KeyBindingError,
                .invalidModifier(
                    source: "windows",
                    binding: KeyBindingID.textEditingFind.rawValue,
                    modifier: "mystery"
                )
            )
        }

        source = completePresetSource()
        try setModifiers(
            ["control", "control"],
            for: .textEditingFind,
            preset: .linux,
            in: &source
        )
        data = try JSONSerialization.data(withJSONObject: source)
        XCTAssertThrowsError(try KeyBindingPresets(data: data)) { error in
            XCTAssertEqual(
                error as? KeyBindingError,
                .duplicateModifier(
                    source: "linux",
                    binding: KeyBindingID.textEditingFind.rawValue,
                    modifier: "control"
                )
            )
        }
    }

    func testUserFileRejectsUnknownBinding() throws {
        let source: [String: Any] = [
            "base-preset": "apple",
            "bindings": [
                "unknown.command": [
                    "key": "u",
                    "modifiers": ["command"],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: source)

        XCTAssertThrowsError(try UserKeyBindings(jsonData: data)) { error in
            XCTAssertEqual(
                error as? KeyBindingError,
                .invalidBindings(
                    source: "user",
                    missing: [],
                    unknown: ["unknown.command"]
                )
            )
        }
    }

    func testJSONCreationRejectsNonRepresentableVirtualKey() {
        var userKeyBindings = UserKeyBindings(basePreset: .apple)
        userKeyBindings[.textEditingFind] = KeyBinding(
            .leftShift,
            modifiers: .command
        )

        XCTAssertThrowsError(try userKeyBindings.jsonData()) { error in
            XCTAssertEqual(
                error as? KeyBindingError,
                .invalidKey(
                    source: "user",
                    binding: KeyBindingID.textEditingFind.rawValue,
                    key: "leftShift"
                )
            )
        }
    }

    func testSubscriptResolvesBaseAndStoresOnlyDifferences() {
        let presets = KeyBindingPresets.bundled
        let inherited = presets.binding(
            for: .textEditingFind,
            preset: .windows
        )
        var userKeyBindings = UserKeyBindings(basePreset: .windows)

        XCTAssertEqual(userKeyBindings[.textEditingFind], inherited)
        XCTAssertTrue(userKeyBindings.bindings.isEmpty)

        userKeyBindings[.textEditingFind] = KeyBinding(
            .q,
            modifiers: .control
        )
        XCTAssertEqual(
            userKeyBindings.bindings[.textEditingFind],
            KeyBinding(.q, modifiers: .control)
        )

        userKeyBindings[.textEditingFind] = inherited
        XCTAssertTrue(userKeyBindings.bindings.isEmpty)

        let initialized = UserKeyBindings(
            basePreset: .windows,
            bindings: [.textEditingFind: inherited]
        )
        XCTAssertTrue(initialized.bindings.isEmpty)
    }

    func testPublicLoaderAppliesUserFileAndNilRestoresPlatformPreset() throws {
        defer { try? loadKeyBindings(nil) }

        var userKeyBindings = UserKeyBindings(basePreset: .windows)
        let override = KeyBinding(
            .q,
            modifiers: [.control, .shift]
        )
        userKeyBindings[.textEditingFind] = override

        try loadKeyBindings(userKeyBindings.jsonData())
        XCTAssertEqual(
            builtInKeyboardShortcut(.textEditingFind),
            KeyboardShortcut("q", modifiers: [.control, .shift])
        )

        try loadKeyBindings(nil)
        XCTAssertEqual(
            builtInKeyboardShortcut(.textEditingFind),
            KeyBindingPresets.bundled.shortcut(
                for: .textEditingFind,
                preset: .platformDefault
            )
        )
    }

    func testReloadedConfigurationIsReadDuringMenuRematerialization() throws {
        defer { try? loadKeyBindings(nil) }

        let item = MainMenuItem(
            name: "Edit",
            id: .edit,
            groups: [
                CommandAccumulator.Result(
                    viewContent: AnyView(
                        Button("Find") {}
                            .builtInKeyboardShortcut(.textEditingFind)
                    )
                ),
            ]
        )
        let environment = EnvironmentValues()
        let host = MainMenuItemHost(item: item, environment: environment)

        try loadKeyBindings(
            UserKeyBindings(basePreset: .apple).jsonData()
        )
        host.update(item: item, environment: environment)
        XCTAssertEqual(
            try XCTUnwrap(host.menuItems().items.first).keyboardShortcut,
            KeyboardShortcut("f", modifiers: .command)
        )

        try loadKeyBindings(
            UserKeyBindings(basePreset: .windows).jsonData()
        )
        host.update(item: item, environment: environment)
        XCTAssertEqual(
            try XCTUnwrap(host.menuItems().items.first).keyboardShortcut,
            KeyboardShortcut("f", modifiers: .control)
        )
    }

    func testInvalidPublicLoadPreservesCurrentConfiguration() throws {
        defer { try? loadKeyBindings(nil) }

        let userKeyBindings = UserKeyBindings(basePreset: .linux)
        try loadKeyBindings(userKeyBindings.jsonData())
        let before = builtInKeyboardShortcut(.textEditingFind)

        XCTAssertThrowsError(try loadKeyBindings(Data("{}".utf8)))
        XCTAssertEqual(builtInKeyboardShortcut(.textEditingFind), before)
    }

    private func completePresetSource() -> [String: Any] {
        let bindings = Dictionary(uniqueKeysWithValues:
            KeyBindingID.allCases.map { identifier in
                (
                    identifier.rawValue,
                    [
                        "key": "k",
                        "modifiers": ["control"],
                    ] as [String: Any]
                )
            }
        )
        let preset: [String: Any] = ["bindings": bindings]
        return [
            "version": 1,
            "presets": Dictionary(uniqueKeysWithValues:
                KeyBindingPreset.allCases.map { presetName in
                    (presetName.rawValue, preset)
                }
            ),
        ]
    }

    private func keyboardEvent(key: VirtualKey) -> KeyboardEvent {
        KeyboardEvent(
            type: .keyDown,
            window: nil,
            deviceID: 0,
            key: key,
            text: "",
            isRepeat: false,
            modifiers: []
        )
    }

    private func setModifiers(
        _ modifiers: [String],
        for identifier: KeyBindingID,
        preset: KeyBindingPreset,
        in source: inout [String: Any]
    ) throws {
        var presets = try XCTUnwrap(source["presets"] as? [String: Any])
        var presetSource = try XCTUnwrap(
            presets[preset.rawValue] as? [String: Any]
        )
        var bindings = try XCTUnwrap(
            presetSource["bindings"] as? [String: Any]
        )
        var binding = try XCTUnwrap(
            bindings[identifier.rawValue] as? [String: Any]
        )
        binding["modifiers"] = modifiers
        bindings[identifier.rawValue] = binding
        presetSource["bindings"] = bindings
        presets[preset.rawValue] = presetSource
        source["presets"] = presets
    }
}
