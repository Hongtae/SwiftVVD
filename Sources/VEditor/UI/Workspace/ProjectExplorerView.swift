//
//  File: ProjectExplorerView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct ProjectExplorerView: View {
    let workspace: EditorWorkspace
    @Binding var selection: EditorFile.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Project Explorer")
                    .font(.system(.headline))
                Text(workspace.projectName)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }
            .padding(12)

            Divider()

            List(selection: $selection) {
                Section("Project") {
                    ForEach(workspace.files) { file in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                            Text(file.path)
                                .font(.system(.caption2))
                                .foregroundColor(.secondary)
                        }
                        .tag(file.id)
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(Color.secondary.opacity(0.05))
    }
}
