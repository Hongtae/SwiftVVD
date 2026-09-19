//
//  File: RayHit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Collision-space geometry produced by a collider ray query.
public struct RayHit {
    public let collider: Collider
    /// The intersection point in collision-space coordinates.
    public let position: Vector3
    /// The unit-length outward normal in collision-space coordinates.
    public let normal: Vector3
    /// The physical distance from the ray origin to `position`.
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
