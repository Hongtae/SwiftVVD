//
//  File: SceneContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

class SceneContext : _GraphValueResolver {
    unowned var parent: SceneContext?
    var inputs: _SceneInputs

    var root: any SceneRoot {
        inputs.root
    }

    var app: AppContext {
        root.app
    }

    var isValid: Bool { false }

    init(inputs: _SceneInputs) {
        self.inputs = inputs
    }

    deinit {
        Log.debug("SceneContext(\(self)) deinit")
        assert(self.parent == nil)
    }

    func updateContent() {
        fatalError("This method must be overridden in subclasses.")
    }

    var windows: [WindowContext] {
        fatalError("This method must be overridden in subclasses.")
    }

    var primaryWindows: [WindowContext] {
        fatalError("This method must be overridden in subclasses.")
    }

    func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let parent {
            return parent.value(atPath: graph)
        }
        return root.value(atPath: graph)
    }
}

class TypedSceneContext<Content> : SceneContext where Content : Scene {
    let graph: _GraphValue<Content>
    var content: Content?

    override var windows: [any WindowContext] { [] }
    override var primaryWindows: [any WindowContext] { [] }

    init(graph: _GraphValue<Content>, inputs: _SceneInputs) {
        self.graph = graph
        super.init(inputs: inputs)
    }

    override func updateContent() {
        self.content = nil
        if var value = self.value(atPath: graph) {
            self.updateScene(&value)
            self.content = value
        } else {
            fatalError("Unable to recover scene at path \(graph)")
        }
    }

    override var isValid: Bool {
        self.content != nil
    }

    override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let content {
            return self.graph.value(atPath: graph, from: content)
        }
        return super.value(atPath: graph)
    }

    func updateScene(_ scene: inout Content) {
    }
}

class GenericSceneContext<Content> : TypedSceneContext<Content> where Content : Scene {
    var body: SceneContext? {
        willSet {
            self.body?.parent = nil
        }
        didSet {
            self.body?.parent = self
        }
    }

    deinit {
        self.body?.parent = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.content != nil {
            self.body?.updateContent()
        }
    }

    override var windows: [WindowContext] {
        self.body?.windows ?? super.windows
    }

    override var primaryWindows: [any WindowContext] {
        self.body?.primaryWindows ?? super.primaryWindows
    }

    override var isValid: Bool {
        self.body?.isValid ?? super.isValid
    }
}

protocol SceneGenerator {
    func makeScene() -> SceneContext
}

struct UnarySceneGenerator : SceneGenerator {
    var inputs: _SceneInputs
    let body: (_SceneInputs) -> SceneContext

    func makeScene() -> SceneContext {
        body(inputs)
    }
}
