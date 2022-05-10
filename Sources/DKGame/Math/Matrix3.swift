import Foundation

public struct Matrix3 {
    public var m11, m12, m13: Scalar
    public var m21, m22, m23: Scalar
    public var m31, m32, m33: Scalar

    public var row1: Vector3 {
        get { Vector3(x: m11, y: m12, z: m13) }
        set (vector) { 
            m11 = vector.x
            m12 = vector.y
            m13 = vector.z
        }
    }

    public var row2: Vector3 {
        get { Vector3(x: m21, y: m22, z: m23) }
        set (vector) { 
            m21 = vector.x
            m22 = vector.y
            m23 = vector.z
        }
    }

    public var row3: Vector3 {
        get { Vector3(x: m31, y: m32, z: m33) }
        set (vector) { 
            m31 = vector.x
            m32 = vector.y
            m33 = vector.z
        }
    }

    public var column1: Vector3 {
        get { Vector3(x: m11, y: m21, z: m31) }
        set (vector) { 
            m11 = vector.x
            m21 = vector.y
            m31 = vector.z
        }
    }

    public var column2: Vector3 {
        get { Vector3(x: m12, y: m22, z: m32) }
        set (vector) { 
            m12 = vector.x
            m22 = vector.y
            m32 = vector.z
        }
    }

    public var column3: Vector3 {
        get { Vector3(x: m13, y: m23, z: m33) }
        set (vector) { 
            m13 = vector.x
            m23 = vector.y
            m33 = vector.z
        }
    }

    subscript(row: Int) -> Vector3 {
        get {
            switch row {
            case 0: return self.row1
            case 1: return self.row2
            case 2: return self.row3
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (vector) {
            switch row {
            case 0: self.row1 = vector
            case 1: self.row2 = vector
            case 2: self.row3 = vector
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    subscript(row: Int, column: Int) -> Scalar {
        get {
            switch (row, column) {
            case (0, 0): return m11
            case (0, 1): return m12
            case (0, 2): return m13
            case (1, 0): return m21
            case (1, 1): return m22
            case (1, 2): return m23
            case (2, 0): return m31
            case (2, 1): return m32
            case (2, 2): return m33
            default:
                assertionFailure("Index out of range")
                break
            }
            return 0.0
        }
        set (value) {
            switch (row, column) {
            case (0, 0): m11 = value
            case (0, 1): m12 = value
            case (0, 2): m13 = value
            case (1, 0): m21 = value
            case (1, 1): m22 = value
            case (1, 2): m23 = value
            case (2, 0): m31 = value
            case (2, 1): m32 = value
            case (2, 2): m33 = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let identity = Matrix3(1.0, 0.0, 0.0,
                                         0.0, 1.0, 0.0,
                                         0.0, 0.0, 1.0)

    public init() {
        self = .identity
    }

    public init(_ m11: Scalar, _ m12: Scalar, _ m13: Scalar,
                _ m21: Scalar, _ m22: Scalar, _ m23: Scalar,
                _ m31: Scalar, _ m32: Scalar, _ m33: Scalar) {
        self.m11 = m11
        self.m12 = m12
        self.m13 = m13
        self.m21 = m21
        self.m22 = m22
        self.m23 = m23
        self.m31 = m31
        self.m32 = m32
        self.m33 = m33
    }

    public init(m11: Scalar, m12: Scalar, m13: Scalar,
                m21: Scalar, m22: Scalar, m23: Scalar,
                m31: Scalar, m32: Scalar, m33: Scalar) {
        self.init(m11, m12, m13, m21, m22, m23, m31, m32, m33)
    }

    public var determinant: Scalar {
       	return m11 * m22 * m33 + m12 * m23 * m31 +
               m13 * m21 * m32 - m11 * m23 * m32 -
               m12 * m21 * m33 - m13 * m22 * m31
    }
}
