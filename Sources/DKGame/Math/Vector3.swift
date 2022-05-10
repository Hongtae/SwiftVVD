import Foundation

public struct Vector3 {
    public var x : Scalar
    public var y : Scalar
    public var z : Scalar

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

    public static let zero = Vector3(0.0, 0.0, 0.0)

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

    public var length: Scalar { sqrt(self.lengthSquared) }

    public var lengthSquared: Scalar { Self.dot(self, self) }

    public static func dot(_ v1: Vector3, _ v2: Vector3) -> Scalar {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    }

    public static func cross(_ v1: Vector3, _ v2: Vector3) -> Vector3 {
        return Vector3(x: v1.y * v2.z - v1.z * v2.y,
                       y: v1.z * v2.x - v1.x * v2.z,
                       z: v1.x * v2.y - v1.y * v2.x)
    }

    public mutating func normalize() {
        let lengthSq = x * x + y * y + z * z
        if lengthSq > 0.0 {
            let inv = 1.0 / sqrt(lengthSq)
            self.x *= inv
            self.y *= inv
            self.z *= inv
        }
    }

    public func normalized() -> Vector3 {
        var v: Vector3 = self
        v.normalize()
        return v
    }
}
