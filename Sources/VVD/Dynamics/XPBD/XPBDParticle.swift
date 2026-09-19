//
//  File: XPBDParticle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Per-particle state consumed by an XPBD solver.
public struct XPBDParticle: Hashable, Sendable {
    public var position: Vector3
    public var previousPosition: Vector3
    public var velocity: Vector3
    public var inverseMass: Scalar

    public var isPinned: Bool {
        inverseMass <= .zero
    }

    public init(position: Vector3 = .zero,
                previousPosition: Vector3? = nil,
                velocity: Vector3 = .zero,
                inverseMass: Scalar = 1.0) {
        self.position = position
        self.previousPosition = previousPosition ?? position
        self.velocity = velocity
        self.inverseMass = inverseMass
    }

    public init(position: Vector3,
                velocity: Vector3 = .zero,
                mass: Scalar) {
        self.init(position: position,
                  velocity: velocity,
                  inverseMass: mass > .zero ? Scalar(1) / mass : .zero)
    }
}

/// Particle storage owned by a cloth, rope, or soft body.
public protocol XPBDBody: AnyObject {
    var particles: [XPBDParticle] { get set }
}
