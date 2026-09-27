//
//  File: LogPaneView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VUI

struct LogPaneView: View {
    let entries: [EditorLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Log")
                    .font(.system(.headline))
                Spacer()
                Text("\(entries.count) messages")
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.level.rawValue)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundColor(color(for: entry.level))
                                .frame(width: 64, alignment: .leading)

                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.secondary.opacity(0.035))
    }

    private func color(for level: EditorLogEntry.Level) -> Color {
        switch level {
        case .info:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
