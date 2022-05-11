import Foundation

public protocol Vector {
    associatedtype Scalar
    associatedtype TransformMatrix

    var length: Self.Scalar { get }
    var lengthSquared: Self.Scalar { get }

    static var zero: Self { get }

    mutating func normalize()
    func normalized()->Self

    mutating func transform(_:TransformMatrix)
    func transforming(_:TransformMatrix) -> Self

    static func dot(_:Self, _:Self) -> Self.Scalar

    static prefix func - (_: Self) -> Self
 
    static func + (_:Self, _:Self) -> Self
    static func - (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self.Scalar) -> Self
    static func * (_:Self, _:Self.TransformMatrix) -> Self
 
    static func += (_:inout Self, _:Self)
    static func -= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self.Scalar)
    static func *= (_:inout Self, _:Self.TransformMatrix)

    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool
}

extension Vector where Scalar: FloatingPoint {
    public var length: Self.Scalar  { sqrt(self.lengthSquared) }
}

extension Vector {
    public var lengthSquared: Self.Scalar   { Self.dot(self, self) }

    public var magnitude: Self.Scalar        { self.length }
    public var magnitudeSquared: Self.Scalar { self.lengthSquared }

    public static func += (_ lhs:inout Self, _ rhs:Self) { lhs = lhs + rhs }
    public static func -= (_ lhs:inout Self, _ rhs:Self) { lhs = lhs - rhs }
    public static func *= (_ lhs:inout Self, _ rhs:Self) { lhs = lhs * rhs }
    public static func *= (_ lhs:inout Self, _ rhs:Scalar) { lhs = lhs * rhs }
    public static func *= (_ lhs:inout Self, _ rhs:Self.TransformMatrix) { lhs = lhs * rhs }
    public static func != (_ lhs:Self, _ rhs:Self) -> Bool { return !(lhs == rhs) }
}
