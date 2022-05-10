import Foundation

public struct Vector2 {
    public var x : Scalar
    public var y : Scalar

    subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (value) {
            switch index {
            case 0: self.x = value
            case 1: self.y = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let zero = Vector2(0.0, 0.0)

    public init() {
        self = .zero
    }

    public init(_ x: Scalar, _ y: Scalar) {
        self.x = x
        self.y = y
    }

    public init(x: Scalar, y: Scalar) {
        self.init(x, y)
    }

    public var length: Scalar { sqrt(self.lengthSquared) }

    public var lengthSquared: Scalar { Self.dot(self, self) }

    public static func dot(_ v1: Vector2, _ v2: Vector2) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y
    }

    public func normalized() -> Vector2 {
        var x = self.x
        var y = self.y
        let lengthSq = x * x + y * y
        if lengthSq > 0.0 {
            let inv = 1.0 / sqrt(lengthSq)
            x *= inv
            y *= inv
        }
        return Vector2(x, y)
    }

    public mutating func normalize() {
        self = self.normalized()
    }

    public func transforming(_ mat: Matrix2) -> Vector2 {
        let x = self.x * mat.m11 + self.y * mat.m21
        let y = self.x * mat.m12 + self.y * mat.m22
        return Vector2(x, y)
    }

    public mutating func transform(_ mat: Matrix2) {
        self = self.transforming(mat)
    }

    public func transforming(_ mat: Matrix3) -> Vector2 {
        let x = self.x * mat.m11 + self.y * mat.m21 + mat.m31
        let y = self.x * mat.m12 + self.y * mat.m22 + mat.m32
        let w = 1.0 / (self.x * mat.m13 + self.y * mat.m23 + mat.m33)
        return Vector2(x * w, y * w)
    }

    public mutating func transform(_ mat: Matrix3) {
        self = self.transforming(mat)
    }
}

extension Vector2: Equatable {
    public static func == (lhs: Vector2, rhs: Vector2) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }
}

extension Vector2 {
    public var magnitudeSquared: Scalar {
        return Self.dot(self, self)
    }

    public mutating func scale(by rhs: Scalar) {
        self.x *= rhs
        self.y *= rhs
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs)
    }

    public static func *= (lhs: inout Self, rhs: Scalar) {
        lhs.x *= rhs
        lhs.y *= rhs
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs.x *= rhs.x
        lhs.y *= rhs.y
    }

    public static func * (lhs: Self, rhs: Matrix2) -> Self {
        return lhs.transforming(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Matrix2) {
        lhs.transform(rhs)
    }

    public static func * (lhs: Self, rhs: Matrix3) -> Self {
        return lhs.transforming(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Matrix3) {
        lhs.transform(rhs)
    }
}

extension Vector2: AdditiveArithmetic {
    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(rhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }
}
