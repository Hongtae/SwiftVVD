//
//  File: XPBDConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol XPBDConstraint {
}

public struct XPBDFixedJointConstraint: XPBDConstraint {
}

public struct XPBDConfigurableJointConstraint: XPBDConstraint {
}

public struct XPBDGearJointConstraint: XPBDConstraint {
}
