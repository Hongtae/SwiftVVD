//
//  File: ProjectionTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ProjectionTransform: Equatable, Sendable{
    public var m11: CGFloat
    public var m12: CGFloat
    public var m13: CGFloat
    public var m21: CGFloat
    public var m22: CGFloat
    public var m23: CGFloat
    public var m31: CGFloat
    public var m32: CGFloat
    public var m33: CGFloat

    public init() {
        (m11, m12, m13) = (1.0, 0.0, 0.0)
        (m21, m22, m23) = (0.0, 1.0, 0.0)
        (m31, m32, m33) = (0.0, 0.0, 1.0)
    }

    public init(_ m: CGAffineTransform) {
        (m11, m12, m13) = (m.a, m.b, 0.0)
        (m21, m22, m23) = (m.c, m.d, 0.0)
        (m31, m32, m33) = (m.tx, m.ty, 1.0)
    }

    public var isIdentity: Bool {
        return m11 == 1.0 && m12 == 0.0 && m13 == 0.0 &&
               m21 == 0.0 && m22 == 1.0 && m23 == 0.0 &&
               m31 == 0.0 && m32 == 0.0 && m33 == 1.0
    }

    public var isAffine: Bool {
        return m31 != 0.0 || m32 != 0.0
    }

    public mutating func invert() -> Bool {
        fatalError()
    }

    public func inverted() -> ProjectionTransform {
        fatalError()
    }

    public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
        fatalError()
    }
}
