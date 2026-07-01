//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct Window<Content>: Scene where Content: View {
    var title: Text
    var titleKey: LocalizedStringKey?
    var id: String
    var content: Content

    public var body: some Scene {
        SingleWindowScene(content: self.content, title: self.title)
    }

    public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) {
        self.title = Text(titleKey)
        self.id = id
        self.content = content()
    }

    public init<S>(_ title: S, id: String, @ViewBuilder content: () -> Content) where S: StringProtocol {
        self.title = Text(title)
        self.id = id
        self.content = content()
    }
}

struct SingleWindowScene<Content>: _PrimitiveScene where Content: View {
    var content: Content
    var title: Text

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeScene called outside an active _AGGraph context.")
        }
        let windowKey = WindowKey(namespace: .app, sceneID: SceneID(Content.self, index: 0))
        let contentGraph = scene[\.content]
        let titleGraph = scene[\.title]
        let item = SceneList.Item(windowKey: windowKey, kind: .single) {
            WindowController(content: contentGraph, title: titleGraph, scene: windowKey)
        }
        let itemsAttr: Attribute<[SceneList.Item]> = graph.makeRule { [item] in [item] }

        var outputs = PreferencesOutputs()
        outputs.append(SceneList.Key.self, node: itemsAttr.identifier)
        return _SceneOutputs(preferences: outputs)
    }
}

