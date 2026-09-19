//
//  File: CollisionPrimitive.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol CollisionPrimitive: Hashable {
    var bounds: AABB { get }
    var isValid: Bool { get }

    func contains(_ point: Vector3) -> Bool

    /// Returns the closest represented surface point to a local-space query.
    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint?

    /// Returns the closest surface intersection with a nonnegative ray
    /// parameter. A ray that starts inside a closed primitive returns its exit
    /// intersection. The result is expressed in the primitive's local space.
    func rayTest(_ ray: Ray) -> PrimitiveRayHit?
}

public protocol ConvexPrimitive: CollisionPrimitive {
}

public protocol ConcavePrimitive: CollisionPrimitive {
}

/// A typed construction layer for a collision primitive.
///
/// Runtime collision dispatch uses the concrete primitive type. A collider
/// created from a shape stores the shape's primitive representation.
public protocol CollisionShape<Primitive>: Hashable {
    associatedtype Primitive: CollisionPrimitive

    var primitive: Primitive { get }
    var bounds: AABB { get }
    var isValid: Bool { get }

    func contains(_ point: Vector3) -> Bool

    /// Forwards the local-space closest-surface query to `primitive`.
    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint?

    /// Forwards the local-space ray query to `primitive`.
    func rayTest(_ ray: Ray) -> PrimitiveRayHit?
}

public extension CollisionShape {
    var bounds: AABB { primitive.bounds }
    var isValid: Bool { primitive.isValid }

    func contains(_ point: Vector3) -> Bool {
        primitive.contains(point)
    }

    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        primitive.closestPoint(to: point)
    }

    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        primitive.rayTest(ray)
    }
}

public protocol ConvexShape<Primitive>: CollisionShape where Primitive: ConvexPrimitive {
}

public protocol ConcaveShape<Primitive>: CollisionShape where Primitive: ConcavePrimitive {
}
