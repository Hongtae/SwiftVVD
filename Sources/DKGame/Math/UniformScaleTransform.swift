import Foundation

public struct UniformScaleTransform {
    public var scale: Scalar
    public var orientation: Quaternion
    public var position: Vector3

    public static let identity: Self = .init(scale: 1.0, orientation: .identity, position: .zero)

    public var matrix3: Matrix3 { orientation.matrix3 * scale }
    public var matrix4: Matrix4 {
        let m = self.matrix3
        return Matrix4(m.m11, m.m12, m.m13, 0.0,
                       m.m21, m.m22, m.m23, 0.0,
                       m.m31, m.m32, m.m33, 0.0,
                       position.x, position.y, position.z, 1.0)
    }

    public init(scale: Scalar = 1.0, orientation: Quaternion = .identity, position: Vector3 = .zero) {
        self.scale = scale
        self.orientation = orientation
        self.position = position
    }

    public func inverted() -> Self {
        let s = 1.0 / self.scale
        let r = orientation.conjugate
        let p = (-position * scale) * r
        return Self(scale: s, orientation: r, position: p)
    }

    public mutating func invert() {
        self = self.inverted()
    }

    public static func * (lhs: Vector3, rhs: Self) -> Vector3 {
        return lhs * rhs.scale * rhs.orientation + rhs.position
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        return Self(scale: lhs.scale * rhs.scale,
                    orientation: lhs.orientation * rhs.orientation,
                    position: lhs.position * rhs.matrix3 + rhs.position)
    }

    public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
}
