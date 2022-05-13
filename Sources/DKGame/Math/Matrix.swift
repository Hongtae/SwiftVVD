public protocol Matrix {
    associatedtype Vector

    mutating func invert()
    func inverted() -> Self?

    mutating func transpose()
    func transposed() -> Self

    var determinant: Scalar { get }

    subscript(row: Int, column: Int) -> Scalar { get set }
    subscript(row: Int) -> Self.Vector { get set }

    static var identity: Self { get }

    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool

    static func + (_:Self, _:Self) -> Self
    static func - (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self) -> Self
    static func * (_:Self, _:Scalar) -> Self

    static func += (_:inout Self, _:Self)
    static func -= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Scalar)
}

public extension Matrix {
    mutating func invert()      { self = self.inverted() ?? self }
    mutating func transpose()   { self = self.transposed() }

    static func != (_ lhs:Self, _ rhs:Self) -> Bool { return !(lhs == rhs) }
    
    static func += (_ lhs:inout Self, _ rhs:Self)       { lhs = lhs + rhs }
    static func -= (_ lhs:inout Self, _ rhs:Self)       { lhs = lhs - rhs }
    static func *= (_ lhs:inout Self, _ rhs:Self)       { lhs = lhs * rhs }
    static func *= (_ lhs:inout Self, _ rhs:Scalar)     { lhs = lhs * rhs }
}
