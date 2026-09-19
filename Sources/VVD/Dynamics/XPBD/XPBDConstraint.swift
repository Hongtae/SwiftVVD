//
//  File: XPBDConstraint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Type-erased constraint state owned by an `XPBDSimulator`.
/// Constraint projection requirements will be added with the solver slice.
public protocol XPBDConstraint: AnyObject {
    var isEnabled: Bool { get set }
}

public final class XPBDFixedJointConstraint: XPBDConstraint {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

public final class XPBDConfigurableJointConstraint: XPBDConstraint {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

public final class XPBDGearJointConstraint: XPBDConstraint {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}
