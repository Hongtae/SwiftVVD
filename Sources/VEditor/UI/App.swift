//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

@main
struct GameEditorApp: App {
    var body: some Scene {
        WindowGroup("VEditor") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .defaultPosition(.zero)
        .commands {
            VEditorCommands()
        }
    }
}
