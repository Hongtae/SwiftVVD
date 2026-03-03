//
//  File: DefaultPositionModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Scene {
    public func defaultPosition(_ position: UnitPoint) -> some Scene {
        modifier(TransformSceneListModifier { items in
            for i in items.indices where items[i].sceneConfiguration.defaultPosition == nil {
                items[i].sceneConfiguration.defaultPosition = position
            }
        })
    }
}
