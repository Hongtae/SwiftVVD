//
//  File: XPBDProjectionSolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Predicts particle positions and resolves scalar constraints with XPBD.
public final class XPBDProjectionSolver: XPBDSolver {
    /// Number of sequential projection passes performed for each step.
    public var projectionIterations: Int
    /// Exponential damping rate applied after velocity reconstruction.
    public var velocityDamping: Scalar

    public init(projectionIterations: Int = 8,
                velocityDamping: Scalar = .zero) {
        self.projectionIterations = projectionIterations
        self.velocityDamping = velocityDamping
    }

    public func solve(_ context: XPBDSolverContext) {
        let timeStep = context.timeStep
        guard timeStep.isFinite, timeStep > .zero else { return }

        let bodies = uniqueBodies(context.bodies)
        let bodyIdentifiers = Set(bodies.map(ObjectIdentifier.init))
        predictPositions(bodies,
                         gravity: context.gravity,
                         timeStep: timeStep)

        let constraints = eligibleConstraints(
            context.constraints,
            bodyIdentifiers: bodyIdentifiers)
        for constraint in constraints {
            constraint.resetAccumulatedMultipliers()
        }

        for _ in 0..<Swift.max(projectionIterations, 0) {
            for constraint in constraints {
                solve(constraint,
                      bodyIdentifiers: bodyIdentifiers,
                      timeStep: timeStep)
            }
        }

        updateVelocities(bodies, timeStep: timeStep)
    }

    private func uniqueBodies(_ bodies: [any XPBDBody]) -> [any XPBDBody] {
        var identifiers: Set<ObjectIdentifier> = []
        return bodies.filter { identifiers.insert(ObjectIdentifier($0)).inserted }
    }

    private func predictPositions(_ bodies: [any XPBDBody],
                                  gravity: Vector3,
                                  timeStep: Scalar) {
        let acceleration = gravity.isFiniteVector ? gravity : .zero
        for body in bodies {
            var particles = body.particles
            for index in particles.indices {
                var particle = particles[index]
                particle.previousPosition = particle.position
                guard particle.position.isFiniteVector else {
                    particle.velocity = .zero
                    particles[index] = particle
                    continue
                }
                guard particle.inverseMass.isFinite,
                      particle.inverseMass > .zero else {
                    particle.velocity = .zero
                    particles[index] = particle
                    continue
                }
                if !particle.velocity.isFiniteVector {
                    particle.velocity = .zero
                }
                particle.velocity += acceleration * timeStep
                particle.position += particle.velocity * timeStep
                particles[index] = particle
            }
            body.particles = particles
        }
    }

    private func eligibleConstraints(
        _ constraints: [any XPBDConstraint],
        bodyIdentifiers: Set<ObjectIdentifier>
    ) -> [any XPBDConstraint] {
        var identifiers: Set<ObjectIdentifier> = []
        return constraints.filter { constraint in
            guard constraint.isEnabled,
                  identifiers.insert(ObjectIdentifier(constraint)).inserted
            else { return false }
            return constraint.particleReferences.allSatisfy { reference in
                reference.isValid &&
                    bodyIdentifiers.contains(ObjectIdentifier(reference.body))
            }
        }
    }

    private func solve(_ constraint: any XPBDConstraint,
                       bodyIdentifiers: Set<ObjectIdentifier>,
                       timeStep: Scalar) {
        for projection in constraint.projections() {
            guard projection.multiplierIndex >= 0,
                  projection.value.isFinite,
                  projection.accumulatedMultiplier.isFinite,
                  !projection.lowerMultiplier.isNaN,
                  !projection.upperMultiplier.isNaN,
                  projection.lowerMultiplier <= projection.upperMultiplier,
                  projection.gradients.isEmpty == false
            else { continue }

            let compliance: Scalar
            if projection.compliance == .infinity {
                continue
            } else if projection.compliance.isFinite {
                compliance = Swift.max(projection.compliance, .zero)
            } else {
                continue
            }

            guard let gradients = combinedGradients(
                projection.gradients,
                bodyIdentifiers: bodyIdentifiers) else { continue }

            let alpha = compliance / (timeStep * timeStep)
            var denominator = alpha
            for entry in gradients {
                let inverseMass = effectiveInverseMass(entry.particle)
                denominator += inverseMass *
                    Vector3.dot(entry.gradient, entry.gradient)
            }
            guard denominator.isFinite,
                  denominator > Scalar.ulpOfOne else { continue }

            let deltaMultiplier = (-projection.value -
                alpha * projection.accumulatedMultiplier) / denominator
            guard deltaMultiplier.isFinite else { continue }
            let accumulatedMultiplier = (
                projection.accumulatedMultiplier + deltaMultiplier).clamp(
                    min: projection.lowerMultiplier,
                    max: projection.upperMultiplier)
            let appliedMultiplier = accumulatedMultiplier -
                projection.accumulatedMultiplier
            guard appliedMultiplier.isFinite else { continue }

            for entry in gradients {
                let inverseMass = effectiveInverseMass(entry.particle)
                guard inverseMass > .zero else { continue }
                applyPositionCorrection(
                    entry.gradient * (inverseMass * appliedMultiplier),
                    to: entry.particle)
            }
            constraint.setAccumulatedMultiplier(
                accumulatedMultiplier,
                at: projection.multiplierIndex)
        }
    }

    private func combinedGradients(
        _ gradients: [XPBDConstraintGradient],
        bodyIdentifiers: Set<ObjectIdentifier>
    ) -> [(particle: XPBDParticleReference, gradient: Vector3)]? {
        var indices: [XPBDParticleReference: Int] = [:]
        var combined: [(particle: XPBDParticleReference, gradient: Vector3)] = []
        combined.reserveCapacity(gradients.count)

        for entry in gradients {
            guard entry.gradient.isFiniteVector,
                  entry.particle.isValid,
                  bodyIdentifiers.contains(ObjectIdentifier(entry.particle.body))
            else { return nil }
            if let index = indices[entry.particle] {
                combined[index].gradient += entry.gradient
            } else {
                indices[entry.particle] = combined.count
                combined.append((entry.particle, entry.gradient))
            }
        }
        return combined
    }

    private func effectiveInverseMass(
        _ reference: XPBDParticleReference
    ) -> Scalar {
        guard let particle = reference.particle,
              particle.inverseMass.isFinite,
              particle.inverseMass > .zero
        else { return .zero }
        return particle.inverseMass
    }

    private func applyPositionCorrection(
        _ correction: Vector3,
        to reference: XPBDParticleReference
    ) {
        guard correction.isFiniteVector else { return }
        var particles = reference.body.particles
        guard particles.indices.contains(reference.particleIndex) else { return }
        particles[reference.particleIndex].position += correction
        reference.body.particles = particles
    }

    private func updateVelocities(_ bodies: [any XPBDBody],
                                  timeStep: Scalar) {
        let damping: Scalar
        if velocityDamping == .infinity {
            damping = .zero
        } else if velocityDamping.isFinite {
            damping = exp(-Swift.max(velocityDamping, .zero) * timeStep)
        } else {
            damping = Scalar(1)
        }

        for body in bodies {
            var particles = body.particles
            for index in particles.indices {
                var particle = particles[index]
                guard particle.inverseMass.isFinite,
                      particle.inverseMass > .zero,
                      particle.position.isFiniteVector,
                      particle.previousPosition.isFiniteVector
                else {
                    particle.velocity = .zero
                    particles[index] = particle
                    continue
                }
                particle.velocity = (particle.position -
                    particle.previousPosition) / timeStep * damping
                particles[index] = particle
            }
            body.particles = particles
        }
    }
}

private extension Vector3 {
    var isFiniteVector: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
