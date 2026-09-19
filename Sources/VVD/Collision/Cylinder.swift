//
//  File: Cylinder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Cylinder: ConvexPrimitive {
    public let radius: Scalar
    public let height: Scalar
    public var isValid: Bool { radius >= .zero && height >= .zero }
    public var bounds: AABB {
        isValid ? AABB(center: .zero, halfExtents: Vector3(radius, height * Scalar(0.5), radius)) : .null
    }

    public init(radius: Scalar, height: Scalar) {
        self.radius = radius
        self.height = height
    }

    public func contains(_ point: Vector3) -> Bool {
        isValid &&
        abs(point.y) <= height * Scalar(0.5) &&
        point.x * point.x + point.z * point.z <= radius * radius
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        let halfHeight = height * Scalar(0.5)
        var closest: PrimitiveRayHit?

        let radialDirectionSquared = ray.direction.x * ray.direction.x +
            ray.direction.z * ray.direction.z
        let radialProjection = ray.origin.x * ray.direction.x +
            ray.origin.z * ray.direction.z
        let radialConstant = ray.origin.x * ray.origin.x +
            ray.origin.z * ray.origin.z - radius * radius

        func testSide(parameter: Scalar) {
            let position = ray.point(at: parameter)
            if position.y >= -halfHeight && position.y <= halfHeight {
                _updateClosestRayHit(
                    ray: ray,
                    parameter: parameter,
                    normal: Vector3(position.x, 0, position.z),
                    closest: &closest)
            }
        }

        if let parameters = _quadraticRayParameters(
            a: radialDirectionSquared,
            b: radialProjection,
            c: radialConstant) {
            testSide(parameter: parameters.near)
            testSide(parameter: parameters.far)
        }

        if abs(ray.direction.y) > .ulpOfOne {
            func testCap(capY: Scalar, normalY: Scalar) {
                let parameter = (capY - ray.origin.y) / ray.direction.y
                let position = ray.point(at: parameter)
                let radialSquared = position.x * position.x + position.z * position.z
                if radialSquared <= radius * radius {
                    _updateClosestRayHit(ray: ray,
                                         parameter: parameter,
                                         normal: Vector3(0, normalY, 0),
                                         closest: &closest)
                }
            }
            testCap(capY: halfHeight, normalY: 1)
            testCap(capY: -halfHeight, normalY: -1)
        }
        return closest
    }
}

public struct CylinderShape: ConvexShape {
    public let primitive: Cylinder

    public init(_ primitive: Cylinder) {
        self.primitive = primitive
    }
}
