//
//  File: XPBDStructuralConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Preserves the rest distance between two particles.
public class XPBDDistanceConstraint: XPBDConstraint {
    public let particleA: XPBDParticleReference
    public let particleB: XPBDParticleReference
    public var restLength: Scalar
    public var compliance: Scalar
    public var isEnabled: Bool
    public private(set) var accumulatedMultiplier: Scalar

    private let fallbackDirection: Vector3

    public var particleReferences: [XPBDParticleReference] {
        [particleA, particleB]
    }

    public init(particleA: XPBDParticleReference,
                particleB: XPBDParticleReference,
                restLength: Scalar? = nil,
                compliance: Scalar = .zero,
                isEnabled: Bool = true) {
        let delta = (particleB.particle?.position ?? .zero) -
            (particleA.particle?.position ?? .zero)
        let length = delta.length
        self.particleA = particleA
        self.particleB = particleB
        self.restLength = restLength ?? length
        self.compliance = compliance
        self.isEnabled = isEnabled
        self.accumulatedMultiplier = .zero
        self.fallbackDirection = length > Scalar.ulpOfOne
            ? delta / length : Vector3(1, 0, 0)
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultiplier = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              restLength.isFinite,
              restLength >= .zero,
              let positionA = particleA.particle?.position,
              let positionB = particleB.particle?.position
        else { return [] }

        let delta = positionB - positionA
        let length = delta.length
        guard length.isFinite else { return [] }
        let direction = length > Scalar.ulpOfOne
            ? delta / length : fallbackDirection
        return [XPBDConstraintProjection(
            multiplierIndex: 0,
            value: length - restLength,
            gradients: [
                XPBDConstraintGradient(particle: particleA,
                                       gradient: -direction),
                XPBDConstraintGradient(particle: particleB,
                                       gradient: direction)
            ],
            compliance: compliance,
            accumulatedMultiplier: accumulatedMultiplier)]
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard index == 0 else { return }
        accumulatedMultiplier = multiplier
    }
}

/// Distance-bending model used between particles separated by one rope vertex
/// or by one shared cloth edge.
public final class XPBDBendingConstraint: XPBDDistanceConstraint {}

/// Preserves the signed volume of one particle tetrahedron.
public final class XPBDVolumeConstraint: XPBDConstraint {
    public let particleA: XPBDParticleReference
    public let particleB: XPBDParticleReference
    public let particleC: XPBDParticleReference
    public let particleD: XPBDParticleReference
    public var restVolume: Scalar
    public var compliance: Scalar
    public var isEnabled: Bool
    public private(set) var accumulatedMultiplier: Scalar

    public var particleReferences: [XPBDParticleReference] {
        [particleA, particleB, particleC, particleD]
    }

    public init(particleA: XPBDParticleReference,
                particleB: XPBDParticleReference,
                particleC: XPBDParticleReference,
                particleD: XPBDParticleReference,
                restVolume: Scalar? = nil,
                compliance: Scalar = .zero,
                isEnabled: Bool = true) {
        self.particleA = particleA
        self.particleB = particleB
        self.particleC = particleC
        self.particleD = particleD
        self.restVolume = restVolume ?? Self.currentVolume(
            particleA, particleB, particleC, particleD) ?? .zero
        self.compliance = compliance
        self.isEnabled = isEnabled
        self.accumulatedMultiplier = .zero
    }

    public static func signedVolume(_ a: Vector3,
                                    _ b: Vector3,
                                    _ c: Vector3,
                                    _ d: Vector3) -> Scalar {
        Vector3.dot(b - a, Vector3.cross(c - a, d - a)) / Scalar(6)
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultiplier = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              restVolume.isFinite,
              let a = particleA.particle?.position,
              let b = particleB.particle?.position,
              let c = particleC.particle?.position,
              let d = particleD.particle?.position
        else { return [] }

        let oneSixth = Scalar(1) / Scalar(6)
        let gradientB = Vector3.cross(c - a, d - a) * oneSixth
        let gradientC = Vector3.cross(d - a, b - a) * oneSixth
        let gradientD = Vector3.cross(b - a, c - a) * oneSixth
        let gradientA = -(gradientB + gradientC + gradientD)
        return [XPBDConstraintProjection(
            multiplierIndex: 0,
            value: Self.signedVolume(a, b, c, d) - restVolume,
            gradients: [
                XPBDConstraintGradient(particle: particleA,
                                       gradient: gradientA),
                XPBDConstraintGradient(particle: particleB,
                                       gradient: gradientB),
                XPBDConstraintGradient(particle: particleC,
                                       gradient: gradientC),
                XPBDConstraintGradient(particle: particleD,
                                       gradient: gradientD)
            ],
            compliance: compliance,
            accumulatedMultiplier: accumulatedMultiplier)]
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard index == 0 else { return }
        accumulatedMultiplier = multiplier
    }

    private static func currentVolume(
        _ particleA: XPBDParticleReference,
        _ particleB: XPBDParticleReference,
        _ particleC: XPBDParticleReference,
        _ particleD: XPBDParticleReference
    ) -> Scalar? {
        guard let a = particleA.particle?.position,
              let b = particleB.particle?.position,
              let c = particleC.particle?.position,
              let d = particleD.particle?.position
        else { return nil }
        return signedVolume(a, b, c, d)
    }
}
