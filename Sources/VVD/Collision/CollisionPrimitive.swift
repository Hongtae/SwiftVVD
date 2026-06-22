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
    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar
}

public protocol ConvexPrimitive: CollisionPrimitive {
}

public protocol ConcavePrimitive: CollisionPrimitive {
}

public protocol CollisionShape<Primitive>: Hashable {
    associatedtype Primitive: CollisionPrimitive

    var primitive: Primitive { get }
    var bounds: AABB { get }
    var isValid: Bool { get }

    func contains(_ point: Vector3) -> Bool
    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar
}

public extension CollisionShape {
    var bounds: AABB { primitive.bounds }
    var isValid: Bool { primitive.isValid }

    func contains(_ point: Vector3) -> Bool {
        primitive.contains(point)
    }

    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        primitive.rayTest(rayOrigin: origin, direction: direction)
    }
}

public protocol ConvexShape<Primitive>: CollisionShape where Primitive: ConvexPrimitive {
}

public protocol ConcaveShape<Primitive>: CollisionShape where Primitive: ConcavePrimitive {
}
