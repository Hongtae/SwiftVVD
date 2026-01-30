//
//  File: UpdateFrameRate.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _UpdateFrameRate: _SceneModifier {
    public typealias Body = Never

    var active: CGFloat = 60.0
    var inactive: CGFloat = 30.0
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        var inputs = inputs
        inputs.setModifierTypeGraph(modifier)
        return body(_Graph(), inputs)
    }
}

extension Scene {
    public func updateFrameRate(forActiveState active: CGFloat,
                                forInactiveState inactive: CGFloat) -> some Scene {
        let modifier = _UpdateFrameRate(active: active, inactive: inactive)
        return self.modifier(modifier)
    }
}
