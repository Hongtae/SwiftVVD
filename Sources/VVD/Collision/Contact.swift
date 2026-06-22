//
//  File: Contact.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Identifies the geometric features that produced a contact point.
public struct ContactFeatureID: Hashable, Sendable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }
}

/// A single contact point between two collision primitives.
///
/// Points and normals are expressed in the first primitive's local/query space.
/// `normal` points from the first primitive toward the second primitive, and
/// `penetrationDepth` is positive when the primitives overlap.
public struct Contact: Hashable, Sendable {
    public let pointOnA: Vector3
    public let pointOnB: Vector3
    public let normal: Vector3
    public let penetrationDepth: Scalar
    public let featureID: ContactFeatureID

    public init(pointOnA: Vector3,
                pointOnB: Vector3,
                normal: Vector3,
                penetrationDepth: Scalar,
                featureID: ContactFeatureID = ContactFeatureID()) {
        self.pointOnA = pointOnA
        self.pointOnB = pointOnB
        self.normal = normal
        self.penetrationDepth = penetrationDepth
        self.featureID = featureID
    }
}
