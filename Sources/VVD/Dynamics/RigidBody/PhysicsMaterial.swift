//
//  File: PhysicsMaterial.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Rule used to combine one material coefficient across a contact pair.
///
/// When two materials request different rules, the case with the higher raw
/// value takes precedence. This makes the resolution symmetric and gives
/// `maximum` the strongest override.
public enum PhysicsMaterialCombineMode: Int, Hashable, Sendable, CaseIterable {
    case average
    case minimum
    case multiply
    case maximum
}

/// Surface properties consumed by a rigid-body contact solver.
public struct PhysicsMaterial: Hashable, Sendable {
    public var friction: Scalar {
        didSet { friction = Self.sanitizedFriction(friction) }
    }
    public var restitution: Scalar {
        didSet { restitution = Self.sanitizedRestitution(restitution) }
    }
    public var frictionCombineMode: PhysicsMaterialCombineMode
    public var restitutionCombineMode: PhysicsMaterialCombineMode

    public static let `default` = PhysicsMaterial()

    public init(
        friction: Scalar = 0.5,
        restitution: Scalar = 0.0,
        frictionCombineMode: PhysicsMaterialCombineMode = .average,
        restitutionCombineMode: PhysicsMaterialCombineMode = .average
    ) {
        self.friction = Self.sanitizedFriction(friction)
        self.restitution = Self.sanitizedRestitution(restitution)
        self.frictionCombineMode = frictionCombineMode
        self.restitutionCombineMode = restitutionCombineMode
    }

    /// Resolves both coefficients symmetrically for a contact pair.
    public func combined(with other: PhysicsMaterial) -> PhysicsMaterial {
        let frictionMode = Self.resolvedMode(frictionCombineMode,
                                             other.frictionCombineMode)
        let restitutionMode = Self.resolvedMode(restitutionCombineMode,
                                                other.restitutionCombineMode)
        return PhysicsMaterial(
            friction: Self.combine(friction, other.friction,
                                   mode: frictionMode),
            restitution: Self.combine(restitution, other.restitution,
                                      mode: restitutionMode),
            frictionCombineMode: frictionMode,
            restitutionCombineMode: restitutionMode)
    }

    private static func resolvedMode(
        _ a: PhysicsMaterialCombineMode,
        _ b: PhysicsMaterialCombineMode
    ) -> PhysicsMaterialCombineMode {
        a.rawValue >= b.rawValue ? a : b
    }

    private static func combine(
        _ a: Scalar,
        _ b: Scalar,
        mode: PhysicsMaterialCombineMode
    ) -> Scalar {
        switch mode {
        case .average: (a + b) * Scalar(0.5)
        case .minimum: Swift.min(a, b)
        case .multiply: a * b
        case .maximum: Swift.max(a, b)
        }
    }

    private static func sanitizedFriction(_ value: Scalar) -> Scalar {
        guard value.isFinite else { return .zero }
        return Swift.max(value, .zero)
    }

    private static func sanitizedRestitution(_ value: Scalar) -> Scalar {
        guard value.isFinite else { return .zero }
        return value.clamp(min: .zero, max: Scalar(1))
    }
}
