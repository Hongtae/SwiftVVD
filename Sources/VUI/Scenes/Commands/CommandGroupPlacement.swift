//
//  File: CommandGroupPlacement.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// The placement owns immutable Text and UUID values. Text's storage is treated
// as immutable while the placement crosses command-building isolation domains.
public struct CommandGroupPlacement: @unchecked Sendable {
    let name: Text
    let id: UUID

    init(_ name: Text, id: UUID) {
        name.assertUnstyled("init(_:id:)")
        self.name = name
        self.id = id
    }

    private init(_ name: String) {
        self.init(Text(verbatim: name), id: UUID())
    }

    public static let appInfo = CommandGroupPlacement("App Info")
    public static let appSettings = CommandGroupPlacement("App Settings")
    public static let systemServices = CommandGroupPlacement("System Services")
    public static let appVisibility = CommandGroupPlacement("App Visibility")
    public static let appTermination = CommandGroupPlacement("App Termination")
    public static let newItem = CommandGroupPlacement("New Item")
    public static let saveItem = CommandGroupPlacement("Save Item")
    public static let importExport = CommandGroupPlacement("Import/Export Item")
    public static let printItem = CommandGroupPlacement("Print Item")
    public static let undoRedo = CommandGroupPlacement("Undo/Redo")
    public static let pasteboard = CommandGroupPlacement("Pasteboard")
    public static let textEditing = CommandGroupPlacement("Text Editing")
    public static let textFormatting = CommandGroupPlacement("Text Formatting")
    public static let toolbar = CommandGroupPlacement("Toolbar")
    public static let sidebar = CommandGroupPlacement("Sidebar")
    public static let windowSize = CommandGroupPlacement("Window Size")
    public static let windowList = CommandGroupPlacement("Window List")
    public static let singleWindowList = CommandGroupPlacement("Singleton Window List")
    public static let windowArrangement = CommandGroupPlacement("Window Arrangement")
    public static let help = CommandGroupPlacement("Help")
}
