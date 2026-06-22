//
//  File: Capsule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Capsule: ConvexPrimitive {
    public let radius: Scalar
    public let height: Scalar
    public var isValid: Bool { radius >= .zero && height >= .zero }
    public var bounds: AABB {
        if isValid {
            let halfHeight = height * Scalar(0.5)
            return AABB(center: .zero, halfExtents: Vector3(radius, halfHeight + radius, radius))
        }
        return .null
    }

    public init(radius: Scalar, height: Scalar) {
        self.radius = radius
        self.height = height
    }

    public func contains(_ point: Vector3) -> Bool {
        if isValid {
            let halfHeight = height * Scalar(0.5)
            let closestY = point.y.clamp(min: -halfHeight, max: halfHeight)
            let closest = Vector3(0, closestY, 0)
            return (point - closest).lengthSquared <= radius * radius
        }
        return false
    }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1.0
    }
}

public struct CapsuleShape: ConvexShape {
    public let primitive: Capsule

    public init(_ primitive: Capsule) {
        self.primitive = primitive
    }
}
