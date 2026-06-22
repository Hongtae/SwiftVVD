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

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        plane.rayTest(rayOrigin: origin, direction: direction)
    }
}

public struct StaticPlaneShape: ConcaveShape {
    public let primitive: StaticPlane

    public init(_ primitive: StaticPlane) {
        self.primitive = primitive
    }
}
