//
//  File: MenuKeyboard.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Renderer-owned menus have no native label syntax for declaring mnemonics.
// Assign the earliest unused alphanumeric character so every presentation of
// the same ordered item list derives the same keyboard surface.
func resolvedMenuAccessKeys<ID: Hashable>(
    for entries: [(id: ID, title: String)]
) -> [ID: Character] {
    var result: [ID: Character] = [:]
    var used: Set<String> = []
    for entry in entries {
        guard let character = entry.title.first(where: { candidate in
            guard candidate.isLetter || candidate.isNumber else {
                return false
            }
            return !used.contains(foldedMenuCharacter(candidate))
        }) else {
            continue
        }
        used.insert(foldedMenuCharacter(character))
        result[entry.id] = character
    }
    return result
}

func menuCharactersAreEquivalent(
    _ lhs: Character,
    _ rhs: Character
) -> Bool {
    foldedMenuCharacter(lhs) == foldedMenuCharacter(rhs)
}

func menuAccessKeyText(
    _ title: String,
    accessKey: Character?,
    showsAccessKey: Bool
) -> Text {
    guard showsAccessKey, let accessKey else {
        return Text(verbatim: title)
    }
    var result = Text(verbatim: "")
    var didUnderline = false
    for character in title {
        var segment = Text(verbatim: String(character))
        if !didUnderline,
           menuCharactersAreEquivalent(character, accessKey) {
            segment = segment.underline()
            didUnderline = true
        }
        result = result + segment
    }
    return result
}

func menuKeyboardShortcutSymbolNames(
    for modifiers: EventModifiers
) -> [String] {
    var result: [String] = []
    if modifiers.contains(.control) {
        result.append("keyboard.control")
    }
    if modifiers.contains(.option) {
        result.append("keyboard.option")
    }
    if modifiers.contains(.shift) {
        result.append("keyboard.shift")
    }
    if modifiers.contains(.command) {
        result.append("keyboard.command")
    }
    return result
}

struct MenuKeyboardShortcutLabel: View {
    var shortcut: KeyboardShortcut

    var body: some View {
        if shortcut.special != nil {
            Text(verbatim: shortcut.displayLabel)
        } else {
            // Backends without dedicated Win/Alt artwork temporarily reuse the
            // Command/Option shapes. Input semantics still come from modifiers.
            HStack(spacing: 1) {
                ForEach(
                    menuKeyboardShortcutSymbolNames(
                        for: shortcut.modifiers
                    ),
                    id: \.self
                ) { symbolName in
                    Image(decorative: symbolName, variableValue: nil)
                }
                Text(verbatim: String(shortcut.key.character).uppercased())
            }
            .font(.system(size: 12))
        }
    }
}

private func foldedMenuCharacter(_ character: Character) -> String {
    String(character)
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .lowercased()
}
