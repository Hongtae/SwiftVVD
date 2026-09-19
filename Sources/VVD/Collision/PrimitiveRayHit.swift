//
//  File: PrimitiveRayHit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Ray intersection geometry expressed in a collision primitive's local space.
public struct PrimitiveRayHit: Hashable, Sendable {
    /// The nonnegative parameter in `ray.origin + ray.direction * parameter`.
    public let parameter: Scalar
    /// The local-space point on the primitive.
    public let position: Vector3
    /// The unit-length local-space outward surface normal.
    public let normal: Vector3

    public init(parameter: Scalar, position: Vector3, normal: Vector3) {
        self.parameter = parameter
        self.position = position
        self.normal = normal
    }
}
