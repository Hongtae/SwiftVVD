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
        let x = Self.dot(self, m.column1)
        let y = Self.dot(self, m.column2)
        let z = Self.dot(self, m.column3)
        return Self(x, y, z) 
    }

    public func transforming(_ m: Matrix4) -> Self {
        let v = Vector4(self.x, self.y, self.z, 1.0).transforming(m)
        let w = 1.0 / v.w
        return Vector3(v.x * w, v.y * w, v.z * w)
    }

    public func transforming(_ q: Quaternion) -> Self {
        return self.rotated(by: q)
    }

    public mutating func transform(_ q: Quaternion) {
        self.rotate(by: q)
    }

    public func rotatedBy(x radian: Scalar) -> Vector3 {
        if radian.isZero  { return self }
        let c = cos(radian)
        let s = sin(radian)
        
        let y = self.y * c - self.z * s
        let z = self.y * s + self.z * c
        return Vector3(self.x, y, z)
    }

    public func rotatedBy(y radian: Scalar) -> Vector3 {
        if radian.isZero { return self }
        let c = cos(radian)
        let s = sin(-radian)

        let x = self.x * c - self.z * s
        let z = self.x * s + self.z * c
        return Vector3(x, self.y, z)
    }

    public func rotatedBy(z radian: Scalar) -> Vector3 {
        if radian.isZero { return self }
        let c = cos(radian)
        let s = sin(radian)

        let x = self.x * c - self.y * s
        let y = self.x * s + self.y * c
        return Vector3(x, y, self.z)
    }

    public func rotatedBy(angle: Scalar, axis: Vector3) -> Vector3 {
        if angle.isZero { return self }
        return self.rotated(by: Quaternion(angle: angle, axis: axis))
    }

    public func rotated(by q: Quaternion) -> Vector3 {
        let vec = Vector3(q.x, q.y, q.z)
        var uv = Self.cross(vec, self)
        var uuv = Self.cross(vec, uv)
        uv *= (2.0 * q.w)
        uuv *= 2.0
        return self + uv + uuv
    }

    public mutating func rotateBy(x radian: Scalar) {
        self = self.rotatedBy(x: radian)
    }

    public mutating func rotateBy(y radian: Scalar) {
        self = self.rotatedBy(y: radian)
    }

    public mutating func rotateBy(z radian: Scalar) {
        self = self.rotatedBy(z: radian)
    }

    public mutating func rotateBy(angle: Scalar, axis: Vector3) {
        self = self.rotatedBy(angle: angle, axis: axis)
    }

    public mutating func rotate(by q: Quaternion) {
        self = self.rotated(by: q)
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

    public static func * (lhs: Self, rhs: Quaternion) -> Vector3 {
        return lhs.transforming(rhs)
    }

    public static func *= (lhs: inout Self, rhs: Quaternion) {
        lhs.transform(rhs)
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z))
    }
}
