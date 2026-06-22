//
//  File: RigidBodyConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol RigidBodyConstraint {
}

public struct FixedJointConstraint: RigidBodyConstraint {
}

public struct ConfigurableJointConstraint: RigidBodyConstraint {
}

public struct GearJointConstraint: RigidBodyConstraint {
}
