//
//  File: Sphere.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Sphere: ConvexPrimitive {
    public let center: Vector3
    public let radius: Scalar
    public var bounds: AABB {
        isValid ? AABB(center: center, halfExtents: Vector3(radius, radius, radius)) : .null
    }

    public init() {
        self.center = .zero
        self.radius = -Scalar.greatestFiniteMagnitude
    }

    public init(center: Vector3, radius: Scalar) {
        self.center = center
        self.radius = radius
    }

    public var isValid: Bool { radius >= 0.0 }

    // bigger sphere, union of s1, s2 merged sphere.
    public static func union(_ s1: Self, _ s2: Self) -> Self? {
        if s1.isValid && s2.isValid {
            let distance = (s1.center - s2.center).length
            if s1.radius - s2.radius >= distance {
                // s1 includes s2
                return s1
            } else if s2.radius - s1.radius >= distance {
                // s2 includes s1
                return s2
            } else {
                // new sphere's radius: distance between two sphere centers + each radius/2
                let r = (distance + s1.radius + s2.radius) * 0.5

                // new sphere's center: move from s2 to s1 with offset (new sphere's radius - radius of s2)
                let center = (s1.center - s2.center).normalized() * (r - s2.radius) + s2.center
                return Sphere(center: center, radius: r)
            }

        } else if s1.isValid {
            return s1
        } else if s2.isValid {
            return s2
        }
        // both are invalid.
        return nil
    }

    public func intersects(_ other: Self) -> Bool {
        guard self.isValid && other.isValid else { return false }

        let radiusSum = self.radius + other.radius
        return (self.center - other.center).lengthSquared <= radiusSum * radiusSum
    }

    public func isPointInside(_ pos: Vector3) -> Bool {
        contains(pos)
    }

    public func contains(_ point: Vector3) -> Bool {
        self.isValid && (point - center).lengthSquared <= (radius * radius)
    }

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid else { return nil }

        let offset = point - center
        let length = offset.length
        let normal = length > .ulpOfOne
            ? offset / length
            : Vector3(1, 0, 0)
        return PrimitiveClosestPoint(position: center + normal * radius,
                                     normal: normal,
                                     distance: abs(length - radius))
    }

    public var volume: Scalar {
        if self.isValid {
            // 4/3 PI * R cubed
            return (4.0 / 3.0) * radius * radius * radius * Scalar.pi
        }
        return 0.0
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        let offset = ray.origin - center
        let directionLengthSquared = ray.direction.lengthSquared
        let projectedOffset = Vector3.dot(offset, ray.direction)
        let constant = offset.lengthSquared - radius * radius
        let discriminant = projectedOffset * projectedOffset - directionLengthSquared * constant
        guard discriminant >= .zero else { return nil }

        let root = discriminant.squareRoot()
        let nearParameter = (-projectedOffset - root) / directionLengthSquared
        let farParameter = (-projectedOffset + root) / directionLengthSquared
        let parameter: Scalar
        if nearParameter >= .zero {
            parameter = nearParameter
        } else if farParameter >= .zero {
            parameter = farParameter
        } else {
            return nil
        }

        let position = ray.point(at: parameter)
        let surfaceOffset = position - center
        let normal = surfaceOffset.lengthSquared > .ulpOfOne
            ? surfaceOffset.normalized()
            : -ray.direction.normalized()
        return PrimitiveRayHit(parameter: parameter,
                               position: position,
                               normal: normal)
    }
}

public struct SphereShape: ConvexShape {
    public let primitive: Sphere

    public init(_ primitive: Sphere) {
        self.primitive = primitive
    }
}
