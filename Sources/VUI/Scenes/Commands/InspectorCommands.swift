//
//  File: InspectorCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct InspectorPresentedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var inspectorPresented: Binding<Bool>? {
        get { self[InspectorPresentedKey.self] }
        set { self[InspectorPresentedKey.self] = newValue }
    }
}

public struct InspectorCommands: Commands {
    @FocusedBinding(\.inspectorPresented)
    private var inspectorPresented

    public init() {}

    private var labelText: String {
        inspectorPresented == true ? "Hide" : "Show"
    }

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button {
                inspectorPresented?.toggle()
            } label: {
                Label(
                    "\(labelText) Inspector",
                    systemImage: "sidebar.trailing"
                )
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(inspectorPresented == nil)
        }
    }
}

@available(*, unavailable)
extension InspectorCommands: Sendable {
}
