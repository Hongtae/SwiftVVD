//
//  File: ToolbarCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ToolbarCommands: Commands {
    @FocusedValue(\.toolbarVisibility)
    private var toolbarVisibility

    public init() {}

    public var body: some Commands {
        CommandGroup(before: .toolbar) {
            Section {
                Button("Show Toolbar") {
                    performRootToolbarCommand(.toggleVisibility)
                }
                .builtInKeyboardShortcut(.toolbarToggleVisibility)
                .disabled(toolbarVisibility == nil)
                .modifier(
                    RootToolbarCommandValidationModifier(
                        command: .toggleVisibility
                    )
                )

                Button("Customize Toolbar…") {
                    performRootToolbarCommand(.customize)
                }
                .modifier(
                    RootToolbarCommandValidationModifier(
                        command: .customize
                    )
                )
            }
        }
    }
}

@available(*, unavailable)
extension ToolbarCommands: Sendable {
}

private struct RootToolbarCommandValidationModifier: ViewModifier {
    var command: RootToolbarCommand

    private var context: RootToolbarCommandContext? {
        appContext?.appWindowsController?.activeRootToolbarCommandContext
    }

    private var isEnabled: Bool {
        switch command {
        case .toggleVisibility:
            context?.canToggleVisibility == true
        case .customize:
            context?.canCustomize == true
        }
    }

    private var title: String? {
        guard command == .toggleVisibility else { return nil }
        return context?.visibility == .hidden
            ? "Show Toolbar"
            : "Hide Toolbar"
    }

    func body(content: Content) -> some View {
        let title = title
        let isEnabled = isEnabled
        return content
            .disabled(!isEnabled)
            .transformPlatformItemList(
                AllPlatformItemListFlags.self
            ) { list in
                list.modify { item in
                    // Replace the source action with app-level standard-command
                    // dispatch. Resolve the active root again when selected so
                    // a stale menu snapshot cannot target a window that has
                    // since become inactive.
                    item.isEnabled = item.isEnabled && isEnabled
                    if var selection = item.selectionBehavior {
                        selection.onSelect = isEnabled ? {
                            performRootToolbarCommand(command)
                        } : nil
                        item.selectionBehavior = selection
                    }
                    if let title {
                        item.label = NSAttributedString(string: title)
                    }
                }
            }
    }
}

private func performRootToolbarCommand(_ command: RootToolbarCommand) {
    appContext?.appWindowsController?.performRootToolbarCommand(command)
}
