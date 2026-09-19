//
//  File: SoftBody.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public final class SoftBody: XPBDBody {
    public var particles: [XPBDParticle]
    public var tetrahedra: [XPBDParticleTetrahedron]

    public init(particles: [XPBDParticle] = [],
                tetrahedra: [XPBDParticleTetrahedron] = []) {
        self.particles = particles
        self.tetrahedra = tetrahedra
    }

    public func makeVolumeConstraints(
        compliance: Scalar = .zero
    ) -> [XPBDVolumeConstraint] {
        tetrahedra.compactMap { tetrahedron in
            guard tetrahedron.isValid(particleCount: particles.count) else {
                return nil
            }
            return XPBDVolumeConstraint(
                particleA: XPBDParticleReference(body: self,
                                                 particleIndex: tetrahedron.a),
                particleB: XPBDParticleReference(body: self,
                                                 particleIndex: tetrahedron.b),
                particleC: XPBDParticleReference(body: self,
                                                 particleIndex: tetrahedron.c),
                particleD: XPBDParticleReference(body: self,
                                                 particleIndex: tetrahedron.d),
                compliance: compliance)
        }
    }
}
