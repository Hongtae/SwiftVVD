//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

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
        _SceneOutputs(scene: UnarySceneGenerator(graph: scene, inputs: inputs) { graph, inputs in
            SingleWindowSceneContext<Content>(graph: graph, inputs: inputs)
        })
    }
}

class SingleWindowSceneContext<Content>: TypedSceneContext<SingleWindowScene<Content>> where Content: View {
    typealias Scene = SingleWindowScene<Content>
    var window: WindowContext?

    override init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        defer {
            self.window = GenericWindowContext(content: graph[\.content], title: graph[\.title], scene: self)
        }
        super.init(graph: graph, inputs: inputs)
    }

    override func updateContent() {
        super.updateContent()
        if self.content != nil {
            self.window?.updateContent()
        }
    }

    override var windows: [WindowContext] {
        [window].compactMap(\.self)
    }

    override var primaryWindows: [WindowContext] {
        [window].compactMap(\.self)
    }

    override var isValid: Bool {
        if super.isValid {
            if let window {
                return window.isValid
            }
        }
        return false
    }
}
