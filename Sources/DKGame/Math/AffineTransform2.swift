import Foundation

public struct AffineTransform2: Transform {
    public typealias Vector = Vector2

    public var matrix2: Matrix2
    public var translation: Vector2

    public var matrix3: Matrix3 {
        get {
            Matrix3(matrix2.m11, matrix2.m12, 0.0,
                    matrix2.m21, matrix2.m22, 0.0,
                    translation.x, translation.y, 1.0)
        }
        set (m) {
            self.matrix2 = .init(m.m11, m.m12, m.m21, m.m22)
            self.translation = .init(m.m31, m.m32)
        }
    }

    public var linearTransform: LinearTransform2 {
        get { LinearTransform2(self.matrix2) }
        set(t) { self.matrix2 = t.matrix2 }
    }

    public static let identity: Self = .init(origin: .zero)

    public init() {
        self.matrix2 = .identity
        self.translation = .zero
    }

    public init(origin: Vector2) {
        self.matrix2 = .identity
        self.translation = origin
    }

    public init(linear: Matrix2, origin: Vector2 = .zero) {
        self.matrix2 = linear
        self.translation = origin
    }

    public init(linear: LinearTransform2, origin: Vector2 = .zero) {
        self.matrix2 = linear.matrix2
        self.translation = origin
    }

    public init(axisX: Vector2, axisY: Vector2, origin: Vector2 = .zero) {
        self.matrix2 = .init(row1: axisX, row2: axisY)
        self.translation = origin
    }

    public init(x: Scalar, y: Scalar) {
        self.matrix2 = .identity
        self.translation = .init(x, y)
    }

    public init(_ m: Matrix3) {
        self.matrix2 = .init(m.m11, m.m12, m.m21, m.m22)
        self.translation = .init(m.m31, m.m32)
    }

    public func inverted() -> Self {
        let matrix = self.matrix2.inverted() ?? .identity
        let origin = -translation * matrix
        return Self(linear: matrix2, origin: origin)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public func translated(by offset: Vector2) -> Self {
        // Translate
        // |1  0  0|
        // |0  1  0|
        // |X  Y  1|
        return Self(linear: matrix2, origin: self.translation + offset)        
    }

    public mutating func translate(by offset: Vector2) {
        self = self.translated(by: offset)
    }

    public func translated(x: Scalar, y: Scalar) -> Self {
        return self.translated(by: Vector2(x, y))
    }

    public mutating func translate(x: Scalar, y: Scalar) {
        self = self.translated(x: x, y: y)
    }

    public func transformed(by t: LinearTransform2) -> Self {
        return Self(linear: matrix2 * t.matrix2, origin: translation * t.matrix2)
    }

    public mutating func transform(by t: LinearTransform2) {
        self = self.transformed(by: t)
    }

    public func transformed(by t: AffineTransform2) -> Self {
        return Self(linear: matrix2 * t.matrix2,
                    origin: translation * t.matrix2 + t.translation)
    }

    public mutating func transform(by t: AffineTransform2) {
        self = self.transformed(by: t)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.matrix2 == rhs.matrix2 && lhs.translation == rhs.translation
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return lhs.transformed(by: rhs)
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }

    public static func * (lhs: Self, rhs: LinearTransform2) -> Self {
        return lhs.transformed(by: rhs)
    }

    public static func *= (lhs: inout Self, rhs: LinearTransform2) {
        lhs = lhs * rhs
    }

    public static func * (lhs: Vector2, rhs: Self) -> Vector2 {
        let v = Vector3(lhs.x, lhs.y, 1.0).transformed(by: rhs.matrix3)
        return Vector2(v.x, v.y) * (1.0 / v.z)
    }

    public static func *= (lhs: inout Vector2, rhs: Self) {
        lhs = lhs * rhs
    }
}
