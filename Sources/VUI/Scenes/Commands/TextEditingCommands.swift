//
//  File: TextEditingCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct TextEditingCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            findSubmenu
            spellingAndGrammarSubmenu
            substitutionsSubmenu
            transformationsSubmenu
            speechSubmenu
        }
    }

    private var findSubmenu: some View {
        Menu("Find") {
            textEditingButton(
                "Find…",
                command: .find,
                tag: 1,
                keyBinding: .textEditingFind
            )
            textEditingButton(
                "Find and Replace…",
                command: .findAndReplace,
                tag: 12,
                keyBinding: .textEditingFindAndReplace
            )
            textEditingButton(
                "Find Next",
                command: .findNext,
                tag: 2,
                keyBinding: .textEditingFindNext
            )
            textEditingButton(
                "Find Previous",
                command: .findPrevious,
                tag: 3,
                keyBinding: .textEditingFindPrevious
            )
            textEditingButton(
                "Use Selection for Find",
                command: .useSelectionForFind,
                tag: 7,
                keyBinding: .textEditingUseSelectionForFind
            )
            textEditingButton(
                "Jump to Selection",
                command: .jumpToSelection,
                keyBinding: .textEditingJumpToSelection
            )
        }
        .modifier(TextEditingFindMenuValidationModifier())
    }

    private var spellingAndGrammarSubmenu: some View {
        Menu("Spelling and Grammar") {
            Section {
                textEditingButton(
                    "Show Spelling and Grammar",
                    command: .showSpellingAndGrammar,
                    keyBinding: .textEditingShowSpellingAndGrammar
                )
                textEditingButton(
                    "Check Document Now",
                    command: .checkDocumentNow,
                    keyBinding: .textEditingCheckDocumentNow
                )
            }
            Section {
                textEditingButton(
                    "Check Spelling While Typing",
                    command: .toggleCheckSpellingWhileTyping
                )
                textEditingButton(
                    "Check Grammar With Spelling",
                    command: .toggleCheckGrammarWithSpelling
                )
                textEditingButton(
                    "Correct Spelling Automatically",
                    command: .toggleAutomaticSpellingCorrection
                )
            }
        }
    }

    private var substitutionsSubmenu: some View {
        Menu("Substitutions") {
            textEditingButton(
                "Show Substitutions",
                command: .showSubstitutions
            )
            Section {
                textEditingButton(
                    "Smart Copy/Paste",
                    command: .toggleSmartCopyPaste
                )
                textEditingButton(
                    "Smart Quotes",
                    command: .toggleSmartQuotes
                )
                textEditingButton(
                    "Smart Dashes",
                    command: .toggleSmartDashes
                )
                textEditingButton(
                    "Smart Links",
                    command: .toggleSmartLinks
                )
                textEditingButton(
                    "Data Detectors",
                    command: .toggleDataDetectors
                )
                textEditingButton(
                    "Text Replacement",
                    command: .toggleTextReplacement
                )
            }
        }
    }

    private var transformationsSubmenu: some View {
        Menu("Transformations") {
            textEditingButton("Make Upper Case", command: .makeUpperCase)
            textEditingButton("Make Lower Case", command: .makeLowerCase)
            textEditingButton("Capitalize", command: .capitalize)
        }
    }

    private var speechSubmenu: some View {
        Menu("Speech") {
            textEditingButton("Start Speaking", command: .startSpeaking)
            textEditingButton("Stop Speaking", command: .stopSpeaking)
        }
    }

    private func textEditingButton(
        _ title: LocalizedStringKey,
        command: TextEditingCommand,
        tag: Int? = nil
    ) -> some View {
        Button(title) {
            performRootTextEditingCommand(command)
        }
        .modifier(
            TextEditingCommandItemModifier(command: command, tag: tag)
        )
    }

    private func textEditingButton(
        _ title: LocalizedStringKey,
        command: TextEditingCommand,
        tag: Int? = nil,
        keyBinding: KeyBindingID
    ) -> some View {
        Button(title) {
            performRootTextEditingCommand(command)
        }
        .builtInKeyboardShortcut(keyBinding)
        .modifier(
            TextEditingCommandItemModifier(command: command, tag: tag)
        )
    }
}

@available(*, unavailable)
extension TextEditingCommands: Sendable {}

enum TextEditingCommand: Hashable, Sendable {
    case copy
    case cut
    case paste
    case delete
    case selectAll
    case find
    case findAndReplace
    case findNext
    case findPrevious
    case useSelectionForFind
    case jumpToSelection
    case showSpellingAndGrammar
    case checkDocumentNow
    case toggleCheckSpellingWhileTyping
    case toggleCheckGrammarWithSpelling
    case toggleAutomaticSpellingCorrection
    case showSubstitutions
    case toggleSmartCopyPaste
    case toggleSmartQuotes
    case toggleSmartDashes
    case toggleSmartLinks
    case toggleDataDetectors
    case toggleTextReplacement
    case makeUpperCase
    case makeLowerCase
    case capitalize
    case startSpeaking
    case stopSpeaking
}

extension _ResolvedCommands {
    mutating func initializeDefaultPasteboardCommands() {
        let operation = CommandOperation(
            mutation: .initialize,
            placement: .pasteboard,
            content: DefaultPasteboardCommandItems()
        )
        operation.resolver?(operation, &self)
    }
}

private struct DefaultPasteboardCommandItems: View {
    var body: some View {
        pasteboardButton(
            "Cut",
            command: .cut,
            keyBinding: .pasteboardCut
        )
        pasteboardButton(
            "Copy",
            command: .copy,
            keyBinding: .pasteboardCopy
        )
        pasteboardButton(
            "Paste",
            command: .paste,
            keyBinding: .pasteboardPaste
        )
        pasteboardButton("Delete", command: .delete)
        pasteboardButton(
            "Select All",
            command: .selectAll,
            keyBinding: .pasteboardSelectAll
        )
    }

    private func pasteboardButton(
        _ title: LocalizedStringKey,
        command: TextEditingCommand
    ) -> some View {
        Button(title) {
            performRootTextEditingCommand(command)
        }
        .modifier(TextEditingCommandItemModifier(command: command, tag: nil))
        .modifier(DefaultPasteboardCommandValidationModifier(command: command))
    }

    private func pasteboardButton(
        _ title: LocalizedStringKey,
        command: TextEditingCommand,
        keyBinding: KeyBindingID
    ) -> some View {
        Button(title) {
            performRootTextEditingCommand(command)
        }
        .builtInKeyboardShortcut(keyBinding)
        .modifier(TextEditingCommandItemModifier(command: command, tag: nil))
        .modifier(DefaultPasteboardCommandValidationModifier(command: command))
    }
}

private struct DefaultPasteboardCommandValidationModifier: ViewModifier {
    var command: TextEditingCommand

    func body(content: Content) -> some View {
        let isEnabled = canPerformRootTextEditingCommand(command)
        return content
            .disabled(!isEnabled)
            .transformPlatformItemList(
                AllPlatformItemListFlags.self
            ) { list in
                list.modify { item in
                    item.isEnabled = item.isEnabled && isEnabled
                    if var selection = item.selectionBehavior {
                        selection.onSelect = isEnabled ? {
                            performRootTextEditingCommand(command)
                        } : nil
                        item.selectionBehavior = selection
                    }
                }
            }
    }
}

protocol TextEditingCommandResponder: AnyObject {
    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool
    func performTextEditingCommand(_ command: TextEditingCommand)
}

extension WindowController {
    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool {
        textEditingCommandResponder()?.canPerformTextEditingCommand(command)
            == true
    }

    func performTextEditingCommand(_ command: TextEditingCommand) {
        textEditingCommandResponder()?.performTextEditingCommand(command)
    }

    private func textEditingCommandResponder()
        -> (any TextEditingCommandResponder)? {
        guard let focusedResponder else { return nil }
        for responder in focusedResponder.sequence {
            if let responder = responder as? any TextEditingCommandResponder {
                return responder
            }
        }
        return nil
    }
}

private struct TextEditingCommandItemModifier: ViewModifier {
    var command: TextEditingCommand
    var tag: Int?

    func body(content: Content) -> some View {
        content.transformPlatformItemList(
            AllPlatformItemListFlags.self
        ) { list in
            list.modify { item in
                item.textEditingCommand = command
                item.platformTag = tag
            }
        }
    }
}

private struct TextEditingFindMenuValidationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.transformPlatformItemList(
            AllPlatformItemListFlags.self
        ) { list in
            list.modify { menuItem in
                menuItem.children?.modify { item in
                    guard let command = item.textEditingCommand else { return }
                    item.isEnabled = item.isEnabled
                        && canPerformRootTextEditingCommand(command)
                }
            }
        }
    }
}

private func canPerformRootTextEditingCommand(
    _ command: TextEditingCommand
) -> Bool {
    appContext?.appWindowsController?
        .canPerformRootTextEditingCommand(command) == true
}

private func performRootTextEditingCommand(_ command: TextEditingCommand) {
    appContext?.appWindowsController?
        .performRootTextEditingCommand(command)
}
