//
//  File: RopeBody.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public final class RopeBody: XPBDBody {
    public var particles: [XPBDParticle]
    public var segments: [XPBDParticleEdge]

    public init(particles: [XPBDParticle] = [],
                segments: [XPBDParticleEdge]? = nil) {
        self.particles = particles
        if let segments {
            self.segments = segments
        } else if particles.count > 1 {
            self.segments = (1..<particles.count).map {
                XPBDParticleEdge($0 - 1, $0)
            }
        } else {
            self.segments = []
        }
    }

    public func makeDistanceConstraints(
        compliance: Scalar = .zero
    ) -> [XPBDDistanceConstraint] {
        segments.compactMap { edge in
            guard edge.isValid(particleCount: particles.count) else { return nil }
            return XPBDDistanceConstraint(
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
        var neighbors: [Int: Set<Int>] = [:]
        for edge in segments
        where edge.isValid(particleCount: particles.count) {
            neighbors[edge.first, default: []].insert(edge.second)
            neighbors[edge.second, default: []].insert(edge.first)
        }

        var bendingEdges: Set<XPBDParticleEdge> = []
        for adjacent in neighbors.values {
            let indices = adjacent.sorted()
            guard indices.count > 1 else { continue }
            for first in 0..<(indices.count - 1) {
                for second in (first + 1)..<indices.count {
                    bendingEdges.insert(XPBDParticleEdge(indices[first],
                                                         indices[second]))
                }
            }
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
