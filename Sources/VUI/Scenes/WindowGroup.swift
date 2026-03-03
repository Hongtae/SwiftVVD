//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        fatalError("Implement with AG")
    }
}

class WindowGroupSceneContext<Content> where Content: View {
    typealias Scene = WindowGroupScene<Content>
    var window: WindowContext?

    init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        defer {
            self.window = GroupWindowContext(dataType: nil, content: graph[\.content], title: graph[\.title], scene: self)
        }
    }
}

class GroupWindowContext<Content>: GenericWindowContext<Content> where Content: View {
    let dataType: Any.Type?
    
    let titleGraph: _GraphValue<Text>
    var _title: String = ""

    override var title: String { _title }
    override var style: PlatformWindowStyle { .genericWindow }

    init(dataType: Any.Type?, content: _GraphValue<Content>, title: _GraphValue<Text>, scene: Any) {
        self.dataType = dataType
        self.titleGraph = title
        super.init(content: content, scene: scene)

        //let backgroundColor = VVD.Color(rgba8: (245, 242, 241, 255))
        let backgroundColor = VVD.Color(rgba8: (255, 255, 241, 255))
        self.config.backgroundColor = backgroundColor
    }

    override func updateContent() {
        fatalError("Implement with AG")
    }
}

extension GroupWindowContext: @unchecked Sendable {
}
