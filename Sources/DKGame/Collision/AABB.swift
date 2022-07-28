//
//  File: AABB.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct AABB {
    public let min: Vector3
    public let max: Vector3

    public var center: Vector3 { (min + max) * 0.5 }
    public var halfExtents: Vector3 { (max - min) * 0.5 }

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    public init(center: Vector3, halfExtents: Vector3) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }
}
