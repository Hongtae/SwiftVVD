//
//  File: TriangleMesh.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol TriangleMeshStorage: AnyObject {
    var bounds: AABB { get }
    var isValid: Bool { get }
    var triangleCount: Int { get }

    func triangle(at index: Int) -> Triangle
    /// Visits triangle indices whose local bounds overlap `queryBounds`.
    ///
    /// Candidate order is unspecified. Return `false` from `body` to stop the
    /// query. Implementations may use an acceleration structure; the default
    /// implementation performs an exact linear bounds scan.
    @discardableResult
    func queryTriangles(overlapping queryBounds: AABB,
                        _ body: (Int) -> Bool) -> Bool
    func contains(_ point: Vector3) -> Bool
    func rayTest(_ ray: Ray) -> PrimitiveRayHit?
}

public extension TriangleMeshStorage {
    @discardableResult
    func queryTriangles(overlapping queryBounds: AABB,
                        _ body: (Int) -> Bool) -> Bool {
        guard queryBounds.isNull == false else { return true }

        for index in 0..<triangleCount
        where triangle(at: index).aabb.intersects(queryBounds) {
            if body(index) == false { return false }
        }
        return true
    }
}

public struct TriangleMesh: ConcavePrimitive {
    public let storage: any TriangleMeshStorage

    public init() {
        self.storage = EmptyTriangleMeshStorage.shared
    }

    public init(storage: any TriangleMeshStorage) {
        self.storage = storage
    }

    public init(triangles: [Triangle]) {
        self.storage = TriangleArrayMeshStorage(triangles)
    }

    public var bounds: AABB {
        storage.bounds
    }

    public var isValid: Bool {
        storage.isValid
    }

    public var triangleCount: Int {
        storage.triangleCount
    }

    public func triangle(at index: Int) -> Triangle {
        storage.triangle(at: index)
    }

    /// Visits storage-defined triangle candidates overlapping local bounds.
    @discardableResult
    public func queryTriangles(overlapping queryBounds: AABB,
                               _ body: (Int) -> Bool) -> Bool {
        storage.queryTriangles(overlapping: queryBounds, body)
    }

    public func contains(_ point: Vector3) -> Bool {
        storage.contains(point)
    }

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid else { return nil }

        var closest: PrimitiveClosestPoint?
        for index in 0..<triangleCount {
            let triangle = triangle(at: index)
            guard triangle.area > .ulpOfOne else { continue }
            let position = triangle.closestPoint(to: point)
            let distance = (point - position).length
            if closest == nil || distance < closest!.distance {
                closest = PrimitiveClosestPoint(position: position,
                                                normal: triangle.normal,
                                                distance: distance)
            }
        }
        return closest
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        storage.rayTest(ray)
    }
}

extension TriangleMesh: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(storage))
    }
}

private final class EmptyTriangleMeshStorage: TriangleMeshStorage, @unchecked Sendable {
    static let shared = EmptyTriangleMeshStorage()

    var bounds: AABB {
        .null
    }

    var triangleCount: Int {
        0
    }

    var isValid: Bool {
        false
    }

    private init() {
    }

    func triangle(at index: Int) -> Triangle {
        preconditionFailure("Triangle index is out of range.")
    }

    func contains(_ point: Vector3) -> Bool {
        false
    }

    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        nil
    }
}

/// Immutable triangle-array storage with a BVH-accelerated ray query.
///
/// Face normals follow triangle winding. `contains(_:)` treats points on the
/// surface as contained and uses a signed solid-angle test for other points;
/// interior classification therefore requires a closed, consistently wound
/// mesh.
public final class TriangleArrayMeshStorage: TriangleMeshStorage, Sendable {
    public let triangles: [Triangle]
    public let bounds: AABB
    public let isValid: Bool

    private let hierarchy: BVH

    public var triangleCount: Int { triangles.count }

    public init(_ triangles: [Triangle]) {
        self.triangles = triangles

        var bounds = AABB.null
        var elements: [BVH.Element] = []
        elements.reserveCapacity(triangles.count)
        var hasValidTriangle = false
        for (index, triangle) in triangles.enumerated() {
            let triangleBounds = triangle.aabb
            bounds.combine(triangleBounds)
            if triangle.area > .ulpOfOne {
                hasValidTriangle = true
                elements.append(BVH.Element(bounds: triangleBounds,
                                            primitiveIndex: index))
            }
        }
        self.bounds = bounds
        self.isValid = hasValidTriangle
        self.hierarchy = BVH(elements)
    }

    public func triangle(at index: Int) -> Triangle {
        triangles[index]
    }

    @discardableResult
    public func queryTriangles(overlapping queryBounds: AABB,
                               _ body: (Int) -> Bool) -> Bool {
        hierarchy.query(overlapping: queryBounds, body)
    }

    public func contains(_ point: Vector3) -> Bool {
        guard isValid else { return false }

        let tolerance = Swift.max(bounds.extents.length, Scalar(1)) *
            Self.containmentEpsilon
        guard point.x >= bounds.min.x - tolerance,
              point.x <= bounds.max.x + tolerance,
              point.y >= bounds.min.y - tolerance,
              point.y <= bounds.max.y + tolerance,
              point.z >= bounds.min.z - tolerance,
              point.z <= bounds.max.z + tolerance
        else { return false }

        var solidAngle: Scalar = .zero
        for triangle in triangles where triangle.area > .ulpOfOne {
            if Self.containsOnSurface(point,
                                      triangle: triangle,
                                      tolerance: tolerance) {
                return true
            }

            let a = triangle.p0 - point
            let b = triangle.p1 - point
            let c = triangle.p2 - point
            let numerator = Vector3.dot(a, Vector3.cross(b, c))
            let denominator = a.length * b.length * c.length +
                Vector3.dot(a, b) * c.length +
                Vector3.dot(b, c) * a.length +
                Vector3.dot(c, a) * b.length
            solidAngle += 2 * atan2(numerator, denominator)
        }
        return abs(solidAngle) > Scalar.pi * 2
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid && bounds.intersects(ray) else { return nil }

        var closest: PrimitiveRayHit?
        hierarchy.query(intersecting: ray) { index in
            let triangle = triangles[index]
            if let result = triangle.rayTest(rayOrigin: ray.origin,
                                             direction: ray.direction) {
                _updateClosestRayHit(ray: ray,
                                     parameter: result.t,
                                     normal: triangle.normal,
                                     closest: &closest)
            }
            return true
        }
        return closest
    }

    private static let containmentEpsilon: Scalar = {
        MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
            ? Scalar(1.0e-9)
            : Scalar(1.0e-5)
    }()

    private static func containsOnSurface(_ point: Vector3,
                                          triangle: Triangle,
                                          tolerance: Scalar) -> Bool {
        let normal = Vector3.cross(triangle.p1 - triangle.p0,
                                   triangle.p2 - triangle.p0)
        let normalLength = normal.length
        guard normalLength > .ulpOfOne,
              abs(Vector3.dot(point - triangle.p0, normal)) <=
                tolerance * normalLength,
              let barycentric = triangle.barycentric(at: point)
        else { return false }

        let barycentricTolerance = containmentEpsilon
        return barycentric.x >= -barycentricTolerance &&
            barycentric.y >= -barycentricTolerance &&
            barycentric.z >= -barycentricTolerance &&
            barycentric.x <= 1 + barycentricTolerance &&
            barycentric.y <= 1 + barycentricTolerance &&
            barycentric.z <= 1 + barycentricTolerance
    }
}

public struct TriangleMeshShape: ConcaveShape {
    public let primitive: TriangleMesh

    public init(_ primitive: TriangleMesh) {
        self.primitive = primitive
    }
}
