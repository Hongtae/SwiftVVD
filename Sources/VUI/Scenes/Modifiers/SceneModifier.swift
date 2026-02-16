//
//  File: SceneModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//


public struct _SceneModifier_Content<Modifier>: Scene where Modifier: _SceneModifier {
    public typealias Body = Never

    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        if let body = _SceneModifierBodyContext.body[ObjectIdentifier(self)]?.makeScene {
            return body(_Graph(), inputs)
        }
        fatalError("Unable to get scene body of \(Modifier.self)")
    }
}

extension _SceneModifier_Content: _PrimitiveScene {
}

private struct _SceneModifierBodyContext {
    struct _Body: @unchecked Sendable {
        let makeScene: ((_Graph, _SceneInputs) -> _SceneOutputs)?
    }

    @TaskLocal
    static var body: [ObjectIdentifier: _Body] = [:]
}

public protocol _SceneModifier {
    associatedtype Body: Scene
    @SceneBuilder func body(content: Self.SceneContent) -> Self.Body
    typealias SceneContent = _SceneModifier_Content<Self>
    static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs
}

extension _SceneModifier where Self.Body == Never {
    public func body(content: Self.SceneContent) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension _SceneModifier {
    var _content: Self.Body {
        body(content: _SceneModifier_Content())
    }

    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var value = _SceneModifierBodyContext.body
        value[ObjectIdentifier(Self.self)] = _SceneModifierBodyContext._Body(makeScene: body)
        return _SceneModifierBodyContext.$body.withValue(value) {
            Body._makeScene(scene: modifier[\._content], inputs: inputs)
        }
    }
}

extension _SceneModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        var graphInputs = _GraphInputs(sharedContext: nil,
                                       environment: inputs.environment)
        Self._makeInputs(modifier: modifier, inputs: &graphInputs)

        var inputs = inputs
        inputs.modifiers.append(contentsOf: graphInputs.modifiers)
        return body(_Graph(), inputs)
    }
}

extension EmptyModifier: _SceneModifier {
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        body(_Graph(), inputs)
    }
}

extension _SceneModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ModifiedContent: Scene where Content: Scene, Modifier: _SceneModifier {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }

    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        Modifier._makeScene(modifier: scene[\.modifier], inputs: inputs) { _, inputs in
            Content._makeScene(scene: scene[\.content], inputs: inputs)
        }
    }
}

extension ModifiedContent: _SceneModifier where Content: _SceneModifier, Modifier: _SceneModifier {
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        Modifier._makeScene(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeScene(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }
}

extension Scene {
    func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}
