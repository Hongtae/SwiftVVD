//
//  File: XPBDConstraintProjection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Stable identity for one particle stored by an `XPBDBody`.
///
/// The reference retains its body and resolves the particle through its current
/// array storage, so replacing the array does not invalidate a valid index.
public struct XPBDParticleReference: Hashable {
    public let body: any XPBDBody
    public let particleIndex: Int

    public init(body: any XPBDBody, particleIndex: Int) {
        self.body = body
        self.particleIndex = particleIndex
    }

    public var isValid: Bool {
        body.particles.indices.contains(particleIndex)
    }

    public var particle: XPBDParticle? {
        guard isValid else { return nil }
        return body.particles[particleIndex]
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs.body) == ObjectIdentifier(rhs.body) &&
            lhs.particleIndex == rhs.particleIndex
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(body))
        hasher.combine(particleIndex)
    }
}

/// Gradient of one scalar constraint with respect to one particle position.
public struct XPBDConstraintGradient: Hashable {
    public let particle: XPBDParticleReference
    public let gradient: Vector3

    public init(particle: XPBDParticleReference, gradient: Vector3) {
        self.particle = particle
        self.gradient = gradient
    }
}

/// One scalar position constraint consumed by an XPBD solver.
///
/// For constraint value `C`, gradients `g`, inverse particle masses `w`, and
/// `alpha = compliance / timeStep^2`, the solver computes
/// `deltaLambda = (-C - alpha * accumulatedMultiplier) /
/// (sum(w * dot(g, g)) + alpha)` and applies
/// `deltaPosition = w * g * deltaLambda`.
public struct XPBDConstraintProjection: Hashable {
    /// Stable multiplier slot owned by the source constraint.
    public let multiplierIndex: Int
    public let value: Scalar
    public let gradients: [XPBDConstraintGradient]
    public let compliance: Scalar
    public let accumulatedMultiplier: Scalar
    public let lowerMultiplier: Scalar
    public let upperMultiplier: Scalar

    public init(multiplierIndex: Int,
                value: Scalar,
                gradients: [XPBDConstraintGradient],
                compliance: Scalar = .zero,
                accumulatedMultiplier: Scalar = .zero,
                lowerMultiplier: Scalar = -.infinity,
                upperMultiplier: Scalar = .infinity) {
        self.multiplierIndex = multiplierIndex
        self.value = value
        self.gradients = gradients
        self.compliance = compliance
        self.accumulatedMultiplier = accumulatedMultiplier
        self.lowerMultiplier = lowerMultiplier
        self.upperMultiplier = upperMultiplier
    }
}
