//
//  File: Box.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Box: ConvexPrimitive {
    public let halfExtents: Vector3
    public var isValid: Bool {
        halfExtents.x >= .zero && halfExtents.y >= .zero && halfExtents.z >= .zero
    }
    public var bounds: AABB {
        isValid ? AABB(center: .zero, halfExtents: halfExtents) : .null
    }

    public init(halfExtents: Vector3) {
        self.halfExtents = halfExtents
    }

    public func contains(_ point: Vector3) -> Bool {
        isValid &&
        abs(point.x) <= halfExtents.x &&
        abs(point.y) <= halfExtents.y &&
        abs(point.z) <= halfExtents.z
    }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        bounds.rayTest(rayOrigin: origin, direction: direction)
    }
}

public struct BoxShape: ConvexShape {
    public let primitive: Box

    public init(_ primitive: Box) {
        self.primitive = primitive
    }
}
