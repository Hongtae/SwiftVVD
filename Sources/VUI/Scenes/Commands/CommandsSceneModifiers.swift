//
//  File: CommandsSceneModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct CommandsModifier<Content: Commands>: _SceneModifier {
    var content: Content

    typealias Body = Never

    // The transformer appends this modifier's command items after the list
    // produced by the wrapped scene, preserving modifier application order.
    private struct UpdateList: Rule {
        var _list: Attribute<CommandsList>

        var value: (inout CommandsList) -> Void {
            let list = _list
            return { value in
                value.items.append(contentsOf: list.value.items)
            }
        }
    }

    static func _makeScene(
        modifier: _GraphValue<Self>,
        inputs: _SceneInputs,
        body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs
    ) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("CommandsModifier._makeScene called outside _AGGraph context")
        }
        guard inputs.preferences.keys.contains(CommandsList.Key.self) else {
            return body(_Graph(), inputs)
        }

        var commandPreferences = PreferencesInputs(
            keys: PreferenceKeys(),
            hostKeys: inputs.preferences.hostKeys
        )
        commandPreferences.add(CommandsList.Key.self)
        let commandInputs = _CommandsInputs(
            base: inputs.base,
            preferences: commandPreferences
        )
        let commandOutputs = Content._makeCommands(
            content: modifier[\.content],
            inputs: commandInputs
        )
        var outputs = body(_Graph(), inputs)
        if let list = commandOutputs.preferences.value(for: CommandsList.Key.self) {
            let transform: Attribute<(inout CommandsList) -> Void> =
                graph.makeRule(UpdateList(_list: Attribute(list)))
            outputs.preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: CommandsList.Key.self,
                transform: transform
            )
        }
        return outputs
    }
}

struct CommandsRemovedModifier: _SceneModifier {
    typealias Body = Never

    static func _makeScene(
        modifier: _GraphValue<Self>,
        inputs: _SceneInputs,
        body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs
    ) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("CommandsRemovedModifier._makeScene called outside _AGGraph context")
        }

        // Suppress command collection while the wrapped scene is constructed.
        var childInputs = inputs
        childInputs.preferences.remove(CommandsList.Key.self)
        var outputs = body(_Graph(), childInputs)

        // The scene item retains the removal decision for later host merging.
        let transform: Attribute<(inout [SceneList.Item]) -> Void> = graph.makeRule {
            { items in
                for index in items.indices {
                    items[index].options.insert(.commandsRemoved)
                }
            }
        }
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: SceneList.Key.self,
            transform: transform
        )
        return outputs
    }
}

extension Scene {
    nonisolated public func commandsRemoved() -> some Scene {
        modifier(CommandsRemovedModifier())
    }

    nonisolated public func commandsReplaced<Content>(
        @CommandsBuilder content: () -> Content
    ) -> some Scene where Content: Commands {
        modifier(CommandsRemovedModifier())
            .modifier(CommandsModifier(content: content()))
    }
}
