//
//  File: CommandGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct CommandGroup<Content>: Commands where Content: View {
    var change: CommandOperation

    public init(
        before group: CommandGroupPlacement,
        @ViewBuilder addition: () -> Content
    ) {
        change = CommandOperation(
            mutation: .prepend,
            placement: group,
            content: addition()
        )
    }

    public init(
        after group: CommandGroupPlacement,
        @ViewBuilder addition: () -> Content
    ) {
        change = CommandOperation(
            mutation: .append,
            placement: group,
            content: addition()
        )
    }

    public init(
        replacing group: CommandGroupPlacement,
        @ViewBuilder addition: () -> Content
    ) {
        change = CommandOperation(
            mutation: .replace,
            placement: group,
            content: addition()
        )
    }

    nonisolated public static func _makeCommands(
        content: _GraphValue<Self>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("CommandGroup._makeCommands called outside _AGGraph context")
        }
        let list = graph.makeRule(MakeList(commandGroup: content._attribute))
        var preferences = PreferencesOutputs()
        preferences.makePreferenceWriter(
            inputs: inputs.preferences,
            key: CommandsList.Key.self,
            value: list
        )
        return _CommandsOutputs(preferences: preferences)
    }

    public var body: some Commands {
        EmptyCommands()
    }

    public func _resolve(into resolved: inout _ResolvedCommands) {
        change.resolver?(change, &resolved)
    }

    private struct MakeList: Rule {
        var commandGroup: Attribute<CommandGroup>

        var value: CommandsList {
            CommandsList(items: [
                CommandsList.Item(
                    value: .operation(commandGroup.value.change),
                    version: DisplayList.Version(forUpdate: ())
                )
            ])
        }
    }
}
