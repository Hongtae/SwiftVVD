import Foundation

public struct Quaternion {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    public var w: Scalar

    public static let zero = Quaternion(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
}
