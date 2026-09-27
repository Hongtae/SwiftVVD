//
//  File: ContentView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct ContentView: View {
    private let workspace = EditorWorkspace.sample
    @State private var selectedFileID =
        EditorWorkspace.sample.initialSelectedFileID

    var body: some View {
        EditorWorkspaceView(
            workspace: workspace,
            selectedFileID: $selectedFileID
        )
    }
}
