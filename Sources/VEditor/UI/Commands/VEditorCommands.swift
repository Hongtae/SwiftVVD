//
//  File: VEditorCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct VEditorCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
        }
        CommandGroup(after: .undoRedo) {
        }
        CommandGroup(after: .toolbar) {
        }
        CommandMenu("Tools") {
        }
        CommandGroup(after: .windowSize) {
        }
        CommandGroup(after: .help) {
        }
    }
}
