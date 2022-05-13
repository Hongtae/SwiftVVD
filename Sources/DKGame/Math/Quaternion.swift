import Foundation

public struct Quaternion: Vector {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    public var w: Scalar

    public subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
            case 3: return self.w
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
            case 3: self.w = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let zero = Quaternion(0.0, 0.0, 0.0, 0.0)
    public static let identity = Quaternion(0.0, 0.0, 0.0, 1.0)

    public init() {
        self = .identity
    }

    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar, _ w: Scalar) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(x: Scalar, y: Scalar, z: Scalar, w: Scalar) {
        self.init(x, y, z, w)
    }

    public init(angle: Scalar, axis: Vector3) {
        self.init(0, 0, 0, 1)
        if axis.length > 0.0 {
            let u = axis.normalized()
            let a = angle * 0.5
            let sinR = sin(a)

            self.x = sinR * u.x
            self.y = sinR * u.y
            self.z = sinR * u.z
            self.w = cos(a)
        }
    }

    public init(pitch: Scalar, yaw: Scalar, roll: Scalar) {
        let p = pitch * 0.5
        let y = yaw * 0.5
        let r = roll * 0.5

        let sinP = sin(p)
        let cosP = cos(p)
        let sinY = sin(y)
        let cosY = cos(y)
        let sinR = sin(r)
        let cosR = cos(r)

        self.x = cosR * sinP * cosY + sinR * cosP * sinY
        self.y = cosR * cosP * sinY - sinR * sinP * cosY
        self.z = sinR * cosP * cosY - cosR * sinP * sinY
        self.w = cosR * cosP * cosY + sinR * sinP * sinY

        self.normalize()
    }

    public init(from: Vector3, to: Vector3, t: Scalar) {
        self.init(0, 0, 0, 1)
        let len1 = from.length
        let len2 = to.length
        if len1 > 0.0 && len2 > 0.0 {
            let axis = Vector3.cross(from, to)
            let angle = acos(Vector3.dot(from.normalized(), to.normalized())) * t

            self.init(angle: angle, axis: axis)
        }
    }

    public init(_ vector: Vector4) {
        self.init(vector.x, vector.y, vector.z, vector.w)
    }

    public var roll: Scalar { atan2(2 * (x * y + w * z), w * w + x * x - y * y - z * z) }

    public var pitch: Scalar { atan2(2 * (y * z + w * x), w * w - x * x - y * y + z * z) }

    public var yaw: Scalar { asin(-2 * (x * z - w * y)) }

    public var angle: Scalar {
        let lengthSq = x * x + y * y + z * z + w * w
        if lengthSq > 0.0 && abs(w) < 1.0 {
            return 2.0 * acos(w)
        }
        return 0.0
    }

    public var axis: Vector3 {
        let lengthSq = x * x + y * y + z * z + w * w
        if lengthSq > 0.0 {
            let inv = 1.0 / sqrt(lengthSq)
            return Vector3(x: x * inv, y: y * inv, z: z * inv)
        }
        return Vector3(x: 1.0, y: 0.0, z: 0.0)
    }

    public var conjugate: Self { Self(-x, -y, -z, w) }

    public var vector4: Vector4 { Vector4(x, y, z, w) }

    public var matrix3: Matrix3 {
        var mat = Matrix3.identity
        mat.m11 = 1.0 - 2.0 * (y * y + z * z)
        mat.m12 = 2.0 * (x * y + z * w)
        mat.m13 = 2.0 * (x * z - y * w)

        mat.m21 = 2.0 * (x * y - z * w)
        mat.m22 = 1.0 - 2.0 * (x * x + z * z)
        mat.m23 = 2.0 * (y * z + x * w)

        mat.m31 = 2.0 * (x * z + y * w)
        mat.m32 = 2.0 * (y * z - x * w)
        mat.m33 = 1.0 - 2.0 * (x * x + y * y)
        return mat
    }

    public var matrix4: Matrix4 {
        var mat = Matrix4.identity
	    mat.m11 = 1.0 - 2.0 * (y * y + z * z)
	    mat.m12 = 2.0 * (x * y + z * w)
	    mat.m13 = 2.0 * (x * z - y * w)

	    mat.m21 = 2.0 * (x * y - z * w)
	    mat.m22 = 1.0 - 2.0 * (x * x + z * z)
	    mat.m23 = 2.0 * (y * z + x * w)

	    mat.m31 = 2.0 * (x * z + y * w)
	    mat.m32 = 2.0 * (y * z - x * w)
	    mat.m33 = 1.0 - 2.0 * (x * x + y * y)
        return mat
    }

    public static func dot(_ q1: Quaternion, _ q2: Quaternion) -> Scalar {
        return q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.w == rhs.w
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        return Self(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z, lhs.w + rhs.w)
    }

    public static prefix func - (lhs: Self) -> Self {
        return Self(-lhs.x, -lhs.y, -lhs.z, -lhs.w)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return Self(rhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z, lhs.w - rhs.w)
    }

    public static func * (lhs: Self, rhs: Scalar) -> Self {
        return Self(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs, lhs.w * rhs)
    }

    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
		let x = rhs.w * lhs.x + rhs.x * lhs.w + rhs.y * lhs.z - rhs.z * lhs.y
		let y = rhs.w * lhs.y + rhs.y * lhs.w + rhs.z * lhs.x - rhs.x * lhs.z
		let z = rhs.w * lhs.z + rhs.z * lhs.w + rhs.x * lhs.y - rhs.y * lhs.x
		let w = rhs.w * lhs.w - rhs.x * lhs.x - rhs.y * lhs.y - rhs.z * lhs.z
        return Quaternion(x, y, z, w)
    }

    public static func slerp(_ q1: Quaternion, _ q2: Quaternion, t: Scalar) -> Quaternion {
        var cosHalfTheta = Self.dot(q1, q2)
        let flip = cosHalfTheta < 0.0
        if flip { cosHalfTheta = -cosHalfTheta }

        if cosHalfTheta >= 1.0 { return q1 }    // q1 = q2 or q1 = -q2

        let halfTheta = acos(cosHalfTheta)
        let oneOverSinHalfTheta = 1.0 / sin(halfTheta)

        let t2 = 1.0 - t

        let ratio1 = sin(halfTheta * t2) * oneOverSinHalfTheta
        var ratio2 = sin(halfTheta * t) * oneOverSinHalfTheta

        if flip { ratio2 = -ratio2 }

        return q1 * ratio1 + q2 * ratio2
    }

    public static func interpolate(_ q1: Quaternion, _ q2: Quaternion, _ t: Scalar) -> Quaternion {
        return slerp(q1, q2, t: t)
    }

    public func inverted() -> Quaternion? {
        let n = self.lengthSquared
        if n > 0.0 {
            let inv = 1.0 / n
            let x = self.x * -inv
            let y = self.y * -inv
            let z = self.z * -inv
            let w = self.w * inv
            return Quaternion(x, y, z, w)
        }
        return nil
    }

    public mutating func invert() {
        self = self.inverted() ?? self
    }

    public static func minimum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z), min(lhs.w, rhs.w))
    }

    public static func maximum(_ lhs: Self, _ rhs: Self) -> Self {
        return Self(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z), max(lhs.w, rhs.w))
    }
}
