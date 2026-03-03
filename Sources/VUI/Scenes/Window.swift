//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        fatalError("Implement with AG")
    }
}

class SingleWindowSceneContext<Content> where Content: View {
    typealias Scene = SingleWindowScene<Content>
    var window: WindowContext?

    init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        defer {
            self.window = SceneWindowContext(content: graph[\.content], title: graph[\.title], scene: self)
        }
    }
}


class SceneWindowContext<Content>: GenericWindowContext<Content> where Content: View {
    let titleGraph: _GraphValue<Text>
    var _title: String = ""

    override var title: String { _title }
    override var style: PlatformWindowStyle { .genericWindow }

    init(content: _GraphValue<Content>, title: _GraphValue<Text>, scene: Any) {
        self.titleGraph = title
        super.init(content: content, scene: scene)
    }

    override func updateContent() {
        fatalError("Implement with AG")
    }
}

extension SceneWindowContext: @unchecked Sendable {
}
