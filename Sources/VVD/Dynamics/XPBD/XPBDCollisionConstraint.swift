//
//  File: XPBDCollisionConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Keeps one XPBD particle outside a collider surface by at least its radius.
///
/// Closed primitives use their outward surface normal while the particle is
/// contained. Open surfaces are treated as two-sided and orient the correction
/// toward the side containing the particle.
public final class XPBDParticleCollisionConstraint: XPBDConstraint {
    public let particle: XPBDParticleReference
    public let collider: Collider
    public var particleRadius: Scalar
    public var compliance: Scalar
    public var isEnabled: Bool
    public private(set) var accumulatedMultiplier: Scalar

    public var particleReferences: [XPBDParticleReference] { [particle] }

    public init(particle: XPBDParticleReference,
                collider: Collider,
                particleRadius: Scalar = .zero,
                compliance: Scalar = .zero,
                isEnabled: Bool = true) {
        self.particle = particle
        self.collider = collider
        self.particleRadius = particleRadius
        self.compliance = compliance
        self.isEnabled = isEnabled
        self.accumulatedMultiplier = .zero
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultiplier = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              collider.isEnabled,
              collider.isValid,
              particleRadius.isFinite,
              particleRadius >= .zero,
              let position = particle.particle?.position,
              position._xpbdIsFinite
        else { return [] }

        let inverseTransform = collider.transform.inverted()
        let localPosition = position.applying(inverseTransform)
        guard let closest = collider.primitive.closestPoint(to: localPosition),
              closest.position._xpbdIsFinite,
              closest.normal._xpbdIsFinite,
              closest.distance.isFinite,
              closest.distance >= .zero
        else { return [] }

        let localOffset = localPosition - closest.position
        let localNormal: Vector3
        let signedDistance: Scalar
        if collider.primitive.contains(localPosition) {
            localNormal = closest.normal.normalized()
            signedDistance = -closest.distance
        } else if localOffset.lengthSquared > Scalar.ulpOfOne {
            localNormal = localOffset.normalized()
            signedDistance = closest.distance
        } else {
            localNormal = closest.normal.normalized()
            signedDistance = .zero
        }

        let normal = localNormal
            .applying(collider.transform.orientation)
            .normalized()
        let value = signedDistance - particleRadius
        guard normal._xpbdIsFinite,
              normal.lengthSquared > Scalar.ulpOfOne,
              value.isFinite
        else { return [] }
        // A later projection can separate the particle after contact has
        // already corrected it. Keep the row until that multiplier is released.
        guard value < .zero || accumulatedMultiplier > .zero else { return [] }

        return [XPBDConstraintProjection(
            multiplierIndex: 0,
            value: value,
            gradients: [XPBDConstraintGradient(particle: particle,
                                                gradient: normal)],
            compliance: compliance,
            accumulatedMultiplier: accumulatedMultiplier,
            lowerMultiplier: .zero)]
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard index == 0 else { return }
        accumulatedMultiplier = multiplier
    }
}

public extension XPBDBody {
    /// Builds one particle collision constraint for each current particle.
    func makeCollisionConstraints(
        against collider: Collider,
        particleRadius: Scalar = .zero,
        compliance: Scalar = .zero
    ) -> [XPBDParticleCollisionConstraint] {
        particles.indices.map { index in
            XPBDParticleCollisionConstraint(
                particle: XPBDParticleReference(body: self,
                                                 particleIndex: index),
                collider: collider,
                particleRadius: particleRadius,
                compliance: compliance)
        }
    }
}

private extension Vector3 {
    var _xpbdIsFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
