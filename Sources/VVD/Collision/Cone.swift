//
//  File: Cone.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Cone: ConvexPrimitive {
    public let radius: Scalar
    public let height: Scalar
    public var isValid: Bool { radius >= .zero && height > .ulpOfOne }
    public var bounds: AABB {
        isValid ? AABB(center: .zero, halfExtents: Vector3(radius, height * Scalar(0.5), radius)) : .null
    }

    public init(radius: Scalar, height: Scalar) {
        self.radius = radius
        self.height = height
    }

    public func contains(_ point: Vector3) -> Bool {
        guard isValid else { return false }

        let halfHeight = height * Scalar(0.5)
        guard point.y >= -halfHeight && point.y <= halfHeight else { return false }

        let radiusAtY = radius * ((halfHeight - point.y) / height)
        return point.x * point.x + point.z * point.z <= radiusAtY * radiusAtY
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        let halfHeight = height * Scalar(0.5)
        if radius.isZero {
            return rayTestAxisSegment(ray, halfHeight: halfHeight)
        }
        let slope = radius / height
        let slopeSquared = slope * slope
        let verticalOffset = halfHeight - ray.origin.y
        let a = ray.direction.x * ray.direction.x +
            ray.direction.z * ray.direction.z -
            slopeSquared * ray.direction.y * ray.direction.y
        let b = ray.origin.x * ray.direction.x +
            ray.origin.z * ray.direction.z +
            slopeSquared * verticalOffset * ray.direction.y
        let c = ray.origin.x * ray.origin.x +
            ray.origin.z * ray.origin.z -
            slopeSquared * verticalOffset * verticalOffset
        var closest: PrimitiveRayHit?

        func testSide(parameter: Scalar) {
            let position = ray.point(at: parameter)
            guard position.y >= -halfHeight && position.y <= halfHeight else {
                return
            }
            _updateClosestRayHit(
                ray: ray,
                parameter: parameter,
                normal: Vector3(position.x,
                                slopeSquared * (halfHeight - position.y),
                                position.z),
                closest: &closest)
        }

        if abs(a) > .ulpOfOne {
            if let parameters = _quadraticRayParameters(a: a, b: b, c: c) {
                testSide(parameter: parameters.near)
                testSide(parameter: parameters.far)
            }
        } else if abs(b) > .ulpOfOne {
            testSide(parameter: -c / (2 * b))
        }

        if abs(ray.direction.y) > .ulpOfOne {
            let parameter = (-halfHeight - ray.origin.y) / ray.direction.y
            let position = ray.point(at: parameter)
            let radialSquared = position.x * position.x + position.z * position.z
            if radialSquared <= radius * radius {
                _updateClosestRayHit(ray: ray,
                                     parameter: parameter,
                                     normal: Vector3(0, -1, 0),
                                     closest: &closest)
            }
        }
        return closest
    }

    private func rayTestAxisSegment(_ ray: Ray,
                                    halfHeight: Scalar) -> PrimitiveRayHit? {
        let parameter: Scalar
        if abs(ray.direction.x) > .ulpOfOne {
            parameter = -ray.origin.x / ray.direction.x
            guard abs(ray.origin.z + ray.direction.z * parameter) <= .ulpOfOne else {
                return nil
            }
        } else if abs(ray.direction.z) > .ulpOfOne {
            guard abs(ray.origin.x) <= .ulpOfOne else { return nil }
            parameter = -ray.origin.z / ray.direction.z
        } else {
            guard abs(ray.origin.x) <= .ulpOfOne,
                  abs(ray.origin.z) <= .ulpOfOne,
                  abs(ray.direction.y) > .ulpOfOne
            else { return nil }

            let targetY: Scalar
            if ray.origin.y < -halfHeight {
                targetY = -halfHeight
            } else if ray.origin.y > halfHeight {
                targetY = halfHeight
            } else {
                targetY = ray.direction.y > .zero ? halfHeight : -halfHeight
            }
            parameter = (targetY - ray.origin.y) / ray.direction.y
        }

        let position = ray.point(at: parameter)
        guard position.y >= -halfHeight && position.y <= halfHeight else {
            return nil
        }
        var closest: PrimitiveRayHit?
        _updateClosestRayHit(ray: ray,
                             parameter: parameter,
                             normal: .zero,
                             closest: &closest)
        return closest
    }
}

public struct ConeShape: ConvexShape {
    public let primitive: Cone

    public init(_ primitive: Cone) {
        self.primitive = primitive
    }
}
