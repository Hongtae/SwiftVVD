//
//  File: CommandMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct CommandMenu<Content>: Commands where Content: View {
    var name: Text
    var content: Content

    public init(
        _ nameKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(Text(nameKey), content: content)
    }

    @_disfavoredOverload
    public init(
        _ name: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.init(Text(name), content: content)
    }

    public init(
        _ name: Text,
        @ViewBuilder content: () -> Content
    ) {
        name.assertUnstyled("init(_:content:)")
        self.name = name
        self.content = content()
    }

    @_disfavoredOverload
    public init<S>(
        _ name: S,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(Text(name), content: content)
    }

    nonisolated public static func _makeCommands(
        content: _GraphValue<Self>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("CommandMenu._makeCommands called outside _AGGraph context")
        }
        // The rule retains one identity while its graph value is reevaluated.
        let list = graph.makeRule(
            MakeList(commandMenu: content._attribute, id: UUID())
        )
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
        let placement = CommandGroupPlacement(name, id: UUID())
        let operation = CommandOperation(
            mutation: .topLevel,
            placement: placement,
            content: content
        )
        operation.resolver?(operation, &resolved)
    }

    private struct MakeList: Rule {
        var commandMenu: Attribute<CommandMenu>
        var id: UUID

        var value: CommandsList {
            let menu = commandMenu.value
            let placement = CommandGroupPlacement(menu.name, id: id)
            let operation = CommandOperation(
                mutation: .topLevel,
                placement: placement,
                content: menu.content
            )
            return CommandsList(items: [
                CommandsList.Item(
                    value: .operation(operation),
                    version: DisplayList.Version(forUpdate: ())
                )
            ])
        }
    }
}
