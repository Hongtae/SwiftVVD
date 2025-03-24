//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private var defaultWindowTitle: Text { Text("XGUI.WindowGroup") }

public struct WindowGroup<Content> : Scene where Content : View {

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

struct WindowGroupScene<Content> : _PrimitiveScene where Content : View {
    var content: Content
    var title: Text

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        _SceneOutputs(scene: UnarySceneGenerator(graph: scene, inputs: inputs) { graph, inputs in
            WindowGroupSceneContext<Content>(graph: graph, inputs: inputs)
        })
    }
}

class WindowGroupSceneContext<Content> : TypedSceneContext<WindowGroupScene<Content>> where Content : View {
    typealias Scene = WindowGroupScene<Content>
    var window: WindowContext?

    override init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        defer {
            self.window = GroupWindowContext(dataType: nil, content: graph[\.content], title: graph[\.title], scene: self)
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

class GroupWindowContext<Content> : GenericWindowContext<Content> where Content : View {
    let dataType: Any.Type?
    init(dataType: Any.Type?, content: _GraphValue<Content>, title: _GraphValue<Text>, scene: SceneContext) {
        self.dataType = dataType
        super.init(content: content, title: title, scene: scene)
    }
}

extension GroupWindowContext : @unchecked Sendable {
}
