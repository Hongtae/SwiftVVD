//
//  File: ConvexHull.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct ConvexHull: ConvexPrimitive {
    public let vertices: [Vector3]
    public let bounds: AABB

    public var isValid: Bool {
        vertices.isEmpty == false && bounds.isNull == false
    }

    public init() {
        self.init(vertices: [])
    }

    public init(vertices: [Vector3]) {
        self.vertices = vertices
        self.bounds = AABB(vertices)
    }

    public func contains(_ point: Vector3) -> Bool {
        false
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        nil
    }
}

public struct ConvexHullShape: ConvexShape {
    public let primitive: ConvexHull

    public init(_ primitive: ConvexHull) {
        self.primitive = primitive
    }
}
