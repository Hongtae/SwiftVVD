//
//  File: PrimitiveClosestPoint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Closest surface geometry expressed in a collision primitive's local space.
public struct PrimitiveClosestPoint: Hashable, Sendable {
    /// The closest point on the represented primitive surface.
    public let position: Vector3
    /// The unit-length outward surface normal. Open surfaces use their winding
    /// or declared normal orientation.
    public let normal: Vector3
    /// The nonnegative Euclidean distance from the query point to `position`.
    public let distance: Scalar

    public init(position: Vector3, normal: Vector3, distance: Scalar) {
        self.position = position
        self.normal = normal
        self.distance = distance
    }
}
