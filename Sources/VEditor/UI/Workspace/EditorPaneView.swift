//
//  File: EditorPaneView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct EditorPaneView: View {
    let file: EditorFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(file?.name ?? "Editor")
                    .font(.system(.headline))
                Spacer()
                if let file {
                    Text(file.kind.rawValue)
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)

            Divider()

            if let file {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(file.previewLines.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .trailing)

                                Text(
                                    file.previewLines[index].isEmpty
                                        ? " "
                                        : file.previewLines[index]
                                )
                                .font(.system(size: 13, design: .monospaced))
                            }
                        }
                    }
                    .padding(16)
                    .frame(
                        minWidth: 520,
                        maxWidth: .infinity,
                        alignment: .topLeading
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Text("No File Selected")
                        .font(.system(.headline))
                    Text("Choose a file in Project Explorer.")
                        .foregroundColor(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
    }
}
