//
//  File: DefaultSizeModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// TransformSceneListModifier — applies a transform closure to the [SceneList.Item]
// preference value produced by the inner scene subtree.
public struct TransformSceneListModifier: _SceneModifier {
    public typealias Body = Never

    let transform: (inout [SceneList.Item]) -> Void

    public static func _makeScene(
        modifier: _GraphValue<Self>,
        inputs: _SceneInputs,
        body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs
    ) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeScene called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)

        let keyID = ObjectIdentifier(SceneList.Key.self)
        guard let idx = outputs.preferences.preferences.firstIndex(where: {
            ObjectIdentifier($0.key) == keyID
        }) else {
            return outputs
        }

        let originalNode = outputs.preferences.preferences[idx].value
        let newAttr: Attribute<[SceneList.Item]> = graph.makeRule {
            let t = modifier._attribute.value
            var items = Attribute<[SceneList.Item]>(originalNode).value
            t.transform(&items)
            return items
        }

        // Replace the SceneList.Key entry with the transformed node.
        // Rebuild via append so that _makeReduceRule is correctly captured.
        var newPrefs = PreferencesOutputs()
        for kv in outputs.preferences.preferences {
            if ObjectIdentifier(kv.key) == keyID {
                newPrefs.append(SceneList.Key.self, node: newAttr.identifier)
            } else {
                newPrefs.preferences.append(kv)
            }
        }
        newPrefs.debugProperties = outputs.preferences.debugProperties
        outputs.preferences = newPrefs
        return outputs
    }
}

extension Scene {
    public func defaultSize(_ size: CGSize) -> some Scene {
        modifier(TransformSceneListModifier { items in
            for i in items.indices where items[i].sceneConfiguration.defaultSize == nil {
                items[i].sceneConfiguration.defaultSize = size
            }
        })
    }

    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        defaultSize(CGSize(width: width, height: height))
    }
}
