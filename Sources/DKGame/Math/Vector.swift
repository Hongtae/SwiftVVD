import Foundation

public typealias Scalar = CGFloat

public struct Vector2 {
    public var x : Scalar
    public var y : Scalar

    public static let zero = Vector2(x: 0.0, y: 0.0)
}

public struct Vector3 {
    public var x : Scalar
    public var y : Scalar
    public var z : Scalar

    public static let zero = Vector3(x: 0.0, y: 0.0, z: 0.0)
}

public struct Vector4 {
    public var x : Scalar
    public var y : Scalar
    public var z : Scalar
    public var w : Scalar

    public static let zero = Vector4(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
}
