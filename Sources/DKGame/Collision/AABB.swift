//
//  File: AABB.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct AABB {
    public let min: Vector3
    public let max: Vector3

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }
}
