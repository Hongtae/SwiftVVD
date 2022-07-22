//
//  File: Transform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Transform {
    associatedtype Vector

    static var identity: Self { get }

    static func * (_:Self.Vector, _:Self) -> Self.Vector
    static func *= (_:inout Self.Vector, _:Self)
    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool
}

public extension Transform {
    static func *= (lhs:inout Self.Vector, rhs:Self)    { lhs = lhs * rhs }
    static func != (lhs:Self, rhs: Self) -> Bool        { !(lhs == rhs) }
}

public protocol Interpolatable {
    static func interpolate(_:Self, _:Self, t: Scalar) -> Self
}

public struct TransformUnit: Transform, Interpolatable {
    public typealias Vector = Vector3

    public var scale: Vector3
    public var rotation: Quaternion
    public var translation: Vector3

    public var matrix3: Matrix3 {
        var mat3 = self.rotation.matrix3

        mat3.m11 *= scale.x
        mat3.m12 *= scale.x
        mat3.m13 *= scale.x

        mat3.m21 *= scale.y
        mat3.m22 *= scale.y
        mat3.m23 *= scale.y

        mat3.m31 *= scale.z
        mat3.m32 *= scale.z
        mat3.m33 *= scale.z

        return mat3
    }

    public var matrix4: Matrix4 {
        let mat3 = self.matrix3
        return Matrix4(
            mat3.m11, mat3.m12, mat3.m13, 0.0, 
            mat3.m21, mat3.m22, mat3.m23, 0.0,
            mat3.m31, mat3.m32, mat3.m33, 0.0,
            translation.x, translation.y, translation.z, 1.0)
    }

    public static let identity: Self = .init(scale: Vector3(1, 1, 1), rotation: .identity, translation: .zero)

    public init(scale: Vector3, rotation: Quaternion, translation: Vector3) {
        self.scale = scale
        self.rotation = rotation
        self.translation = translation
    }

    public init() {
        self.init(scale: Vector3(1, 1, 1), rotation: .identity, translation: .zero)
    }

    public static func interpolate(_ t1: Self, _ t2: Self, t: Scalar) -> Self {
        let s = t1.scale + ((t2.scale - t1.scale) * t)
        let r = Quaternion.slerp(t1.rotation, t2.rotation, t: t)
        let t = t1.translation + ((t2.translation - t1.translation) * t)
        return Self(scale: s, rotation: r, translation: t)
    }

    public static func * (v: Vector3, t: Self) -> Vector3 {
        return (v * t.scale) * t.rotation + t.translation
    }

    public static func == (lhs:Self, rhs:Self) -> Bool {
        return lhs.scale == rhs.scale &&
               lhs.rotation == rhs.rotation &&
               lhs.translation == rhs.translation
    }
}
