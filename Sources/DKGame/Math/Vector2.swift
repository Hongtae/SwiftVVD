import Foundation

public struct Vector2: Vector, LinearTransformable, HomogeneousTransformable {
    public typealias LinearTransformMatrix = Matrix2
    public typealias HomogeneousTransformMatrix = Matrix3

    public var x : Scalar
    public var y : Scalar

    public static let zero = Vector2(0.0, 0.0)

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

    public static func dot(_ v1: Vector2, _ v2: Vector2) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y
    }

    public func transforming(_ mat: Matrix2) -> Vector2 {
        let x = self.x * mat.m11 + self.y * mat.m21
        let y = self.x * mat.m12 + self.y * mat.m22
        return Vector2(x, y)
    }

    public func transforming(_ mat: Matrix3) -> Vector2 {
        let x = self.x * mat.m11 + self.y * mat.m21 + mat.m31
        let y = self.x * mat.m12 + self.y * mat.m22 + mat.m32
        let w = 1.0 / (self.x * mat.m13 + self.y * mat.m23 + mat.m33)
        return Vector2(x * w, y * w)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(rhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y)
    }
}
