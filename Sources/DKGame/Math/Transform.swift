//
//  File: Transform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Transform: VectorTransformer, Interpolatable {
    public typealias Vector = Vector3
    
    public var orientation: Quaternion
    public var position: Vector3

    public static let identity: Self = .init(orientation: .identity, position: .zero)

    public var matrix3: Matrix3 { self.orientation.matrix3 }
    public var matrix4: Matrix4 {
        let m = self.orientation.matrix3
        return Matrix4(m.m11, m.m12, m.m13, 0.0,
                       m.m21, m.m22, m.m23, 0.0,
                       m.m31, m.m32, m.m33, 0.0,
                       position.x, position.y, position.z, 1.0)
    }

    public init(orientation: Quaternion = .identity, position: Vector3 = .zero) {
        self.orientation = orientation
        self.position = position
    }

    public init(matrix: Matrix3, position: Vector3 = .zero) {
        self.orientation = LinearTransform3(matrix).rotation
        self.position = position
    }

    public func inverted() -> Self {
        let r = orientation.conjugate
        let p = -position * r
        return Self(orientation: r, position: p)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public static func interpolate(_ t1: Self, _ t2: Self, t: Scalar) -> Self {
        return Self(orientation: Quaternion.slerp(t1.orientation, t2.orientation, t:t),
                    position: t1.position + ((t2.position - t1.position) * t))
    }

    public static func == (lhs:Self, rhs:Self) -> Bool {
        return lhs.orientation == rhs.orientation &&
               lhs.position == rhs.position
    }

    public static func * (v: Vector3, t: Self) -> Vector3 {
        return v * t.orientation + t.position
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(orientation: lhs.orientation * rhs.orientation,
                    position: lhs.position * rhs.orientation + lhs.position)
    }

    public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
}
