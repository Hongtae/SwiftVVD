import Foundation

public struct Matrix2: Matrix {
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

    public subscript(row: Int) -> Vector2 {
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

    public subscript(row: Int, column: Int) -> Scalar {
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

    public init(row1: Vector2, row2: Vector2) {
        self.init(row1.x, row1.y, row2.x, row2.y)
    }

    public var determinant: Scalar { return m11 * m22 - m12 * m21 }
    
    public var isDiagonal: Bool { m12 == 0.0 && m21 == 0.0 }

    public func inverted() -> Self? {
        let d = self.determinant
        if d.isZero { return nil }
        let inv = 1.0 / d
        let m11 =  self.m22 * inv
        let m12 = -self.m12 * inv
        let m21 = -self.m21 * inv
        let m22 =  self.m11 * inv
        return Matrix2(m11, m12, m21, m22)
    }

    public func transposed() -> Self {
        return Matrix2(row1: self.column1, row2: self.column2)
    }

    public static func == (_ lhs:Self, _ rhs:Self) -> Bool {
        return lhs.row1 == rhs.row1 && lhs.row2 == rhs.row2
    }

    public static func + (_ lhs:Self, _ rhs:Self) -> Self {
        return Matrix2(row1: lhs.row1 + rhs.row1, row2: lhs.row2 + rhs.row2)
    }

    public static func - (_ lhs:Self, _ rhs:Self) -> Self {
        return Matrix2(row1: lhs.row1 - rhs.row1, row2: lhs.row2 - rhs.row2)
    }

    public static func * (_ lhs:Self, _ rhs:Self) -> Self {
        let row1 = lhs.row1,    row2 = lhs.row2
        let col1 = rhs.column1, col2 = rhs.column2

        return Matrix2(Vector2.dot(row1, col1), Vector2.dot(row1, col2),
                       Vector2.dot(row2, col1), Vector2.dot(row2, col2))
    }

    public static func * (_ lhs:Self, _ rhs:Self.Scalar) -> Self {
        return Matrix2(row1: lhs.row1 * rhs, row2: lhs.row2 * rhs)
    }
}
