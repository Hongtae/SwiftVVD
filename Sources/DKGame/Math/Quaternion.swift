import Foundation

public struct Quaternion {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    public var w: Scalar

    subscript(index: Int) -> Scalar {
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

    public init(axis: Vector3, angle: Scalar) {
        self.x = 0.0
        self.y = 0.0
        self.z = 0.0
        self.w = 1.0
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

    public mutating func normalize() {
        let n = x * x + y * y + z * z + w * w
        if n > 0.0 {
            let inv = 1.0 / n
            self.x *= -inv
            self.y *= -inv
            self.z *= -inv
            self.w *= inv
        }
    }

    public func normalized() -> Quaternion {
        var q: Quaternion = self
        q.normalize()
        return q
    }

    public var length: Scalar { sqrt(x * x + y * y + z * z + w * w) }

    public var lengthSq: Scalar { x * x + y * y + z * z + w * w }

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
}
