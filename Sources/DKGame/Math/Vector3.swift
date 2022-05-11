import Foundation

public struct Vector3: Vector, LinearTransformable, HomogeneousTransformable {
    public typealias LinearTransformMatrix = Matrix3
    public typealias HomogeneousTransformMatrix = Matrix4

    public var x : Scalar
    public var y : Scalar
    public var z : Scalar

    public static let zero = Vector3(0.0, 0.0, 0.0)

    subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
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
            case 2: self.z = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public init() {
        self = .zero
    }

    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Scalar, y: Scalar, z: Scalar) {
        self.init(x, y, z)
    }

    public static func dot(_ v1: Vector3, _ v2: Vector3) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    }

    public static func cross(_ v1: Vector3, _ v2: Vector3) -> Vector3 {
        return Vector3(x: v1.y * v2.z - v1.z * v2.y,
                       y: v1.z * v2.x - v1.x * v2.z,
                       z: v1.x * v2.y - v1.y * v2.x)
    }

    public func transforming(_ m: Matrix3) -> Self {
        let x = (self.x * m.m11) + (self.y * m.m21) + (self.z * m.m31)
        let y = (self.x * m.m12) + (self.y * m.m22) + (self.z * m.m32)
        let z = (self.x * m.m13) + (self.y * m.m23) + (self.z * m.m33)   
        return Self(x, y, z) 
    }

    public func transforming(_ m: Matrix4) -> Self {
        let x = (self.x * m.m11) + (self.y * m.m21) + (self.z * m.m31) + m.m41
        let y = (self.x * m.m12) + (self.y * m.m22) + (self.z * m.m32) + m.m42
        let z = (self.x * m.m13) + (self.y * m.m23) + (self.z * m.m33) + m.m43
        let w = 1.0 / ((self.x * m.m14) + (self.y * m.m24) + (self.z * m.m34) + m.m44)
        return Self(x * w, y * w, z * w)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y, -lhs.z)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(rhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z)
    }
}
