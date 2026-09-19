//
//  File: TimeOfImpact.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Primitive-pair sweep geometry in the moving primitive's start-local space.
///
/// Primitive A moves by the query translation while primitive B remains fixed.
/// `fraction` is the first impact along that translation in the closed interval
/// zero through one. The normal points from A toward B at impact.
public struct TimeOfImpact: Hashable, Sendable {
    public let fraction: Scalar
    public let pointOnA: Vector3
    public let pointOnB: Vector3
    public let normal: Vector3

    public init(fraction: Scalar,
                pointOnA: Vector3,
                pointOnB: Vector3,
                normal: Vector3) {
        self.fraction = fraction
        self.pointOnA = pointOnA
        self.pointOnB = pointOnB
        self.normal = normal
    }

    public var isValid: Bool {
        fraction.isFinite && (Scalar.zero...Scalar(1)).contains(fraction) &&
        pointOnA.isFinite && pointOnB.isFinite && normal.isFinite &&
        normal.lengthSquared > .ulpOfOne
    }
}

private extension Vector3 {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
