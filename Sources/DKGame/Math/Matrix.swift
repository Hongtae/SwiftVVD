public protocol Matrix {
    associatedtype Scalar
    associatedtype Vector

    mutating func inverse()
    func inversed() -> Self

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

extension Matrix {
    public static func != (_ lhs:inout Self, _ rhs:Self) -> Bool { return !(lhs == rhs) }
    public static func += (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs + rhs }
    public static func -= (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs - rhs }
    public static func *= (_ lhs:inout Self, _ rhs:Self)         { lhs = lhs * rhs }
    public static func *= (_ lhs:inout Self, _ rhs:Self.Scalar)  { lhs = lhs * rhs }
}
