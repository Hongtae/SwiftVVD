//
//  File: XPBDConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Type-erased position constraint owned by an `XPBDSimulator`.
public protocol XPBDConstraint: AnyObject {
    var isEnabled: Bool { get set }
    /// Particles whose positions may be read or corrected by this constraint.
    var particleReferences: [XPBDParticleReference] { get }

    /// Clears multipliers before the first projection iteration of a step.
    func resetAccumulatedMultipliers()
    /// Builds scalar projections from the current predicted particle positions.
    func projections() -> [XPBDConstraintProjection]
    /// Stores the solver-updated multiplier for a stable projection slot.
    func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int)
}

public extension XPBDConstraint {
    var particleReferences: [XPBDParticleReference] { [] }
    func resetAccumulatedMultipliers() {}
    func projections() -> [XPBDConstraintProjection] { [] }
    func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {}
}

public final class XPBDFixedJointConstraint: XPBDConstraint {
    public let particleA: XPBDParticleReference
    public let particleB: XPBDParticleReference?
    public var worldAnchor: Vector3
    public var restOffset: Vector3
    public var compliance: Scalar
    public var isEnabled: Bool
    public private(set) var accumulatedMultipliers: Vector3

    public var particleReferences: [XPBDParticleReference] {
        if let particleB { return [particleA, particleB] }
        return [particleA]
    }

    public init(particleA: XPBDParticleReference,
                particleB: XPBDParticleReference? = nil,
                worldAnchor: Vector3? = nil,
                restOffset: Vector3? = nil,
                compliance: Scalar = .zero,
                isEnabled: Bool = true) {
        let positionA = particleA.particle?.position ?? .zero
        let positionB = particleB?.particle?.position
        let anchor = worldAnchor ?? positionA
        self.particleA = particleA
        self.particleB = particleB
        self.worldAnchor = anchor
        self.restOffset = restOffset ?? (positionB.map { $0 - positionA } ?? .zero)
        self.compliance = compliance
        self.isEnabled = isEnabled
        self.accumulatedMultipliers = .zero
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultipliers = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              let positionA = particleA.particle?.position,
              let positionB = _xpbdSecondPosition(particleB,
                                                  worldAnchor: worldAnchor)
        else { return [] }

        let error = positionB - positionA - restOffset
        return _xpbdAxes.indices.map { index in
            let axis = _xpbdAxes[index]
            return XPBDConstraintProjection(
                multiplierIndex: index,
                value: Vector3.dot(error, axis),
                gradients: _xpbdPairGradients(
                    particleA: particleA,
                    particleB: particleB,
                    axis: axis),
                compliance: compliance,
                accumulatedMultiplier: accumulatedMultipliers[index])
        }
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard 0..<3 ~= index else { return }
        accumulatedMultipliers[index] = multiplier
    }
}

public final class XPBDConfigurableJointConstraint: XPBDConstraint {
    public let particleA: XPBDParticleReference
    public let particleB: XPBDParticleReference?
    public var worldAnchor: Vector3
    public var restOffset: Vector3
    public var orientation: Quaternion
    public var xAxis: XPBDJointAxis
    public var yAxis: XPBDJointAxis
    public var zAxis: XPBDJointAxis
    public var isEnabled: Bool
    public private(set) var accumulatedMultipliers: Vector3

    public var particleReferences: [XPBDParticleReference] {
        if let particleB { return [particleA, particleB] }
        return [particleA]
    }

    public init(particleA: XPBDParticleReference,
                particleB: XPBDParticleReference? = nil,
                worldAnchor: Vector3? = nil,
                restOffset: Vector3? = nil,
                orientation: Quaternion = .identity,
                xAxis: XPBDJointAxis = .free,
                yAxis: XPBDJointAxis = .free,
                zAxis: XPBDJointAxis = .free,
                isEnabled: Bool = true) {
        let positionA = particleA.particle?.position ?? .zero
        let positionB = particleB?.particle?.position
        self.particleA = particleA
        self.particleB = particleB
        self.worldAnchor = worldAnchor ?? positionA
        self.restOffset = restOffset ?? (positionB.map { $0 - positionA } ?? .zero)
        self.orientation = orientation
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
        self.isEnabled = isEnabled
        self.accumulatedMultipliers = .zero
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultipliers = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              let positionA = particleA.particle?.position,
              let positionB = _xpbdSecondPosition(particleB,
                                                  worldAnchor: worldAnchor)
        else { return [] }

        let error = positionB - positionA - restOffset
        let axes = _xpbdAxes.map { $0.applying(orientation) }
        let settings = [xAxis, yAxis, zAxis]
        var projections: [XPBDConstraintProjection] = []
        projections.reserveCapacity(3)

        for index in axes.indices {
            let axis = axes[index]
            let coordinate = Vector3.dot(error, axis)
            guard let parameters = _xpbdProjectionParameters(
                settings[index], coordinate: coordinate,
                accumulatedMultiplier: accumulatedMultipliers[index]) else { continue }
            projections.append(XPBDConstraintProjection(
                multiplierIndex: index,
                value: parameters.value,
                gradients: _xpbdPairGradients(
                    particleA: particleA,
                    particleB: particleB,
                    axis: axis),
                compliance: settings[index].compliance,
                accumulatedMultiplier: accumulatedMultipliers[index],
                lowerMultiplier: parameters.lowerMultiplier,
                upperMultiplier: parameters.upperMultiplier))
        }
        return projections
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard 0..<3 ~= index else { return }
        accumulatedMultipliers[index] = multiplier
    }
}

public final class XPBDGearJointConstraint: XPBDConstraint {
    public let particleA: XPBDParticleReference
    public let particleB: XPBDParticleReference?
    public var axisA: Vector3
    public var axisB: Vector3
    public var ratio: Scalar
    public var targetCoordinate: Scalar
    public var compliance: Scalar
    public var isEnabled: Bool
    public private(set) var accumulatedMultiplier: Scalar

    public var particleReferences: [XPBDParticleReference] {
        if let particleB { return [particleA, particleB] }
        return [particleA]
    }

    public init(particleA: XPBDParticleReference,
                particleB: XPBDParticleReference? = nil,
                axisA: Vector3 = Vector3(1, 0, 0),
                axisB: Vector3 = Vector3(1, 0, 0),
                ratio: Scalar = 1.0,
                targetCoordinate: Scalar? = nil,
                compliance: Scalar = .zero,
                isEnabled: Bool = true) {
        let normalizedA = axisA.lengthSquared > Scalar.ulpOfOne
            ? axisA.normalized() : .zero
        let normalizedB = axisB.lengthSquared > Scalar.ulpOfOne
            ? axisB.normalized() : .zero
        let initialA = particleA.particle.map {
            Vector3.dot($0.position, normalizedA)
        } ?? .zero
        let initialB = particleB?.particle.map {
            Vector3.dot($0.position, normalizedB)
        } ?? .zero
        self.particleA = particleA
        self.particleB = particleB
        self.axisA = axisA
        self.axisB = axisB
        self.ratio = ratio
        self.targetCoordinate = targetCoordinate ?? initialA + ratio * initialB
        self.compliance = compliance
        self.isEnabled = isEnabled
        self.accumulatedMultiplier = .zero
    }

    public func resetAccumulatedMultipliers() {
        accumulatedMultiplier = .zero
    }

    public func projections() -> [XPBDConstraintProjection] {
        guard isEnabled,
              ratio.isFinite,
              targetCoordinate.isFinite,
              axisA.lengthSquared > Scalar.ulpOfOne,
              particleB == nil || axisB.lengthSquared > Scalar.ulpOfOne,
              let positionA = particleA.particle?.position
        else { return [] }

        let normalizedA = axisA.normalized()
        let normalizedB = axisB.normalized()
        var value = Vector3.dot(positionA, normalizedA) - targetCoordinate
        var gradients = [XPBDConstraintGradient(
            particle: particleA,
            gradient: normalizedA)]
        if let particleB,
           let positionB = particleB.particle?.position {
            value += ratio * Vector3.dot(positionB, normalizedB)
            gradients.append(XPBDConstraintGradient(
                particle: particleB,
                gradient: normalizedB * ratio))
        } else if particleB != nil {
            return []
        }

        return [XPBDConstraintProjection(
            multiplierIndex: 0,
            value: value,
            gradients: gradients,
            compliance: compliance,
            accumulatedMultiplier: accumulatedMultiplier)]
    }

    public func setAccumulatedMultiplier(_ multiplier: Scalar, at index: Int) {
        guard index == 0 else { return }
        accumulatedMultiplier = multiplier
    }
}

public enum XPBDJointMotion: Hashable, Sendable {
    case free
    case locked
    case limited(lower: Scalar, upper: Scalar)
}

/// Position constraint settings for one configurable-joint axis.
public struct XPBDJointAxis: Hashable, Sendable {
    public var motion: XPBDJointMotion
    public var compliance: Scalar

    public static let free = XPBDJointAxis()
    public static let locked = XPBDJointAxis(motion: .locked)

    public static func limited(_ lower: Scalar,
                               _ upper: Scalar,
                               compliance: Scalar = .zero) -> Self {
        Self(motion: .limited(lower: lower, upper: upper),
             compliance: compliance)
    }

    public init(motion: XPBDJointMotion = .free,
                compliance: Scalar = .zero) {
        self.motion = motion
        self.compliance = compliance
    }
}

private struct _XPBDProjectionParameters {
    let value: Scalar
    let lowerMultiplier: Scalar
    let upperMultiplier: Scalar
}

private let _xpbdAxes = [Vector3(1, 0, 0),
                         Vector3(0, 1, 0),
                         Vector3(0, 0, 1)]

private func _xpbdPairGradients(
    particleA: XPBDParticleReference,
    particleB: XPBDParticleReference?,
    axis: Vector3
) -> [XPBDConstraintGradient] {
    var gradients = [XPBDConstraintGradient(particle: particleA,
                                             gradient: -axis)]
    if let particleB {
        gradients.append(XPBDConstraintGradient(particle: particleB,
                                                gradient: axis))
    }
    return gradients
}

private func _xpbdSecondPosition(
    _ particle: XPBDParticleReference?,
    worldAnchor: Vector3
) -> Vector3? {
    if let particle { return particle.particle?.position }
    return worldAnchor
}

private func _xpbdProjectionParameters(
    _ settings: XPBDJointAxis,
    coordinate: Scalar,
    accumulatedMultiplier: Scalar
) -> _XPBDProjectionParameters? {
    guard coordinate.isFinite else { return nil }
    switch settings.motion {
    case .free:
        return nil
    case .locked:
        return _XPBDProjectionParameters(value: coordinate,
                                         lowerMultiplier: -.infinity,
                                         upperMultiplier: .infinity)
    case .limited(let rawLower, let rawUpper):
        guard rawLower.isFinite, rawUpper.isFinite else { return nil }
        let lower = Swift.min(rawLower, rawUpper)
        let upper = Swift.max(rawLower, rawUpper)
        // Keep the previously active side until its multiplier is released.
        // Another projection may enter the interval or cross the opposite side.
        if accumulatedMultiplier > .zero ||
            (accumulatedMultiplier == .zero && coordinate < lower) {
            return _XPBDProjectionParameters(value: coordinate - lower,
                                             lowerMultiplier: .zero,
                                             upperMultiplier: .infinity)
        }
        if accumulatedMultiplier < .zero ||
            (accumulatedMultiplier == .zero && coordinate > upper) {
            return _XPBDProjectionParameters(value: coordinate - upper,
                                             lowerMultiplier: -.infinity,
                                             upperMultiplier: .zero)
        }
        return nil
    }
}
