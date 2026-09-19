//
//  File: PhysicsMaterial.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Surface properties consumed by a rigid-body contact solver.
public struct PhysicsMaterial: Hashable, Sendable {
    public var friction: Scalar
    public var restitution: Scalar

    public static let `default` = PhysicsMaterial()

    public init(friction: Scalar = 0.5, restitution: Scalar = 0.0) {
        self.friction = friction
        self.restitution = restitution
    }
}
