//
//  File: Cone.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Cone: ConvexPrimitive {
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
        guard isValid && height > .ulpOfOne else { return false }

        let halfHeight = height * Scalar(0.5)
        guard point.y >= -halfHeight && point.y <= halfHeight else { return false }

        let radiusAtY = radius * ((halfHeight - point.y) / height)
        return point.x * point.x + point.z * point.z <= radiusAtY * radiusAtY
    }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1.0
    }
}

public struct ConeShape: ConvexShape {
    public let primitive: Cone

    public init(_ primitive: Cone) {
        self.primitive = primitive
    }
}
