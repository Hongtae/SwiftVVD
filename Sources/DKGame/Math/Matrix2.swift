import Foundation

public struct Matrix2 {
    public var m11, m12: Scalar
    public var m21, m22: Scalar

    public var row1: Vector2 {
        get { Vector2(x: m11, y: m12) }
        set (vector) { 
            m11 = vector.x
            m12 = vector.y
        }
    }

    public var row2: Vector2 {
        get { Vector2(x: m21, y: m22) }
        set (vector) { 
            m21 = vector.x
            m22 = vector.y
        }
    }

    public var column1: Vector2 {
        get { Vector2(x: m11, y: m21) }
        set (vector) { 
            m11 = vector.x
            m21 = vector.y
        }
    }

    public var column2: Vector2 {
        get { Vector2(x: m12, y: m22) }
        set (vector) { 
            m12 = vector.x
            m22 = vector.y
        }
    }

    subscript(row: Int) -> Vector2 {
        get {
            switch row {
            case 0: return self.row1
            case 1: return self.row2
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
            case (1, 0): return m21
            case (1, 1): return m22
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
            case (1, 0): m21 = value
            case (1, 1): m22 = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let identity = Matrix2(1.0, 0.0, 0.0, 1.0)

    public init() {
        self = .identity
    }

    public init(_ m11: Scalar, _ m12: Scalar, _ m21: Scalar, _ m22: Scalar) {
        self.m11 = m11
        self.m12 = m12
        self.m21 = m21
        self.m22 = m22
    }

    public init(m11: Scalar, m12: Scalar, m21: Scalar, m22: Scalar) {
        self.init(m11, m12, m21, m22)
    }

    public var determinant: Scalar { return m11 * m22 - m12 * m21 }
}
