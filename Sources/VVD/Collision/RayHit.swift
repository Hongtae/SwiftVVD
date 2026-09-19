//
//  File: RayHit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Result produced by a collision-space ray query.
public struct RayHit {
    public let collider: Collider
    public let position: Vector3
    public let normal: Vector3
    public let distance: Scalar

    public init(collider: Collider,
                position: Vector3,
                normal: Vector3,
                distance: Scalar) {
        self.collider = collider
        self.position = position
        self.normal = normal
        self.distance = distance
    }
}
