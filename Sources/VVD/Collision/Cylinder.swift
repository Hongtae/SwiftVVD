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

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1.0
    }
}

public struct CylinderShape: ConvexShape {
    public let primitive: Cylinder

    public init(_ primitive: Cylinder) {
        self.primitive = primitive
    }
}
