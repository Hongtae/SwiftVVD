//
//  File: ConvexHull.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct ConvexHull: ConvexPrimitive, Sendable {
    public let vertices: [Vector3]
    /// Convex face loops indexing `vertices` in outward winding order.
    ///
    /// An empty array keeps the hull usable as a support-mapped vertex cloud,
    /// but surface queries require validated face topology.
    public let faces: [[Int]]
    public let bounds: AABB

    private let surfacePlanes: [_ConvexHullSurfacePlane]?

    public var isValid: Bool {
        vertices.isEmpty == false && bounds.isNull == false &&
            (faces.isEmpty || surfacePlanes != nil)
    }

    /// Whether the hull has a closed, convex surface suitable for point and
    /// ray queries.
    public var hasSurfaceTopology: Bool {
        surfacePlanes != nil
    }

    public init() {
        self.init(vertices: [])
    }

    public init(vertices: [Vector3]) {
        self.init(vertices: vertices, faces: [])
    }

    /// Creates a convex hull with optional indexed surface topology.
    ///
    /// Every face must be a planar convex loop with outward winding. The face
    /// loops must form a closed two-manifold, with each undirected edge used
    /// once in each direction. Invalid nonempty topology makes the hull
    /// invalid. Interior or otherwise redundant vertices may remain unreferenced.
    public init(vertices: [Vector3], faces: [[Int]]) {
        let bounds = AABB(vertices)
        self.vertices = vertices
        self.faces = faces
        self.bounds = bounds
        self.surfacePlanes = Self.makeSurfacePlanes(vertices: vertices,
                                                    faces: faces,
                                                    bounds: bounds)
    }

    public func contains(_ point: Vector3) -> Bool {
        guard isValid, let surfacePlanes else { return false }
        let tolerance = Self.surfaceTolerance(for: bounds)
        return surfacePlanes.allSatisfy {
            Vector3.dot($0.normal, point) - $0.offset <= tolerance
        }
    }

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid, let surfacePlanes else { return nil }

        var closest: PrimitiveClosestPoint?
        for (faceIndex, face) in faces.enumerated() {
            let first = vertices[face[0]]
            for index in 1..<(face.count - 1) {
                let triangle = Triangle(first,
                                        vertices[face[index]],
                                        vertices[face[index + 1]])
                let position = triangle.closestPoint(to: point)
                let distance = (point - position).length
                if closest == nil || distance < closest!.distance {
                    closest = PrimitiveClosestPoint(
                        position: position,
                        normal: surfacePlanes[faceIndex].normal,
                        distance: distance)
                }
            }
        }
        return closest
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid,
              ray.isValid,
              bounds.intersects(ray),
              let surfacePlanes
        else { return nil }

        let surfaceTolerance = Self.surfaceTolerance(for: bounds)
        let parallelTolerance = Self.numericEpsilon *
            Swift.max(ray.direction.length, Scalar(1))
        var nearParameter = -Scalar.infinity
        var farParameter = Scalar.infinity
        var nearNormal = Vector3.zero
        var farNormal = Vector3.zero

        for plane in surfacePlanes {
            let distance = Vector3.dot(plane.normal, ray.origin) - plane.offset
            let denominator = Vector3.dot(plane.normal, ray.direction)

            if abs(denominator) <= parallelTolerance {
                guard distance <= surfaceTolerance else { return nil }
                continue
            }

            let parameter = -distance / denominator
            if denominator < .zero {
                if parameter > nearParameter {
                    nearParameter = parameter
                    nearNormal = plane.normal
                }
            } else if parameter < farParameter {
                farParameter = parameter
                farNormal = plane.normal
            }
            guard nearParameter <= farParameter else { return nil }
        }

        if nearParameter >= .zero {
            return PrimitiveRayHit(parameter: nearParameter,
                                   position: ray.point(at: nearParameter),
                                   normal: nearNormal)
        }
        guard farParameter >= .zero && farParameter.isFinite else { return nil }
        return PrimitiveRayHit(parameter: farParameter,
                               position: ray.point(at: farParameter),
                               normal: farNormal)
    }

    private static let numericEpsilon: Scalar = {
        MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
            ? Scalar(1.0e-9)
            : Scalar(1.0e-5)
    }()

    private static func surfaceTolerance(for bounds: AABB) -> Scalar {
        Swift.max(bounds.extents.length, Scalar(1)) * numericEpsilon
    }

    private static func makeSurfacePlanes(vertices: [Vector3],
                                          faces: [[Int]],
                                          bounds: AABB) -> [_ConvexHullSurfacePlane]? {
        guard faces.isEmpty == false,
              faces.count >= 4,
              vertices.count >= 4,
              bounds.isNull == false,
              vertices.allSatisfy({ vertex in
                  vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite
              })
        else { return nil }

        let tolerance = surfaceTolerance(for: bounds)
        let areaTolerance = tolerance * tolerance
        let center = vertices.reduce(Vector3.zero, +) / Scalar(vertices.count)
        var edgeUses: [_ConvexHullEdge: _ConvexHullEdgeUse] = [:]
        var planes: [_ConvexHullSurfacePlane] = []
        planes.reserveCapacity(faces.count)

        for face in faces {
            guard face.count >= 3,
                  Set(face).count == face.count,
                  face.allSatisfy({ vertices.indices.contains($0) })
            else { return nil }

            let first = vertices[face[0]]
            var rawNormal = Vector3.zero
            for index in 1..<(face.count - 1) {
                let candidate = Vector3.cross(vertices[face[index]] - first,
                                              vertices[face[index + 1]] - first)
                if candidate.lengthSquared > areaTolerance {
                    rawNormal = candidate
                    break
                }
            }
            guard rawNormal.lengthSquared > areaTolerance else { return nil }

            let normal = rawNormal.normalized()
            let offset = Vector3.dot(normal, first)

            // The average of a full-dimensional convex vertex set lies
            // strictly behind every outward face.
            guard Vector3.dot(normal, center) - offset < -tolerance else {
                return nil
            }

            for vertexIndex in face {
                let distance = Vector3.dot(normal, vertices[vertexIndex]) - offset
                guard abs(distance) <= tolerance else { return nil }
            }
            for vertex in vertices {
                guard Vector3.dot(normal, vertex) - offset <= tolerance else {
                    return nil
                }
            }

            for index in face.indices {
                let previous = vertices[face[(index + face.count - 1) % face.count]]
                let current = vertices[face[index]]
                let next = vertices[face[(index + 1) % face.count]]
                let incoming = current - previous
                let outgoing = next - current
                guard incoming.length > tolerance,
                      outgoing.length > tolerance,
                      Vector3.dot(Vector3.cross(incoming, outgoing), normal) >=
                        -areaTolerance
                else { return nil }

                let edge = _ConvexHullEdge(face[index],
                                           face[(index + 1) % face.count])
                var use = edgeUses[edge] ?? _ConvexHullEdgeUse()
                use.count += 1
                use.directionBalance += face[index] < face[(index + 1) % face.count]
                    ? 1
                    : -1
                edgeUses[edge] = use
            }
            planes.append(_ConvexHullSurfacePlane(normal: normal, offset: offset))
        }

        guard edgeUses.values.allSatisfy({
            $0.count == 2 && $0.directionBalance == 0
        }) else { return nil }
        return planes
    }
}

private struct _ConvexHullSurfacePlane: Hashable, Sendable {
    let normal: Vector3
    let offset: Scalar
}

private struct _ConvexHullEdge: Hashable, Sendable {
    let lower: Int
    let upper: Int

    init(_ first: Int, _ second: Int) {
        lower = Swift.min(first, second)
        upper = Swift.max(first, second)
    }
}

private struct _ConvexHullEdgeUse {
    var count = 0
    var directionBalance = 0
}

public struct ConvexHullShape: ConvexShape {
    public let primitive: ConvexHull

    public init(_ primitive: ConvexHull) {
        self.primitive = primitive
    }
}
