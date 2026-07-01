//
//  File: UpdateFrameRate.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _UpdateFrameRate: _SceneModifier {
    public typealias Body = Never

    var active: CGFloat = 60.0
    var inactive: CGFloat = 30.0
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeScene called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        let configAttr: Attribute<_RuntimeWindowConfig> = graph.makeRule {
            let m = modifier._attribute.value
            return _RuntimeWindowConfig(activeFrameRate: m.active,
                                        inactiveFrameRate: m.inactive)
        }
        outputs.preferences.append(_RuntimeWindowConfig.Key.self, node: configAttr.identifier)
        return outputs
    }
}

extension Scene {
    public func updateFrameRate(forActiveState active: CGFloat,
                                forInactiveState inactive: CGFloat) -> some Scene {
        let modifier = _UpdateFrameRate(active: active, inactive: inactive)
        return self.modifier(modifier)
    }
}
