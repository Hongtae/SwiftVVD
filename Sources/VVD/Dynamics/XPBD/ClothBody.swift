//
//  File: ClothBody.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public final class ClothBody: XPBDBody {
    public var particles: [XPBDParticle]
    public var triangles: [XPBDParticleTriangle]

    public init(particles: [XPBDParticle] = [],
                triangles: [XPBDParticleTriangle] = []) {
        self.particles = particles
        self.triangles = triangles
    }

    public func makeDistanceConstraints(
        compliance: Scalar = .zero
    ) -> [XPBDDistanceConstraint] {
        var edges: Set<XPBDParticleEdge> = []
        for triangle in triangles
        where triangle.isValid(particleCount: particles.count) {
            edges.formUnion(triangle.edges)
        }
        return edges.sorted {
            ($0.first, $0.second) < ($1.first, $1.second)
        }.map { edge in
            XPBDDistanceConstraint(
                particleA: XPBDParticleReference(body: self,
                                                 particleIndex: edge.first),
                particleB: XPBDParticleReference(body: self,
                                                 particleIndex: edge.second),
                compliance: compliance)
        }
    }

    public func makeBendingConstraints(
        compliance: Scalar = .zero
    ) -> [XPBDBendingConstraint] {
        var oppositeVertices: [XPBDParticleEdge: [Int]] = [:]
        for triangle in triangles
        where triangle.isValid(particleCount: particles.count) {
            oppositeVertices[XPBDParticleEdge(triangle.a, triangle.b),
                             default: []].append(triangle.c)
            oppositeVertices[XPBDParticleEdge(triangle.b, triangle.c),
                             default: []].append(triangle.a)
            oppositeVertices[XPBDParticleEdge(triangle.c, triangle.a),
                             default: []].append(triangle.b)
        }

        var bendingEdges: Set<XPBDParticleEdge> = []
        for vertices in oppositeVertices.values {
            let uniqueVertices = Set(vertices)
            guard uniqueVertices.count == 2,
                  let first = uniqueVertices.min(),
                  let second = uniqueVertices.max()
            else { continue }
            bendingEdges.insert(XPBDParticleEdge(first, second))
        }
        return bendingEdges.sorted {
            ($0.first, $0.second) < ($1.first, $1.second)
        }.map { edge in
            XPBDBendingConstraint(
                particleA: XPBDParticleReference(body: self,
                                                 particleIndex: edge.first),
                particleB: XPBDParticleReference(body: self,
                                                 particleIndex: edge.second),
                compliance: compliance)
        }
    }
}
