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

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid else { return nil }

        let halfHeight = height * Scalar(0.5)
        let axisPoint = Vector3(
            0,
            point.y.clamp(min: -halfHeight, max: halfHeight),
            0)
        let offset = point - axisPoint
        let length = offset.length
        let normal = length > .ulpOfOne
            ? offset / length
            : Vector3(1, 0, 0)
        return PrimitiveClosestPoint(position: axisPoint + normal * radius,
                                     normal: normal,
                                     distance: abs(length - radius))
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

        func testCylinderSide(parameter: Scalar) {
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
            testCylinderSide(parameter: parameters.near)
            testCylinderSide(parameter: parameters.far)
        }

        func testHemisphere(centerY: Scalar, isTop: Bool) {
            let center = Vector3(0, centerY, 0)
            let offset = ray.origin - center
            guard let parameters = _quadraticRayParameters(
                a: ray.direction.lengthSquared,
                b: Vector3.dot(offset, ray.direction),
                c: offset.lengthSquared - radius * radius)
            else { return }

            func test(parameter: Scalar) {
                let position = ray.point(at: parameter)
                guard isTop ? position.y >= halfHeight : position.y <= -halfHeight else {
                    return
                }
                _updateClosestRayHit(ray: ray,
                                     parameter: parameter,
                                     normal: position - center,
                                     closest: &closest)
            }
            test(parameter: parameters.near)
            test(parameter: parameters.far)
        }

        testHemisphere(centerY: halfHeight, isTop: true)
        testHemisphere(centerY: -halfHeight, isTop: false)
        return closest
    }
}

public struct CapsuleShape: ConvexShape {
    public let primitive: Capsule

    public init(_ primitive: Capsule) {
        self.primitive = primitive
    }
}
