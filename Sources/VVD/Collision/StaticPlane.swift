//
//  File: StaticPlane.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct StaticPlane: ConcavePrimitive {
    public let plane: Plane
    public var bounds: AABB { .null }
    public var isValid: Bool { plane.normal.lengthSquared > .ulpOfOne }

    public init(_ plane: Plane) {
        self.plane = plane
    }

    public func contains(_ point: Vector3) -> Bool {
        isValid && abs(plane.dot(point)) <= .ulpOfOne
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        let distance = plane.dot(ray.origin)
        let denominator = Vector3.dot(plane.normal, ray.direction)
        let parameter: Scalar
        if abs(distance) <= .ulpOfOne {
            parameter = .zero
        } else {
            guard abs(denominator) > .ulpOfOne else { return nil }
            parameter = -distance / denominator
            guard parameter >= .zero else { return nil }
        }

        return PrimitiveRayHit(parameter: parameter,
                               position: ray.point(at: parameter),
                               normal: plane.normal.normalized())
    }
}

public struct StaticPlaneShape: ConcaveShape {
    public let primitive: StaticPlane

    public init(_ primitive: StaticPlane) {
        self.primitive = primitive
    }
}
