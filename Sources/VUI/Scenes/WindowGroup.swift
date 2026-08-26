//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private var defaultWindowTitle: Text { Text("VUI.WindowGroup") }

public struct WindowGroup<Content>: Scene where Content: View {

    let content: ()->Content
    let contextType: Any.Type
    let title: Text
    let identifier: String

    public var body: some Scene {
        WindowGroupScene(content: self.content(), title: self.title)
    }

    public init(@ViewBuilder makeContent: @escaping () -> Content) {
        self.content = makeContent
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = ""
    }

    public init(id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.content = makeContent
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = id
    }

    public init(_ title: Text, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = title
        self.content = makeContent
        self.contextType = Never.self
        self.identifier = ""
    }

    public init(_ title: Text, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = title
        self.identifier = id
        self.content = makeContent
        self.contextType = Never.self
    }
}

extension WindowGroup {
    public init(_ title: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = Text(title)
        self.identifier = ""
        self.content = makeContent
        self.contextType = Never.self
    }

    public init(_ title: String, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = Text(title)
        self.identifier = id
        self.content = makeContent
        self.contextType = Never.self
    }
}

struct WindowGroupScene<Content>: _PrimitiveScene where Content: View {
    var content: Content
    var title: Text

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeScene called outside an active _AGGraph context.")
        }
        // One window slot per Content type. AppGraph subscribes to this preference
        // and creates/destroys a WindowController when the value changes.
        let windowKey = WindowKey(namespace: .app, sceneID: SceneID(Content.self, index: 0))
        let contentGraph = scene[\.content]
        let titleGraph = scene[\.title]
        let sceneEnvironment = inputs.base.cachedEnvironment.value.environment
        let item = SceneList.Item(windowKey: windowKey, kind: .main) { environment in
            let wc = WindowController(
                content: contentGraph,
                title: titleGraph,
                scene: windowKey,
                environment: environment
            )
            var configuration = wc.baseConfiguration
            configuration.backgroundColor = BackendColor(
                rgba8: .init(r: 255, g: 255, b: 241, a: 255)
            )
            wc.baseConfiguration = configuration
            return wc
        }
        let itemsAttr: Attribute<[SceneList.Item]> = graph.makeRule {
            var item = item
            item.environment = sceneEnvironment.value
            return [item]
        }

        var outputs = PreferencesOutputs()
        outputs.append(SceneList.Key.self, node: itemsAttr.identifier)
        return _SceneOutputs(preferences: outputs)
    }
}
