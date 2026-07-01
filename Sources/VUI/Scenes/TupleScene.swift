//
//  File: TupleScene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct _TupleScene<T>: Scene {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    subscript<U>(keyPath: KeyPath<T, U>) -> U {
        self.value[keyPath: keyPath]
    }

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeScene called outside an active _AGGraph context.")
        }

        var childOutputsList: [_SceneOutputs] = []

        // For each Scene-typed field in T, extract a child Attribute via offset-based rule
        // (same pattern as TupleView._makeViewList), then recursively wire the child scene.
        func makeChild<S: Scene>(_: S.Type, offset: Int) {
            let childAttr: Attribute<S> = graph.makeRule {
                withUnsafeBytes(of: scene._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset).assumingMemoryBound(to: S.self).pointee
                }
            }
            let childGraph = _GraphValue<S>(_attribute: childAttr)
            childOutputsList.append(S._makeScene(scene: childGraph, inputs: inputs))
        }

        _forEachField(of: T.self) { _, offset, fieldType in
            if let sceneType = fieldType as? any Scene.Type {
                func open<S: Scene>(_: S.Type) { makeChild(S.self, offset: offset) }
                open(sceneType)
            }
            return true
        }

        // Merge preference outputs from all children.
        // Collect AGAttribute nodes per key type, then create one reduced AG node per key.
        var seenKeys: [ObjectIdentifier: (any PreferenceKey.Type, [AGAttribute])] = [:]
        for childOut in childOutputsList {
            for kv in childOut.preferences.preferences {
                let id = ObjectIdentifier(kv.key)
                if seenKeys[id] == nil { seenKeys[id] = (kv.key, []) }
                seenKeys[id]!.1.append(kv.value)
            }
        }

        var merged = PreferencesOutputs()
        for (_, (keyType, childNodes)) in seenKeys {
            func mergeKey<K: PreferenceKey>(_ kt: K.Type) {
                let childAttrs = childNodes.map { Attribute<K.Value>($0) }
                let mergedAttr: Attribute<K.Value> = graph.makeRule {
                    var result = K.defaultValue
                    for attr in childAttrs {
                        K.reduce(value: &result, nextValue: { attr.value })
                    }
                    return result
                }
                merged.append(kt, node: mergedAttr.identifier)
            }
            mergeKey(keyType)
        }

        return _SceneOutputs(preferences: merged)
    }
}

extension _TupleScene: _PrimitiveScene {
}
