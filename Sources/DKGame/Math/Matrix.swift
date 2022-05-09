import Foundation

public struct Matrix2 {
    public var m11, m12: Scalar
    public var m21, m22: Scalar

    public static let identity = Matrix2(m11: 1.0, m12: 0.0,
                                         m21: 0.0, m22: 1.0)
}

public struct Matrix3 {
    public var m11, m12, m13: Scalar
    public var m21, m22, m23: Scalar
    public var m31, m32, m33: Scalar

    public static let identity = Matrix3(m11: 1.0, m12: 0.0, m13: 0.0,
                                         m21: 0.0, m22: 1.0, m23: 0.0,
                                         m31: 0.0, m32: 0.0, m33: 1.0)
}

public struct Matrix4 {
    public var m11, m12, m13, m14: Scalar
    public var m21, m22, m23, m24: Scalar
    public var m31, m32, m33, m34: Scalar
    public var m41, m42, m43, m44: Scalar

    public static let identity = Matrix4(m11: 1.0, m12: 0.0, m13: 0.0, m14: 0.0,
                                         m21: 0.0, m22: 1.0, m23: 0.0, m24: 0.0,
                                         m31: 0.0, m32: 0.0, m33: 1.0, m34: 0.0,
                                         m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0)
}
