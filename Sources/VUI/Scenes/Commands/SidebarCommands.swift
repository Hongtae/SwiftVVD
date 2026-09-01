//
//  File: SidebarCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct SidebarCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("Show Sidebar") {
                performRootSidebarCommand()
            }
            .builtInKeyboardShortcut(.sidebarToggle)
            .modifier(RootSidebarCommandValidationModifier())
        }
    }
}

@available(*, unavailable)
extension SidebarCommands: Sendable {}

private struct RootSidebarCommandValidationModifier: ViewModifier {
    private var context: RootSidebarCommandContext? {
        appContext?.appWindowsController?.activeRootSidebarCommandContext
    }

    func body(content: Content) -> some View {
        let context = context
        let title = context?.isSidebarVisible == true
            ? "Hide Sidebar"
            : "Show Sidebar"
        let isEnabled = context != nil

        return content
            .disabled(!isEnabled)
            .transformPlatformItemList(
                AllPlatformItemListFlags.self
            ) { list in
                list.modify { item in
                    // Resolve the active root again when selected so an old
                    // menu snapshot cannot target an inactive split view.
                    item.isEnabled = item.isEnabled && isEnabled
                    if var selection = item.selectionBehavior {
                        selection.onSelect = isEnabled ? {
                            performRootSidebarCommand()
                        } : nil
                        item.selectionBehavior = selection
                    }
                    item.label = NSAttributedString(string: title)
                }
            }
    }
}

private func performRootSidebarCommand() {
    appContext?.appWindowsController?.performRootSidebarCommand()
}
