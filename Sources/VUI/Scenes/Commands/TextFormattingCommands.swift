//
//  File: TextFormattingCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TextFormattingCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .textFormatting) {
            Section {
                ExternalMenu(
                    "Font",
                    platformIdentifier: "NSFontMenu"
                )
                textSubmenu
            }
        }
    }

    private var textSubmenu: some View {
        Menu("Text") {
            alignmentSection
            Section {
                writingDirectionSubmenu
            }
            rulerSection
        }
    }

    private var alignmentSection: some View {
        Section {
            textFormattingButton(
                "Align Left",
                command: .alignLeft,
                keyBinding: .textFormattingAlignLeft
            )
            textFormattingButton(
                "Center",
                command: .alignCenter,
                keyBinding: .textFormattingAlignCenter
            )
            textFormattingButton("Justify", command: .alignJustify)
            textFormattingButton(
                "Align Right",
                command: .alignRight,
                keyBinding: .textFormattingAlignRight
            )
        }
    }

    private var writingDirectionSubmenu: some View {
        Menu("Writing Direction") {
            Section("Paragraph") {
                textFormattingButton(
                    "Default",
                    command: .defaultParagraphWritingDirection
                )
                textFormattingButton(
                    "Left to Right",
                    command: .leftToRightParagraphWritingDirection
                )
                textFormattingButton(
                    "Right to Left",
                    command: .rightToLeftParagraphWritingDirection
                )
            }
            Section("Selection") {
                textFormattingButton(
                    "Default",
                    command: .defaultSelectionWritingDirection
                )
                textFormattingButton(
                    "Left to Right",
                    command: .leftToRightSelectionWritingDirection
                )
                textFormattingButton(
                    "Right to Left",
                    command: .rightToLeftSelectionWritingDirection
                )
            }
        }
    }

    private var rulerSection: some View {
        Section {
            textFormattingButton("Show Ruler", command: .toggleRuler)
            textFormattingButton(
                "Copy Ruler",
                command: .copyRuler,
                keyBinding: .textFormattingCopyRuler
            )
            textFormattingButton(
                "Paste Ruler",
                command: .pasteRuler,
                keyBinding: .textFormattingPasteRuler
            )
        }
    }

    private func textFormattingButton(
        _ title: LocalizedStringKey,
        command: TextFormattingCommand
    ) -> some View {
        Button(title) {
            performRootTextFormattingCommand(command)
        }
        .modifier(TextFormattingCommandItemModifier(command: command))
    }

    private func textFormattingButton(
        _ title: LocalizedStringKey,
        command: TextFormattingCommand,
        keyBinding: KeyBindingID
    ) -> some View {
        Button(title) {
            performRootTextFormattingCommand(command)
        }
        .builtInKeyboardShortcut(keyBinding)
        .modifier(TextFormattingCommandItemModifier(command: command))
    }
}

@available(*, unavailable)
extension TextFormattingCommands: Sendable {}

enum TextFormattingCommand: Hashable, Sendable {
    case alignLeft
    case alignCenter
    case alignJustify
    case alignRight
    case defaultParagraphWritingDirection
    case leftToRightParagraphWritingDirection
    case rightToLeftParagraphWritingDirection
    case defaultSelectionWritingDirection
    case leftToRightSelectionWritingDirection
    case rightToLeftSelectionWritingDirection
    case toggleRuler
    case copyRuler
    case pasteRuler
}

protocol TextFormattingCommandResponder: AnyObject {
    func performTextFormattingCommand(_ command: TextFormattingCommand)
}

extension WindowController {
    func performTextFormattingCommand(_ command: TextFormattingCommand) {
        textFormattingCommandResponder()?.performTextFormattingCommand(command)
    }

    private func textFormattingCommandResponder()
        -> (any TextFormattingCommandResponder)? {
        guard let commandFocusedResponder else { return nil }
        for responder in commandFocusedResponder.sequence {
            if let responder = responder as? any TextFormattingCommandResponder {
                return responder
            }
        }
        return nil
    }
}

private struct TextFormattingCommandItemModifier: ViewModifier {
    var command: TextFormattingCommand

    func body(content: Content) -> some View {
        content.transformPlatformItemList(
            SelectionPlatformItemListFlags.self
        ) { list in
            list.modify { item in
                item.textFormattingCommand = command
            }
        }
    }
}

private func performRootTextFormattingCommand(
    _ command: TextFormattingCommand
) {
    appContext?.appWindowsController?
        .performRootTextFormattingCommand(command)
}
