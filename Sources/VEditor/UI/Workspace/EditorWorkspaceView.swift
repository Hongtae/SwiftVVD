//
//  File: EditorWorkspaceView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct EditorWorkspaceView: View {
    let workspace: EditorWorkspace
    @Binding var selectedFileID: EditorFile.ID?

    private var selectedFile: EditorFile? {
        workspace.file(id: selectedFileID)
    }

    var body: some View {
        HSplitView {
            ProjectExplorerView(
                workspace: workspace,
                selection: $selectedFileID
            )
            .frame(
                minWidth: 180,
                idealWidth: 240,
                maxWidth: 360,
                maxHeight: .infinity
            )

            VSplitView {
                HSplitView {
                    EditorPaneView(file: selectedFile)
                        .frame(
                            minWidth: 420,
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )

                    InspectorPaneView(file: selectedFile)
                        .frame(
                            minWidth: 220,
                            idealWidth: 280,
                            maxWidth: 420,
                            maxHeight: .infinity
                        )
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 280,
                    idealHeight: 540,
                    maxHeight: .infinity
                )

                LogPaneView(entries: workspace.logs)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 100,
                        idealHeight: 180,
                        maxHeight: 320
                    )
            }
            .frame(
                minWidth: 520,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .frame(
            minWidth: 960,
            maxWidth: .infinity,
            minHeight: 640,
            maxHeight: .infinity
        )
    }
}
