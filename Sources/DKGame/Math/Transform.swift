//
//  File: Transform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Transform: Hashable {
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
        let r = orientation.conjugated()
        let p = (-position).applying(r)
        return Self(orientation: r, position: p)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func concatenating(_ t: Self) -> Self {
        return Self(orientation: self.orientation.concatenating(t.orientation),
                    position: self.position.applying(t.orientation) + t.position)
    }

    public mutating func concatenate(_ t: Self) {
        self = self.concatenating(t)
    }

    public static func interpolate(_ t1: Self, _ t2: Self, t: some BinaryFloatingPoint) -> Self {
        return Self(orientation: Quaternion.slerp(t1.orientation, t2.orientation, t:t),
                    position: t1.position + ((t2.position - t1.position) * t))
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.concatenating(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }
}

public extension Vector3 {
    func applying(_ t: Transform) -> Vector3 {
        self.applying(t.orientation) + t.position
    }

    mutating func apply(_ t: Transform) {
        self = self.applying(t)
    }
}
