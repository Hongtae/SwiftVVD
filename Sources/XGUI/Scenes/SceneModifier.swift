//
//  File: SceneModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _SceneModifier_Content<Modifier> where Modifier: _SceneModifier {
    public typealias Body = Never
}

extension _SceneModifier_Content: Scene {
    public var body: Never { neverBody() }
}

public protocol _SceneModifier {
    associatedtype Body: Scene
    @SceneBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _SceneModifier_Content<Self>
}

extension _SceneModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body { neverBody() }
}

extension _SceneModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ModifiedContent: Scene where Content: Scene, Modifier: _SceneModifier {
    public var body: Never { neverBody() }
}

extension ModifiedContent: _PrimitiveScene where Content: Scene, Modifier: _SceneModifier {
    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy {
        var modifiers = modifiers
        modifiers.append(self.modifier)
        return _makeSceneProxy(self.content, modifiers: modifiers)
    }
}

extension ModifiedContent: _SceneModifier where Content: _SceneModifier, Modifier: _SceneModifier {
}

extension Scene {
    func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}
