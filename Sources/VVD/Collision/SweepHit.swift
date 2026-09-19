//
//  File: SweepHit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Collision-space geometry produced by a translational primitive sweep.
public struct SweepHit: Hashable {
    /// The stationary collider reached by the moving query primitive.
    public let collider: Collider
    /// The first-impact fraction along the supplied translation, in `0...1`.
    public let fraction: Scalar
    /// Surface point on the moving primitive in collision-space coordinates.
    public let pointOnMoving: Vector3
    /// Surface point on `collider` in collision-space coordinates.
    public let pointOnCollider: Vector3
    /// Unit direction from the moving primitive toward `collider` at impact.
    public let normal: Vector3
    /// Physical distance traveled by the query origin at impact.
    public let distance: Scalar

    public init(collider: Collider,
                fraction: Scalar,
                pointOnMoving: Vector3,
                pointOnCollider: Vector3,
                normal: Vector3,
                distance: Scalar) {
        self.collider = collider
        self.fraction = fraction
        self.pointOnMoving = pointOnMoving
        self.pointOnCollider = pointOnCollider
        self.normal = normal
        self.distance = distance
    }
}
