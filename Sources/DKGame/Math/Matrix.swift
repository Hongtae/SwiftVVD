public protocol Matrix {
    associatedtype Scalar
    associatedtype Vector

    mutating func invert()
    func inverted() -> Self?

    mutating func transpose()
    func transposed() -> Self

    var determinant: Self.Scalar { get }

    subscript(row: Int, column: Int) -> Self.Scalar { get set }
    subscript(row: Int) -> Self.Vector { get set }

    static var identity: Self { get }

    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool

    static func + (_:Self, _:Self) -> Self
    static func - (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self.Scalar) -> Self

    static func += (_:inout Self, _:Self)
    static func -= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self.Scalar)
}

public extension Matrix {
    mutating func invert()      { self = self.inverted() ?? self }
    mutating func transpose()   { self = self.transposed() }

    static func != (_ lhs:Self, _ rhs:Self) -> Bool { return !(lhs == rhs) }
    
    static func += (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs + rhs }
    static func -= (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs - rhs }
    static func *= (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs * rhs }
    static func *= (_ lhs:inout Self, _ rhs:Self.Scalar)  { lhs = lhs * rhs }
}
