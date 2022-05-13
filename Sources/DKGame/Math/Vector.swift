import Foundation

public protocol Vector {
    associatedtype Scalar

    var length: Self.Scalar { get }
    var lengthSquared: Self.Scalar { get }

    static var zero: Self { get }

    mutating func normalize()
    func normalized()->Self

    static func dot(_:Self, _:Self) -> Self.Scalar

    static prefix func - (_: Self) -> Self
 
    static func + (_:Self, _:Self) -> Self
    static func - (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self) -> Self
    static func * (_:Self, _:Self.Scalar) -> Self
 
    static func += (_:inout Self, _:Self)
    static func -= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self)
    static func *= (_:inout Self, _:Self.Scalar)

    static func == (_:Self, _:Self) -> Bool
    static func != (_:Self, _:Self) -> Bool

    static func minimum(_:Self, _:Self) -> Self
    static func maximum(_:Self, _:Self) -> Self
}

public extension Vector where Scalar: FloatingPoint {
    var length: Self.Scalar  { self.lengthSquared.squareRoot() }

    func normalized()->Self {
        let lengthSq = self.lengthSquared
        if lengthSq.isZero == false {
            let inv = Self.Scalar(1) / lengthSq.squareRoot()
            return self * inv
        }
        return self
    }    
}

public extension Vector {
    var lengthSquared: Self.Scalar    { Self.dot(self, self) }

    var magnitude: Self.Scalar        { self.length }
    var magnitudeSquared: Self.Scalar { self.lengthSquared }

    mutating func normalize() {
        self = self.normalized()
    }

    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    static func *= (lhs: inout Self, rhs: Self.Scalar) { lhs = lhs * rhs }
    static func != (lhs: Self, rhs: Self) -> Bool { return !(lhs == rhs) }
}

public protocol LinearTransformable {
    associatedtype LinearTransformMatrix
    mutating func transform(by:LinearTransformMatrix)
    func transformed(by:LinearTransformMatrix) -> Self

    static func * (_: Self, _: Self.LinearTransformMatrix) -> Self
    static func *= (_: inout Self, _: Self.LinearTransformMatrix)
}

public extension LinearTransformable {
    mutating func transform(by t: Self.LinearTransformMatrix) {
        self = self.transformed(by:t)
    }
    static func * (lhs: Self, rhs: Self.LinearTransformMatrix) -> Self {
        return lhs.transformed(by: rhs)
    }
    static func *= (lhs: inout Self, rhs: Self.LinearTransformMatrix) {
        lhs.transform(by: rhs)
    }
}

public protocol HomogeneousTransformable {
    associatedtype HomogeneousTransformMatrix
    mutating func transform(by:HomogeneousTransformMatrix)
    func transformed(by:HomogeneousTransformMatrix) -> Self

    // static func * (_:Self, _:Self.HomogeneousTransformMatrix) -> Self
    // static func *= (_:inout Self, _:Self.HomogeneousTransformMatrix)
}

public extension HomogeneousTransformable {
    mutating func transform(by t: Self.HomogeneousTransformMatrix) {
        self = self.transformed(by: t)
    }
    // static func * (lhs: Self, rhs: Self.HomogeneousTransformMatrix) -> Self {
    //     return lhs.transformed(by: rhs)
    // }
    // static func *= (lhs: inout Self, rhs: Self.HomogeneousTransformMatrix) {
    //     lhs = lhs.transformed(by: rhs)
    // }
}
