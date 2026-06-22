//
//  File: CollisionPrimitiveOverlap.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private protocol _SupportMap {
    var isSupportMappingValid: Bool { get }
    var center: Vector3 { get }

    /// Farthest point of the primitive in the supplied direction.
    func support(_ direction: Vector3) -> Vector3
}

private extension _SupportMap where Self: CollisionPrimitive {
    var isSupportMappingValid: Bool { isValid }
}

extension Box: _SupportMap {
    var center: Vector3 { .zero }

    /// Box support point is the corner matching the direction signs.
    func support(_ direction: Vector3) -> Vector3 {
        Vector3(direction.x >= .zero ? halfExtents.x : -halfExtents.x,
                direction.y >= .zero ? halfExtents.y : -halfExtents.y,
                direction.z >= .zero ? halfExtents.z : -halfExtents.z)
    }
}

extension Sphere: _SupportMap {
    /// Sphere support point is center plus radius along the direction.
    func support(_ direction: Vector3) -> Vector3 {
        if direction.lengthSquared <= _overlapEpsilon {
            return center + Vector3(radius, 0, 0)
        }
        return center + direction.normalized() * radius
    }
}

extension Capsule: _SupportMap {
    var center: Vector3 { .zero }

    /// Capsule support point is an end-cap center plus radial support.
    func support(_ direction: Vector3) -> Vector3 {
        let halfHeight = height * Scalar(0.5)
        let y = direction.y >= .zero ? halfHeight : -halfHeight
        let radial = Vector3(direction.x, 0, direction.z)
        if radial.lengthSquared <= _overlapEpsilon {
            return Vector3(0, y, 0)
        }
        return Vector3(0, y, 0) + radial.normalized() * radius
    }
}

extension Cylinder: _SupportMap {
    var center: Vector3 { .zero }

    /// Cylinder support point is on one cap and the outer radial rim.
    func support(_ direction: Vector3) -> Vector3 {
        let halfHeight = height * Scalar(0.5)
        let y = direction.y >= .zero ? halfHeight : -halfHeight
        let radial = Vector3(direction.x, 0, direction.z)
        if radial.lengthSquared <= _overlapEpsilon {
            return Vector3(0, y, 0)
        }
        return Vector3(0, y, 0) + radial.normalized() * radius
    }
}

extension Cone: _SupportMap {
    var isSupportMappingValid: Bool { isValid && height > _overlapEpsilon }
    var center: Vector3 { .zero }

    /// Cone support switches between the apex and the base rim.
    func support(_ direction: Vector3) -> Vector3 {
        let halfHeight = height * Scalar(0.5)
        let radial = Vector3(direction.x, 0, direction.z)
        let radialLength = radial.length
        if direction.y >= radialLength * radius / height {
            return Vector3(0, halfHeight, 0)
        }
        if radialLength <= _overlapEpsilon {
            return Vector3(0, -halfHeight, 0)
        }
        return Vector3(0, -halfHeight, 0) + radial * (radius / radialLength)
    }
}

extension Triangle: _SupportMap {
    var isSupportMappingValid: Bool { area > _overlapEpsilon }
    var center: Vector3 { (p0 + p1 + p2) / Scalar(3) }

    /// Triangle support point is the vertex with the largest projection.
    func support(_ direction: Vector3) -> Vector3 {
        let d0 = Vector3.dot(p0, direction)
        let d1 = Vector3.dot(p1, direction)
        let d2 = Vector3.dot(p2, direction)
        if d0 >= d1 && d0 >= d2 { return p0 }
        if d1 >= d2 { return p1 }
        return p2
    }
}

extension ConvexHull: _SupportMap {
    var center: Vector3 { bounds.center }

    /// Convex hull support is the stored vertex with the largest projection.
    func support(_ direction: Vector3) -> Vector3 {
        guard var support = vertices.first else { return .zero }
        var bestDistance = Vector3.dot(support, direction)

        for vertex in vertices.dropFirst() {
            let distance = Vector3.dot(vertex, direction)
            if distance > bestDistance {
                support = vertex
                bestDistance = distance
            }
        }
        return support
    }
}

private struct _TransformedSupport: _SupportMap {
    let base: any _SupportMap
    let transform: Transform

    var isSupportMappingValid: Bool { base.isSupportMappingValid }
    var center: Vector3 { base.center.applying(transform) }

    /// Converts the world-space direction to local space, then transforms back.
    func support(_ direction: Vector3) -> Vector3 {
        let localDirection = direction.applying(transform.orientation.conjugated())
        return base.support(localDirection).applying(transform)
    }
}

// Low-level intersection helpers use `frame` as the transform from the second
// primitive's local space into the first primitive's local space.
extension CollisionAlgorithms {
    // Box, Box
    /// Tests two oriented boxes with SAT.
    static func intersects(_ a: Box, _ b: Box, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let aExtent = [a.halfExtents.x, a.halfExtents.y, a.halfExtents.z]
        let bExtent = [b.halfExtents.x, b.halfExtents.y, b.halfExtents.z]
        let bAxis = [
            Vector3(1, 0, 0).applying(frame.orientation),
            Vector3(0, 1, 0).applying(frame.orientation),
            Vector3(0, 0, 1).applying(frame.orientation)
        ]
        let t = frame.position

        var r = Array(repeating: Array(repeating: Scalar.zero, count: 3), count: 3)
        var absR = r
        for i in 0..<3 {
            for j in 0..<3 {
                r[i][j] = bAxis[j][i]
                absR[i][j] = abs(r[i][j]) + _overlapEpsilon
            }
        }

        // Test face normals from box A.
        for i in 0..<3 {
            let ra = aExtent[i]
            let rb = bExtent[0] * absR[i][0] + bExtent[1] * absR[i][1] + bExtent[2] * absR[i][2]
            let depth = ra + rb - abs(t[i])
            guard _hasOverlapDepth(depth) else { return false }
        }

        // Test face normals from box B.
        for j in 0..<3 {
            let ra = aExtent[0] * absR[0][j] + aExtent[1] * absR[1][j] + aExtent[2] * absR[2][j]
            let rb = bExtent[j]
            let depth = ra + rb - abs(Vector3.dot(t, bAxis[j]))
            guard _hasOverlapDepth(depth) else { return false }
        }

        // Test edge cross-product axes, skipping degenerate axes for parallel edges.
        for i in 0..<3 {
            for j in 0..<3 {
                if Scalar(1) - r[i][j] * r[i][j] <= _overlapEpsilon {
                    continue
                }
                let i1 = (i + 1) % 3
                let i2 = (i + 2) % 3
                let j1 = (j + 1) % 3
                let j2 = (j + 2) % 3
                let ra = aExtent[i1] * absR[i2][j] + aExtent[i2] * absR[i1][j]
                let rb = bExtent[j1] * absR[i][j2] + bExtent[j2] * absR[i][j1]
                let depth = ra + rb - abs(t[i2] * r[i1][j] - t[i1] * r[i2][j])
                guard _hasOverlapDepth(depth) else { return false }
            }
        }

        return true
    }

    // Box, Sphere
    /// Clamps the sphere center to the box and tests sphere penetration.
    static func intersects(_ a: Box, _ b: Sphere, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let center = b.center.applying(frame)
        let closest = Vector3(
            center.x.clamp(min: -a.halfExtents.x, max: a.halfExtents.x),
            center.y.clamp(min: -a.halfExtents.y, max: a.halfExtents.y),
            center.z.clamp(min: -a.halfExtents.z, max: a.halfExtents.z)
        )
        let delta = center - closest
        let distanceSquared = delta.lengthSquared
        if distanceSquared > b.radius * b.radius + _overlapEpsilon {
            return false
        }
        // Center is inside the box, so the sphere intersects.
        if distanceSquared <= _overlapEpsilon {
            return true
        }
        return _hasOverlapDepth(b.radius - distanceSquared.squareRoot())
    }
    static func intersects(_ a: Sphere, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, Capsule
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Box, _ b: Capsule, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Capsule, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, Cylinder
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Box, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cylinder, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, Cone
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Box, _ b: Cone, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cone, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Box, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: ConvexHull, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, StaticPlane
    /// Tests whether a convex box straddles or touches a static plane.
    static func intersects(_ a: Box, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, TriangleMesh
    /// Tests the box against each mesh triangle with GJK.
    static func intersects(_ a: Box, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Box, CompoundPrimitive
    static func intersects(_ a: Box, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: Box, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, Sphere
    /// Compares center distance against radius sum.
    static func intersects(_ a: Sphere, _ b: Sphere, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let center = b.center.applying(frame)
        let radius = a.radius + b.radius
        let distanceSquared = (center - a.center).lengthSquared
        if distanceSquared > radius * radius + _overlapEpsilon {
            return false
        }
        return _hasOverlapDepth(radius - distanceSquared.squareRoot())
    }

    // Sphere, Capsule
    /// Measures sphere center distance to capsule segment.
    static func intersects(_ a: Sphere, _ b: Capsule, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let halfHeight = b.height * Scalar(0.5)
        let p0 = Vector3(0, -halfHeight, 0).applying(frame)
        let p1 = Vector3(0, halfHeight, 0).applying(frame)
        let distanceSquared = _distanceSquared(a.center, p0, p1)
        let radius = a.radius + b.radius
        if distanceSquared > radius * radius + _overlapEpsilon {
            return false
        }
        return _hasOverlapDepth(radius - distanceSquared.squareRoot())
    }
    static func intersects(_ a: Capsule, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, Cylinder
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Sphere, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cylinder, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, Cone
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Sphere, _ b: Cone, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cone, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Sphere, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: ConvexHull, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, StaticPlane
    /// Tests whether a convex sphere straddles or touches a static plane.
    static func intersects(_ a: Sphere, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, TriangleMesh
    /// Tests the sphere against each mesh triangle with GJK.
    static func intersects(_ a: Sphere, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Sphere, CompoundPrimitive
    static func intersects(_ a: Sphere, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: Sphere, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, Capsule
    /// Measures distance between capsule segments.
    static func intersects(_ a: Capsule, _ b: Capsule, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let aHalfHeight = a.height * Scalar(0.5)
        let bHalfHeight = b.height * Scalar(0.5)
        let a0 = Vector3(0, -aHalfHeight, 0)
        let a1 = Vector3(0, aHalfHeight, 0)
        let b0 = Vector3(0, -bHalfHeight, 0).applying(frame)
        let b1 = Vector3(0, bHalfHeight, 0).applying(frame)
        let distanceSquared = _distanceSquared(a0, a1, b0, b1)
        let radius = a.radius + b.radius
        if distanceSquared > radius * radius + _overlapEpsilon {
            return false
        }
        return _hasOverlapDepth(radius - distanceSquared.squareRoot())
    }

    // Capsule, Cylinder
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Capsule, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cylinder, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, Cone
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Capsule, _ b: Cone, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cone, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Capsule, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: ConvexHull, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, StaticPlane
    /// Tests whether a convex capsule straddles or touches a static plane.
    static func intersects(_ a: Capsule, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, TriangleMesh
    /// Tests the capsule against each mesh triangle with GJK.
    static func intersects(_ a: Capsule, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Capsule, CompoundPrimitive
    static func intersects(_ a: Capsule, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: Capsule, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cylinder, Cylinder
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Cylinder, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }

    // Cylinder, Cone
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Cylinder, _ b: Cone, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: Cone, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cylinder, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Cylinder, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: ConvexHull, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cylinder, StaticPlane
    /// Tests whether a convex cylinder straddles or touches a static plane.
    static func intersects(_ a: Cylinder, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cylinder, TriangleMesh
    /// Tests the cylinder against each mesh triangle with GJK.
    static func intersects(_ a: Cylinder, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cylinder, CompoundPrimitive
    static func intersects(_ a: Cylinder, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: Cylinder, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cone, Cone
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Cone, _ b: Cone, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }

    // Cone, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: Cone, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: ConvexHull, _ b: Cone, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cone, StaticPlane
    /// Tests whether a convex cone straddles or touches a static plane.
    static func intersects(_ a: Cone, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: Cone, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cone, TriangleMesh
    /// Tests the cone against each mesh triangle with GJK.
    static func intersects(_ a: Cone, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: Cone, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // Cone, CompoundPrimitive
    static func intersects(_ a: Cone, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: Cone, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // ConvexHull, ConvexHull
    /// Uses convex support maps and GJK.
    static func intersects(_ a: ConvexHull, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        _convexIntersects(a, b, frame: frame)
    }

    // ConvexHull, StaticPlane
    /// Tests whether a convex hull straddles or touches a static plane.
    static func intersects(_ a: ConvexHull, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        _supportMapPlaneIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: StaticPlane, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // ConvexHull, TriangleMesh
    /// Tests the convex hull against each mesh triangle with GJK.
    static func intersects(_ a: ConvexHull, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _supportMapMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // ConvexHull, CompoundPrimitive
    static func intersects(_ a: ConvexHull, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: ConvexHull, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // StaticPlane, StaticPlane
    static func intersects(_ a: StaticPlane, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        guard a.isValid && b.isValid else { return false }

        let planeA = a.plane
        let planeB = _transformed(b.plane, by: frame)
        let lengthA = planeA.normal.length
        let lengthB = planeB.normal.length
        guard lengthA > _overlapEpsilon && lengthB > _overlapEpsilon else { return false }

        let normalA = planeA.normal / lengthA
        let normalB = planeB.normal / lengthB
        let distanceA = planeA.d / lengthA
        let distanceB = planeB.d / lengthB
        let alignment = Vector3.dot(normalA, normalB)

        if Scalar(1) - abs(alignment) > _overlapEpsilon {
            return true
        }

        let orientedDistanceB = alignment >= .zero ? distanceB : -distanceB
        return abs(distanceA - orientedDistanceB) <= _overlapEpsilon
    }

    // StaticPlane, TriangleMesh
    /// Tests whether any mesh triangle straddles or touches the plane.
    static func intersects(_ a: StaticPlane, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _planeMeshIntersects(a, b, frame: frame)
    }
    static func intersects(_ a: TriangleMesh, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // StaticPlane, CompoundPrimitive
    static func intersects(_ a: StaticPlane, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: StaticPlane, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // TriangleMesh, TriangleMesh
    /// Tests all triangle pairs, using AABB rejection before triangle overlap.
    static func intersects(_ a: TriangleMesh, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        _triangleMeshIntersects(a, b, frame: frame)
    }

    // TriangleMesh, CompoundPrimitive
    static func intersects(_ a: TriangleMesh, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
    static func intersects(_ a: CompoundPrimitive, _ b: TriangleMesh, frame: Transform = .identity) -> Bool {
        intersects(b, a, frame: frame.inverted())
    }

    // CompoundPrimitive, CompoundPrimitive
    static func intersects(_ a: CompoundPrimitive, _ b: CompoundPrimitive, frame: Transform = .identity) -> Bool {
        false
    }
}

extension CollisionAlgorithms {
    // Box, Box
    /// Generates a single approximate contact from the minimum SAT axis.
    static func contactManifold(_ a: Box, _ b: Box, frame: Transform = .identity) -> ContactManifold? {
        _boxBoxContact(a, b, frame: frame)
    }

    // Box, Sphere
    /// Generates a contact from the closest point on the box to the sphere center.
    static func contactManifold(_ a: Box, _ b: Sphere, frame: Transform = .identity) -> ContactManifold? {
        _boxSphereContact(a, b, frame: frame)
    }

    /// Generates a sphere-box contact by flipping the box-sphere result.
    static func contactManifold(_ a: Sphere, _ b: Box, frame: Transform = .identity) -> ContactManifold? {
        contactManifold(b, a, frame: frame.inverted()).map { _flipped($0, frame: frame) }
    }

    // Sphere, Sphere
    /// Generates a contact along the line between the two sphere centers.
    static func contactManifold(_ a: Sphere, _ b: Sphere, frame: Transform = .identity) -> ContactManifold? {
        _sphereSphereContact(a, b, frame: frame)
    }

    // Sphere, Capsule
    /// Generates a contact between the sphere center and closest capsule segment point.
    static func contactManifold(_ a: Sphere, _ b: Capsule, frame: Transform = .identity) -> ContactManifold? {
        _sphereCapsuleContact(a, b, frame: frame)
    }

    /// Generates a capsule-sphere contact by flipping the sphere-capsule result.
    static func contactManifold(_ a: Capsule, _ b: Sphere, frame: Transform = .identity) -> ContactManifold? {
        contactManifold(b, a, frame: frame.inverted()).map { _flipped($0, frame: frame) }
    }

    // Capsule, Capsule
    /// Generates a contact between the closest points of the two capsule segments.
    static func contactManifold(_ a: Capsule, _ b: Capsule, frame: Transform = .identity) -> ContactManifold? {
        _capsuleCapsuleContact(a, b, frame: frame)
    }

    // Box, StaticPlane
    /// Generates a single projected contact against the plane.
    static func contactManifold(_ a: Box, _ b: StaticPlane, frame: Transform = .identity) -> ContactManifold? {
        _boxPlaneContact(a, b, frame: frame)
    }

    /// Generates a plane-box contact by flipping the box-plane result.
    static func contactManifold(_ a: StaticPlane, _ b: Box, frame: Transform = .identity) -> ContactManifold? {
        contactManifold(b, a, frame: frame.inverted()).map { _flipped($0, frame: frame) }
    }

    // Sphere, StaticPlane
    /// Generates a projected sphere contact against the plane.
    static func contactManifold(_ a: Sphere, _ b: StaticPlane, frame: Transform = .identity) -> ContactManifold? {
        _spherePlaneContact(a, b, frame: frame)
    }

    /// Generates a plane-sphere contact by flipping the sphere-plane result.
    static func contactManifold(_ a: StaticPlane, _ b: Sphere, frame: Transform = .identity) -> ContactManifold? {
        contactManifold(b, a, frame: frame.inverted()).map { _flipped($0, frame: frame) }
    }
}

private let _overlapEpsilon: Scalar = {
    if MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size {
        return Scalar(1.0e-12)
    }
    return Scalar(1.0e-6)
}()

/// Treats small negative numerical noise as overlap.
private func _hasOverlapDepth(_ depth: Scalar) -> Bool {
    depth >= -_overlapEpsilon
}

/// Builds a one-point manifold when the supplied depth represents overlap.
private func _contact(pointOnA: Vector3,
                      pointOnB: Vector3,
                      normal: Vector3,
                      penetrationDepth: Scalar,
                      featureID: ContactFeatureID = ContactFeatureID()) -> ContactManifold? {
    guard penetrationDepth >= -_overlapEpsilon else { return nil }
    let normal = _normalizedOrFallback(normal, fallback: pointOnB - pointOnA)
    return ContactManifold(Contact(pointOnA: pointOnA,
                                   pointOnB: pointOnB,
                                   normal: normal,
                                   penetrationDepth: Swift.max(penetrationDepth, .zero),
                                   featureID: featureID))
}

/// Flips a manifold generated in B's local space back into A's local space.
private func _flipped(_ manifold: ContactManifold, frame: Transform) -> ContactManifold {
    ContactManifold(contacts: manifold.contacts.map { contact in
        Contact(pointOnA: contact.pointOnB.applying(frame),
                pointOnB: contact.pointOnA.applying(frame),
                normal: -contact.normal.applying(frame.orientation),
                penetrationDepth: contact.penetrationDepth,
                featureID: contact.featureID)
    })
}

/// Normalizes a direction, using a stable fallback when the direction is degenerate.
private func _normalizedOrFallback(_ direction: Vector3, fallback: Vector3 = Vector3(1, 0, 0)) -> Vector3 {
    if direction.lengthSquared > _overlapEpsilon {
        return direction.normalized()
    }
    if fallback.lengthSquared > _overlapEpsilon {
        return fallback.normalized()
    }
    return Vector3(1, 0, 0)
}

/// Generates an approximate box-box contact from the minimum separating axis.
private func _boxBoxContact(_ a: Box, _ b: Box, frame: Transform) -> ContactManifold? {
    guard a.isValid && b.isValid else { return nil }

    let aAxis = [
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1)
    ]
    let aExtent = [a.halfExtents.x, a.halfExtents.y, a.halfExtents.z]
    let bExtent = [b.halfExtents.x, b.halfExtents.y, b.halfExtents.z]
    let bAxis = [
        Vector3(1, 0, 0).applying(frame.orientation),
        Vector3(0, 1, 0).applying(frame.orientation),
        Vector3(0, 0, 1).applying(frame.orientation)
    ]
    let t = frame.position

    var r = Array(repeating: Array(repeating: Scalar.zero, count: 3), count: 3)
    var absR = r
    for i in 0..<3 {
        for j in 0..<3 {
            r[i][j] = bAxis[j][i]
            absR[i][j] = abs(r[i][j]) + _overlapEpsilon
        }
    }

    var minDepth = Scalar.greatestFiniteMagnitude
    var normal = Vector3(1, 0, 0)

    let updateAxis = { (axis: Vector3, depth: Scalar, minDepth: inout Scalar, normal: inout Vector3) -> Bool in
        if depth < -_overlapEpsilon { return false }
        if depth < minDepth {
            minDepth = Swift.max(depth, .zero)
            normal = _normalizedOrFallback(axis, fallback: t)
        }
        return true
    }

    // Test face normals from box A.
    for i in 0..<3 {
        let ra = aExtent[i]
        let rb = bExtent[0] * absR[i][0] + bExtent[1] * absR[i][1] + bExtent[2] * absR[i][2]
        let depth = ra + rb - abs(t[i])
        let axis = t[i] >= .zero ? aAxis[i] : -aAxis[i]
        guard updateAxis(axis, depth, &minDepth, &normal) else { return nil }
    }

    // Test face normals from box B.
    for j in 0..<3 {
        let ra = aExtent[0] * absR[0][j] + aExtent[1] * absR[1][j] + aExtent[2] * absR[2][j]
        let rb = bExtent[j]
        let projected = Vector3.dot(t, bAxis[j])
        let depth = ra + rb - abs(projected)
        let axis = projected >= .zero ? bAxis[j] : -bAxis[j]
        guard updateAxis(axis, depth, &minDepth, &normal) else { return nil }
    }

    // Test edge cross-product axes, skipping degenerate axes for parallel edges.
    for i in 0..<3 {
        for j in 0..<3 {
            if Scalar(1) - r[i][j] * r[i][j] <= _overlapEpsilon {
                continue
            }
            let i1 = (i + 1) % 3
            let i2 = (i + 2) % 3
            let j1 = (j + 1) % 3
            let j2 = (j + 2) % 3
            let ra = aExtent[i1] * absR[i2][j] + aExtent[i2] * absR[i1][j]
            let rb = bExtent[j1] * absR[i][j2] + bExtent[j2] * absR[i][j1]
            let projection = t[i2] * r[i1][j] - t[i1] * r[i2][j]
            let depth = ra + rb - abs(projection)
            var axis = Vector3.cross(aAxis[i], bAxis[j])
            if Vector3.dot(axis, t) < .zero {
                axis = -axis
            }
            guard updateAxis(axis, depth, &minDepth, &normal) else { return nil }
        }
    }

    let transformedB = _TransformedSupport(base: b, transform: frame)
    let pointOnA = a.support(normal)
    let pointOnB = transformedB.support(-normal)
    return _contact(pointOnA: pointOnA,
                    pointOnB: pointOnB,
                    normal: normal,
                    penetrationDepth: minDepth)
}

/// Generates a box-sphere contact using closest-point projection.
private func _boxSphereContact(_ box: Box, _ sphere: Sphere, frame: Transform) -> ContactManifold? {
    guard box.isValid && sphere.isValid else { return nil }

    let center = sphere.center.applying(frame)
    let closest = Vector3(
        center.x.clamp(min: -box.halfExtents.x, max: box.halfExtents.x),
        center.y.clamp(min: -box.halfExtents.y, max: box.halfExtents.y),
        center.z.clamp(min: -box.halfExtents.z, max: box.halfExtents.z)
    )
    let delta = center - closest
    let distanceSquared = delta.lengthSquared
    if distanceSquared > sphere.radius * sphere.radius + _overlapEpsilon {
        return nil
    }

    if distanceSquared <= _overlapEpsilon {
        let distances = [
            box.halfExtents.x - abs(center.x),
            box.halfExtents.y - abs(center.y),
            box.halfExtents.z - abs(center.z)
        ]
        var axisIndex = 0
        if distances[1] < distances[axisIndex] { axisIndex = 1 }
        if distances[2] < distances[axisIndex] { axisIndex = 2 }

        let sign: Scalar = center[axisIndex] >= .zero ? Scalar(1) : Scalar(-1)
        var normal = Vector3.zero
        normal[axisIndex] = sign
        var pointOnA = center
        pointOnA[axisIndex] = box.halfExtents[axisIndex] * sign
        let pointOnB = center - normal * sphere.radius
        return _contact(pointOnA: pointOnA,
                        pointOnB: pointOnB,
                        normal: normal,
                        penetrationDepth: sphere.radius + Swift.max(distances[axisIndex], .zero))
    }

    let distance = distanceSquared.squareRoot()
    let normal = delta / distance
    return _contact(pointOnA: closest,
                    pointOnB: center - normal * sphere.radius,
                    normal: normal,
                    penetrationDepth: sphere.radius - distance)
}

/// Generates a sphere-sphere contact from center distance.
private func _sphereSphereContact(_ a: Sphere, _ b: Sphere, frame: Transform) -> ContactManifold? {
    guard a.isValid && b.isValid else { return nil }

    let centerB = b.center.applying(frame)
    let delta = centerB - a.center
    let distanceSquared = delta.lengthSquared
    let radius = a.radius + b.radius
    if distanceSquared > radius * radius + _overlapEpsilon {
        return nil
    }

    let distance = distanceSquared.squareRoot()
    let normal = _normalizedOrFallback(delta, fallback: frame.position - a.center)
    return _contact(pointOnA: a.center + normal * a.radius,
                    pointOnB: centerB - normal * b.radius,
                    normal: normal,
                    penetrationDepth: radius - distance)
}

/// Generates a sphere-capsule contact from the closest segment point.
private func _sphereCapsuleContact(_ sphere: Sphere, _ capsule: Capsule, frame: Transform) -> ContactManifold? {
    guard sphere.isValid && capsule.isValid else { return nil }

    let halfHeight = capsule.height * Scalar(0.5)
    let p0 = Vector3(0, -halfHeight, 0).applying(frame)
    let p1 = Vector3(0, halfHeight, 0).applying(frame)
    let closest = _closestPoint(sphere.center, p0, p1)
    let delta = closest - sphere.center
    let distanceSquared = delta.lengthSquared
    let radius = sphere.radius + capsule.radius
    if distanceSquared > radius * radius + _overlapEpsilon {
        return nil
    }

    let distance = distanceSquared.squareRoot()
    let normal = _normalizedOrFallback(delta, fallback: frame.position - sphere.center)
    return _contact(pointOnA: sphere.center + normal * sphere.radius,
                    pointOnB: closest - normal * capsule.radius,
                    normal: normal,
                    penetrationDepth: radius - distance)
}

/// Generates a capsule-capsule contact from closest segment points.
private func _capsuleCapsuleContact(_ a: Capsule, _ b: Capsule, frame: Transform) -> ContactManifold? {
    guard a.isValid && b.isValid else { return nil }

    let aHalfHeight = a.height * Scalar(0.5)
    let bHalfHeight = b.height * Scalar(0.5)
    let a0 = Vector3(0, -aHalfHeight, 0)
    let a1 = Vector3(0, aHalfHeight, 0)
    let b0 = Vector3(0, -bHalfHeight, 0).applying(frame)
    let b1 = Vector3(0, bHalfHeight, 0).applying(frame)
    let closest = _closestPoints(a0, a1, b0, b1)
    let delta = closest.b - closest.a
    let distanceSquared = delta.lengthSquared
    let radius = a.radius + b.radius
    if distanceSquared > radius * radius + _overlapEpsilon {
        return nil
    }

    let distance = distanceSquared.squareRoot()
    let normal = _normalizedOrFallback(delta, fallback: frame.position)
    return _contact(pointOnA: closest.a + normal * a.radius,
                    pointOnB: closest.b - normal * b.radius,
                    normal: normal,
                    penetrationDepth: radius - distance)
}

/// Generates a box-plane contact from box projection onto the plane normal.
private func _boxPlaneContact(_ box: Box, _ staticPlane: StaticPlane, frame: Transform) -> ContactManifold? {
    guard box.isValid && staticPlane.isValid else { return nil }

    let plane = _transformed(staticPlane.plane, by: frame)
    let normalLength = plane.normal.length
    guard normalLength > _overlapEpsilon else { return nil }
    let planeNormal = plane.normal / normalLength
    let planeDistance = plane.d / normalLength
    let radius = box.halfExtents.x * abs(planeNormal.x) +
                 box.halfExtents.y * abs(planeNormal.y) +
                 box.halfExtents.z * abs(planeNormal.z)
    let centerDistance = planeDistance
    let depth = radius - abs(centerDistance)
    guard depth >= -_overlapEpsilon else { return nil }

    let normal = centerDistance >= .zero ? -planeNormal : planeNormal
    let pointOnA = box.support(normal)
    let pointOnB = pointOnA - planeNormal * (Vector3.dot(planeNormal, pointOnA) + planeDistance)
    return _contact(pointOnA: pointOnA,
                    pointOnB: pointOnB,
                    normal: normal,
                    penetrationDepth: depth)
}

/// Generates a sphere-plane contact from signed center distance.
private func _spherePlaneContact(_ sphere: Sphere, _ staticPlane: StaticPlane, frame: Transform) -> ContactManifold? {
    guard sphere.isValid && staticPlane.isValid else { return nil }

    let plane = _transformed(staticPlane.plane, by: frame)
    let normalLength = plane.normal.length
    guard normalLength > _overlapEpsilon else { return nil }
    let planeNormal = plane.normal / normalLength
    let planeDistance = plane.d / normalLength
    let signedDistance = Vector3.dot(planeNormal, sphere.center) + planeDistance
    let depth = sphere.radius - abs(signedDistance)
    guard depth >= -_overlapEpsilon else { return nil }

    let normal = signedDistance >= .zero ? -planeNormal : planeNormal
    return _contact(pointOnA: sphere.center + normal * sphere.radius,
                    pointOnB: sphere.center + normal * abs(signedDistance),
                    normal: normal,
                    penetrationDepth: depth)
}

/// Projects a convex support map onto a plane normal and checks sign overlap.
private func _supportMapPlaneIntersects(_ primitive: any _SupportMap, _ plane: StaticPlane, frame: Transform) -> Bool {
    guard primitive.isSupportMappingValid && plane.isValid else { return false }

    let plane = _transformed(plane.plane, by: frame)
    let normal = plane.normal
    guard normal.lengthSquared > _overlapEpsilon else { return false }

    let minDistance = plane.dot(primitive.support(-normal))
    let maxDistance = plane.dot(primitive.support(normal))
    return minDistance <= _overlapEpsilon && maxDistance >= -_overlapEpsilon
}

/// Tests a convex support-mapped primitive against all triangles in a mesh.
private func _supportMapMeshIntersects(_ primitive: any _SupportMap, _ mesh: TriangleMesh, frame: Transform) -> Bool {
    guard primitive.isSupportMappingValid && mesh.isValid else { return false }

    for index in 0..<mesh.triangleCount {
        let triangle = _transformed(mesh.triangle(at: index), by: frame)
        if _gjkIntersects(primitive, triangle) {
            return true
        }
    }
    return false
}

/// Tests a static plane against all triangles in a mesh.
private func _planeMeshIntersects(_ plane: StaticPlane, _ mesh: TriangleMesh, frame: Transform) -> Bool {
    guard plane.isValid && mesh.isValid else { return false }

    for index in 0..<mesh.triangleCount {
        let triangle = _transformed(mesh.triangle(at: index), by: frame)
        if _trianglePlaneOverlaps(triangle, plane.plane) {
            return true
        }
    }
    return false
}

/// Tests mesh triangles pairwise after a cheap triangle AABB rejection.
private func _triangleMeshIntersects(_ a: TriangleMesh, _ b: TriangleMesh, frame: Transform) -> Bool {
    guard a.isValid && b.isValid else { return false }

    for indexA in 0..<a.triangleCount {
        let triangleA = a.triangle(at: indexA)
        for indexB in 0..<b.triangleCount {
            let triangleB = _transformed(b.triangle(at: indexB), by: frame)
            if triangleA.aabb.intersects(triangleB.aabb) && triangleA.intersects(triangleB) {
                return true
            }
        }
    }
    return false
}

/// Runs GJK for two convex support maps.
private func _convexIntersects(_ a: any _SupportMap, _ b: any _SupportMap, frame: Transform) -> Bool {
    guard a.isSupportMappingValid && b.isSupportMappingValid else { return false }

    let b = _TransformedSupport(base: b, transform: frame)
    return _gjkIntersects(a, b)
}

/// GJK origin-containment test for the Minkowski difference of two convex shapes.
private func _gjkIntersects(_ a: any _SupportMap, _ b: any _SupportMap) -> Bool {
    var direction = b.center - a.center
    if direction.lengthSquared <= _overlapEpsilon {
        direction = Vector3(1, 0, 0)
    }

    var simplex = [_minkowskiSupport(a, b, direction)]
    direction = -simplex[0]
    if direction.lengthSquared <= _overlapEpsilon {
        return true
    }

    for _ in 0..<64 {
        let point = _minkowskiSupport(a, b, direction)
        if Vector3.dot(point, direction) < -_overlapEpsilon {
            return false
        }
        if simplex.contains(where: { ($0 - point).lengthSquared <= _overlapEpsilon }) {
            return true
        }
        simplex.append(point)
        if _handleSimplex(&simplex, direction: &direction) {
            return true
        }
        if direction.lengthSquared <= _overlapEpsilon {
            return true
        }
    }
    return false
}

/// Single support point in the Minkowski difference A - B.
private func _minkowskiSupport(_ a: any _SupportMap, _ b: any _SupportMap, _ direction: Vector3) -> Vector3 {
    a.support(direction) - b.support(-direction)
}

/// Updates the simplex and search direction; returns true when origin is enclosed.
private func _handleSimplex(_ simplex: inout [Vector3], direction: inout Vector3) -> Bool {
    switch simplex.count {
    case 2:
        return _handleLine(&simplex, direction: &direction)
    case 3:
        return _handleTriangle(&simplex, direction: &direction)
    case 4:
        return _handleTetrahedron(&simplex, direction: &direction)
    default:
        direction = -simplex[0]
        return false
    }
}

/// Handles a 2-point simplex by searching perpendicular to the line toward origin.
private func _handleLine(_ simplex: inout [Vector3], direction: inout Vector3) -> Bool {
    let a = simplex[1]
    let b = simplex[0]
    let ab = b - a
    let ao = -a

    if _sameDirection(ab, ao) {
        direction = _tripleProduct(ab, ao, ab)
        if direction.lengthSquared <= _overlapEpsilon {
            direction = _perpendicular(to: ab)
        }
    } else {
        simplex = [a]
        direction = ao
    }
    return direction.lengthSquared <= _overlapEpsilon
}

/// Handles a 3-point simplex by keeping the triangle edge/face closest to origin.
private func _handleTriangle(_ simplex: inout [Vector3], direction: inout Vector3) -> Bool {
    let a = simplex[2]
    let b = simplex[1]
    let c = simplex[0]
    let ab = b - a
    let ac = c - a
    let ao = -a
    let abc = Vector3.cross(ab, ac)

    let acPerpendicular = Vector3.cross(abc, ac)
    if _sameDirection(acPerpendicular, ao) {
        if _sameDirection(ac, ao) {
            simplex = [c, a]
            direction = _tripleProduct(ac, ao, ac)
            if direction.lengthSquared <= _overlapEpsilon {
                direction = _perpendicular(to: ac)
            }
            return direction.lengthSquared <= _overlapEpsilon
        }
        simplex = [b, a]
        return _handleLine(&simplex, direction: &direction)
    }

    let abPerpendicular = Vector3.cross(ab, abc)
    if _sameDirection(abPerpendicular, ao) {
        simplex = [b, a]
        return _handleLine(&simplex, direction: &direction)
    }

    if _sameDirection(abc, ao) {
        direction = abc
    } else {
        simplex = [b, c, a]
        direction = -abc
    }
    return direction.lengthSquared <= _overlapEpsilon
}

/// Handles a tetrahedron simplex; origin inside all faces means intersection.
private func _handleTetrahedron(_ simplex: inout [Vector3], direction: inout Vector3) -> Bool {
    let a = simplex[3]
    let b = simplex[2]
    let c = simplex[1]
    let d = simplex[0]

    if _outsideFace(a, b, c, opposite: d, simplex: &simplex, direction: &direction) {
        return false
    }
    if _outsideFace(a, c, d, opposite: b, simplex: &simplex, direction: &direction) {
        return false
    }
    if _outsideFace(a, d, b, opposite: c, simplex: &simplex, direction: &direction) {
        return false
    }
    return true
}

/// Keeps the simplex on a tetrahedron face when origin lies outside that face.
private func _outsideFace(_ a: Vector3,
                          _ b: Vector3,
                          _ c: Vector3,
                          opposite d: Vector3,
                          simplex: inout [Vector3],
                          direction: inout Vector3) -> Bool {
    var normal = Vector3.cross(b - a, c - a)
    var face = [c, b, a]
    if Vector3.dot(normal, d - a) > .zero {
        normal = -normal
        face = [b, c, a]
    }

    if Vector3.dot(normal, -a) > _overlapEpsilon {
        simplex = face
        direction = normal
        return true
    }
    return false
}

/// True when vectors point to the same half-space.
private func _sameDirection(_ a: Vector3, _ b: Vector3) -> Bool {
    Vector3.dot(a, b) > .zero
}

/// Vector triple product used to build a direction perpendicular to an edge.
private func _tripleProduct(_ a: Vector3, _ b: Vector3, _ c: Vector3) -> Vector3 {
    Vector3.cross(Vector3.cross(a, b), c)
}

/// Stable fallback perpendicular for degenerate simplex directions.
private func _perpendicular(to vector: Vector3) -> Vector3 {
    if vector.lengthSquared <= _overlapEpsilon {
        return Vector3(1, 0, 0)
    }

    let axis: Vector3
    if abs(vector.x) <= abs(vector.y) && abs(vector.x) <= abs(vector.z) {
        axis = Vector3(1, 0, 0)
    } else if abs(vector.y) <= abs(vector.z) {
        axis = Vector3(0, 1, 0)
    } else {
        axis = Vector3(0, 0, 1)
    }
    return Vector3.cross(vector, axis).normalized()
}

/// Closest point on a segment to a point.
private func _closestPoint(_ point: Vector3, _ a: Vector3, _ b: Vector3) -> Vector3 {
    let ab = b - a
    let lengthSquared = ab.lengthSquared
    if lengthSquared <= _overlapEpsilon {
        return a
    }
    let t = (Vector3.dot(point - a, ab) / lengthSquared).clamp(min: .zero, max: Scalar(1))
    return a + ab * t
}

/// Closest points between two segments.
private func _closestPoints(_ p1: Vector3, _ q1: Vector3, _ p2: Vector3, _ q2: Vector3) -> (a: Vector3, b: Vector3) {
    let d1 = q1 - p1
    let d2 = q2 - p2
    let r = p1 - p2
    let a = Vector3.dot(d1, d1)
    let e = Vector3.dot(d2, d2)
    let f = Vector3.dot(d2, r)

    var s = Scalar.zero
    var t = Scalar.zero

    if a <= _overlapEpsilon && e <= _overlapEpsilon {
        return (p1, p2)
    }
    if a <= _overlapEpsilon {
        t = (f / e).clamp(min: .zero, max: Scalar(1))
    } else {
        let c = Vector3.dot(d1, r)
        if e <= _overlapEpsilon {
            s = (-c / a).clamp(min: .zero, max: Scalar(1))
        } else {
            let b = Vector3.dot(d1, d2)
            let denom = a * e - b * b
            if denom != .zero {
                s = ((b * f - c * e) / denom).clamp(min: .zero, max: Scalar(1))
            }
            t = (b * s + f) / e
            if t < .zero {
                t = .zero
                s = (-c / a).clamp(min: .zero, max: Scalar(1))
            } else if t > Scalar(1) {
                t = Scalar(1)
                s = ((b - c) / a).clamp(min: .zero, max: Scalar(1))
            }
        }
    }

    return (p1 + d1 * s, p2 + d2 * t)
}

/// Squared distance from a point to a segment.
private func _distanceSquared(_ point: Vector3, _ a: Vector3, _ b: Vector3) -> Scalar {
    (point - _closestPoint(point, a, b)).lengthSquared
}

/// Squared distance between two segments.
private func _distanceSquared(_ p1: Vector3, _ q1: Vector3, _ p2: Vector3, _ q2: Vector3) -> Scalar {
    let closest = _closestPoints(p1, q1, p2, q2)
    return (closest.a - closest.b).lengthSquared
}

/// Applies a rigid transform to all triangle vertices.
private func _transformed(_ triangle: Triangle, by transform: Transform) -> Triangle {
    Triangle(triangle.p0.applying(transform),
             triangle.p1.applying(transform),
             triangle.p2.applying(transform))
}

/// Transforms a plane into the first primitive's local space.
private func _transformed(_ plane: Plane, by transform: Transform) -> Plane {
    let normal = plane.normal.applying(transform.orientation)
    return Plane(normal.x, normal.y, normal.z, plane.d - Vector3.dot(normal, transform.position))
}

/// Triangle-plane overlap is true when triangle vertices lie on both sides or on the plane.
private func _trianglePlaneOverlaps(_ triangle: Triangle, _ plane: Plane) -> Bool {
    let d0 = plane.dot(triangle.p0)
    let d1 = plane.dot(triangle.p1)
    let d2 = plane.dot(triangle.p2)
    let minDistance = Swift.min(d0, d1, d2)
    let maxDistance = Swift.max(d0, d1, d2)
    return minDistance <= _overlapEpsilon && maxDistance >= -_overlapEpsilon
}
