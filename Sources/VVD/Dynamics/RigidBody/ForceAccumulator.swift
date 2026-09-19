//
//  File: ForceAccumulator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Forces collected during one rigid-body simulation step.
public struct ForceAccumulator: Hashable, Sendable {
    public private(set) var force: Vector3
    public private(set) var torque: Vector3

    public init(force: Vector3 = .zero, torque: Vector3 = .zero) {
        self.force = force
        self.torque = torque
    }

    public mutating func addForce(_ force: Vector3) {
        self.force += force
    }

    public mutating func addTorque(_ torque: Vector3) {
        self.torque += torque
    }

    public mutating func addForce(_ force: Vector3, at offset: Vector3) {
        self.force += force
        self.torque += Vector3.cross(offset, force)
    }

    public mutating func removeAll() {
        force = .zero
        torque = .zero
    }
}
