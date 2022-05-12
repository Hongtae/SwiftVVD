import Foundation

public struct LinearTransform3: Transform {
    public typealias Vector = Vector3

    public var matrix3: Matrix3

    public static let identity: LinearTransform3 = .init(Matrix3.identity)

    public var rotation: Quaternion {
        var x = sqrt(max(0.0, 1 + matrix3.m11 - matrix3.m22 - matrix3.m33)) * 0.5
        var y = sqrt(max(0.0, 1 - matrix3.m11 + matrix3.m22 - matrix3.m33)) * 0.5
        var z = sqrt(max(0.0, 1 - matrix3.m11 - matrix3.m22 + matrix3.m33)) * 0.5
        let w = sqrt(max(0.0, 1 + matrix3.m11 + matrix3.m22 + matrix3.m33)) * 0.5
        x = copysign(x, matrix3.m23 - matrix3.m32);
        y = copysign(y, matrix3.m31 - matrix3.m13);
        z = copysign(z, matrix3.m12 - matrix3.m21);

	    return Quaternion(x, y, z, w)
    }

    public init() {
        self.matrix3 = .identity
    }

    public init(_ q: Quaternion) {
        self.matrix3 = q.matrix3
    }

    public init(_ m: Matrix3) {
        self.matrix3 = m
    }
 
    public init(scaleX: Scalar, scaleY: Scalar, scaleZ: Scalar) {
        self.matrix3 = .init(scaleX, 0.0, 0.0,
                             0.0, scaleY, 0.0,
                             0.0, 0.0, scaleZ)
    }

    public init(left: Vector3, up: Vector3, forward: Vector3) {
        self.matrix3 = .init(row1: left, row2: up, row3: forward)
    }

    public func decompose(scale: inout Vector3, rotation: inout Quaternion) -> Bool {
        let s = Vector3(
            Vector3(matrix3.m11, matrix3.m12, matrix3.m13).length,
            Vector3(matrix3.m21, matrix3.m22, matrix3.m23).length,
            Vector3(matrix3.m31, matrix3.m32, matrix3.m33).length)

        if s.x.isZero || s.y.isZero || s.z.isZero { return false }

        var normalized = Matrix3()
        normalized.m11 = matrix3.m11 / scale.x
        normalized.m12 = matrix3.m12 / scale.x
        normalized.m13 = matrix3.m13 / scale.x
        normalized.m21 = matrix3.m21 / scale.y
        normalized.m22 = matrix3.m22 / scale.y
        normalized.m23 = matrix3.m23 / scale.y
        normalized.m31 = matrix3.m31 / scale.z
        normalized.m32 = matrix3.m32 / scale.z
        normalized.m33 = matrix3.m33 / scale.z
        
        scale = s
        rotation = LinearTransform3(normalized).rotation
        return true
    }

    public func inversed() -> Self {
        return Self(self.matrix3.inversed())
    }

    public mutating func inverse() { self = self.inversed() }

    public func multiplied(by t: Self) -> Self {
        return Self(self.matrix3 * t.matrix3)
    }

    public mutating func multiply(by t: Self) {
        self = self.multiplied(by: t)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.matrix3 == rhs.matrix3
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.multiplied(by: rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func * (lhs: Vector3, rhs: Self) -> Vector3 {
        return lhs * rhs.matrix3
    }

    public static func *= (lhs: inout Vector3, rhs: Self) {
        lhs = lhs * rhs
    }
}
