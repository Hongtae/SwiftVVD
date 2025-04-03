//
//  File: SceneContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

class SceneContext: _GraphValueResolver {
    unowned var parent: SceneContext?
    var inputs: _SceneInputs
    var environment: EnvironmentValues
    var properties: PropertyList
    var requiresContentUpdates = false

    var root: any SceneRoot {
        inputs.root
    }

    var app: AppContext {
        root.app
    }

    var isValid: Bool { false }

    init(inputs: _SceneInputs) {
        self.inputs = inputs
        self.environment = inputs.environment
        self.properties = inputs.properties
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

    func resetGraphInputModifiers() {
        self.inputs.resetModifiers()
    }

    func resolveGraphInputs() {
        do {
            self.environment = self.inputs.environment
            self.properties = self.inputs.properties

            var modifiers = self.inputs.modifiers
            modifiers.indices.forEach { index in
                if modifiers[index].isResolved == false {
                    modifiers[index].resolve(container: self)
                }
            }
            modifiers.forEach { modifier in
                if modifier.isResolved {
                    modifier.apply(to: &self.environment)
                }
            }
            modifiers.forEach { modifier in
                if modifier.isResolved {
                    modifier.apply(to: &self.properties)
                }
            }
            self.inputs.modifiers = modifiers
        }
    }
}

class TypedSceneContext<Content>: SceneContext where Content: Scene {
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
            self.resolveGraphInputs()
            self.updateScene(&value)
            self.requiresContentUpdates = false
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

class GenericSceneContext<Content>: TypedSceneContext<Content> where Content: Scene {
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

protocol SceneGenerator<Content> : Equatable {
    associatedtype Content
    var graph: _GraphValue<Content> { get }
    func makeScene() -> SceneContext
}

extension SceneGenerator {
    static func == (lhs: Self, rhs: some SceneGenerator) -> Bool {
        if lhs.graph == rhs.graph {
            assert(type(of: lhs) == type(of: rhs))
            return true
        }
        return false
    }
}

#if DEBUG
// Ensure that the UnarySceneGenerator always returns a SceneContext of the same type.
nonisolated(unsafe) var _debugSceneTypes: [_GraphValue<Any> : SceneContext.Type] = [:]
#endif

struct UnarySceneGenerator<Content>: SceneGenerator {
    let graph: _GraphValue<Content>
    var inputs: _SceneInputs
    let body: (_GraphValue<Content>, _SceneInputs) -> SceneContext

    func makeScene() -> SceneContext {
        let scene = body(graph, inputs)
#if DEBUG
        let key = graph.unsafeCast(to: Any.self)
        if let t = _debugViewTypes[key] {
            assert(type(of: scene) == t)
        } else {
            _debugSceneTypes[key] = type(of: scene)
        }
#endif
        return scene        
    }
}
