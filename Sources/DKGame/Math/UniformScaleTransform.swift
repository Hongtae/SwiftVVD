//
//  File: UniformScaleTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct UniformScaleTransform: Hashable {
    public typealias Vector = Vector3

    public var scale: Scalar
    public var orientation: Quaternion
    public var position: Vector3

    public static let identity: Self = .init(scale: 1.0, orientation: .identity, position: .zero)

    public var matrix3: Matrix3 { orientation.matrix3 * scale }
    public var matrix4: Matrix4 {
        let m = self.matrix3
        return Matrix4(m.m11, m.m12, m.m13, 0.0,
                       m.m21, m.m22, m.m23, 0.0,
                       m.m31, m.m32, m.m33, 0.0,
                       position.x, position.y, position.z, 1.0)
    }

    public init(scale: Scalar = 1.0, orientation: Quaternion = .identity, position: Vector3 = .zero) {
        self.scale = scale
        self.orientation = orientation
        self.position = position
    }

    public func inverted() -> Self {
        let s = 1.0 / self.scale
        let r = orientation.conjugated()
        let p = (-position * scale).applying(r)
        return Self(scale: s, orientation: r, position: p)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public static func interpolate(_ t1: Self, _ t2: Self, t: some BinaryFloatingPoint) -> Self {
        let t = Scalar(t)
        return Self(scale: t1.scale + ((t2.scale - t1.scale) * t),
                    orientation: Quaternion.slerp(t1.orientation, t2.orientation, t:t),
                    position: t1.position + ((t2.position - t1.position) * t))
    }   

    public func concatenating(_ t: Self) -> Self {
        Self(scale: self.scale * t.scale,
             orientation: self.orientation.concatenating(t.orientation),
             position: self.position.applying(t.matrix3) + t.position)
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }
}

public extension Vector3 {
    func applying(_ t: UniformScaleTransform) -> Vector3 {
        (self * t.scale).applying(t.orientation) + t.position
    }

    mutating func apply(_ t: UniformScaleTransform) {
        self = self.applying(t)
    }
}
