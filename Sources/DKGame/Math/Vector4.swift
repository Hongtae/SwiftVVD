import Foundation

public struct Vector4 {
    public var x : Scalar
    public var y : Scalar
    public var z : Scalar
    public var w : Scalar

    subscript(index: Int) -> Scalar {
        get {
            switch index {
            case 0: return self.x
            case 1: return self.y
            case 2: return self.z
            case 3: return self.w
            default:
                assertionFailure("Index out of range")
                break
            }
            return .zero
        }
        set (value) {
            switch index {
            case 0: self.x = value
            case 1: self.y = value
            case 2: self.z = value
            case 3: self.w = value
            default:
                assertionFailure("Index out of range")
                break
            }
        }
    }

    public static let zero = Vector4(0.0, 0.0, 0.0, 0.0)

    public init() {
        self = .zero
    }

    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar, _ w: Scalar) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(x: Scalar, y: Scalar, z: Scalar, w: Scalar) {
        self.init(x, y, z, w)
    }
}
