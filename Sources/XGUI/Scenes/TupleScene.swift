//
//  File: TupleScene.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

struct _TupleScene<T>: Scene {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    subscript<U>(keyPath: KeyPath<T, U>) -> U {
        self.value[keyPath: keyPath]
    }

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        fatalError()
    }
}

extension _TupleScene: _PrimitiveScene {
}
