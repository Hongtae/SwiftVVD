//
//  File: InspectorPaneView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct InspectorPaneView: View {
    let file: EditorFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.system(.headline))
                .padding(12)

            Divider()

            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Selected File") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Name", value: file.name)
                            LabeledContent("Type", value: file.kind.rawValue)
                            LabeledContent("Path", value: file.path)
                        }
                    }

                    GroupBox("Editor") {
                        Text("Type-specific properties will appear here.")
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Text("Nothing Selected")
                        .font(.system(.headline))
                    Text("Select a project file to inspect it.")
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
        .background(Color.secondary.opacity(0.05))
    }
}
