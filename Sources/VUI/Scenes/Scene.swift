//
//  File: Scene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }
    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs
}

extension Scene {
    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        Body._makeScene(scene: scene[\.body], inputs: inputs)
    }
}

extension Never: Scene {
}

protocol _PrimitiveScene: Scene {
}

extension _PrimitiveScene {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

/// The bundle of AG context Attributes passed into a Scene's `_makeScene` call.
public struct _SceneInputs {
    /// Shared graph-level inputs (time, environment, transaction, …).
    var base: _GraphInputs

    /// Preference inputs for aggregating preference values up the scene tree.
    var preferences: PreferencesInputs
}

/// The AG nodes produced by a scene's `_makeScene` call.
public struct _SceneOutputs {
    /// Preference outputs accumulated from the scene subtree.
    var preferences: PreferencesOutputs
}

/// Activation state of a scene window.
public enum SceneActivationState {
    case foregroundActive
    case foregroundInactive
    case background
}
