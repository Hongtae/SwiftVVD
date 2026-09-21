//
//  File: StaticPlane.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct StaticPlane: ConcavePrimitive {
    public let plane: Plane
    public var bounds: AABB { .null }
    public var isValid: Bool {
        plane.d.isFinite && plane.normal.lengthSquared.isFinite &&
            plane.normal.lengthSquared > .ulpOfOne
    }

    public init(_ plane: Plane) {
        self.plane = plane
    }

    public func contains(_ point: Vector3) -> Bool {
        isValid && abs(plane.dot(point)) / plane.normal.length <= .ulpOfOne
    }

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid else { return nil }

        let normalLength = plane.normal.length
        let normal = plane.normal / normalLength
        let signedDistance = plane.dot(point) / normalLength
        return PrimitiveClosestPoint(position: point - normal * signedDistance,
                                     normal: normal,
                                     distance: abs(signedDistance))
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        let normalLength = plane.normal.length
        let normal = plane.normal / normalLength
        let distance = plane.dot(ray.origin) / normalLength
        let denominator = Vector3.dot(normal, ray.direction)
        guard distance.isFinite, denominator.isFinite else { return nil }
        let parameter: Scalar
        if distance == .zero {
            parameter = .zero
        } else {
            guard abs(denominator) > .ulpOfOne else { return nil }
            parameter = -distance / denominator
            guard parameter.isFinite, parameter >= .zero else { return nil }
        }

        return PrimitiveRayHit(parameter: parameter,
                               position: ray.point(at: parameter),
                               normal: normal)
    }
}

public struct StaticPlaneShape: ConcaveShape {
    public let primitive: StaticPlane

    public init(_ primitive: StaticPlane) {
        self.primitive = primitive
    }
}
