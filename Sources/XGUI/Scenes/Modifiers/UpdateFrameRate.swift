//
//  File: UpdateFrameRate.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _UpdateFrameRate: _SceneModifier {
    public typealias Body = Never

    var activeFrameRate: CGFloat = 1.0 / 60.0
    var inactiveFrameRate: CGFloat = 1.0 / 30.0
}

extension Scene {
    public func updateFrameRate(forActiveState active: CGFloat,
                                forInactiveState inactive: CGFloat) -> some Scene {
        let modifier = _UpdateFrameRate(activeFrameRate: active, inactiveFrameRate: inactive)
        return self.modifier(modifier)
    }
}
