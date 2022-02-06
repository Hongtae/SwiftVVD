public struct SamplerDescriptor {
	public enum MinMagFilter {
        case nearest
        case linear
    }
	public enum MipFilter {
        case notMipmapped
        case nearest
        case linear
    }
    public enum AddressMode {
        case clampToEdge
        case `repeat`
        case mirrorRepeat
        case clampToZero
    }

    var addressModeU: AddressMode = .clampToEdge
    var addressModeV: AddressMode = .clampToEdge
    var addressModeW: AddressMode = .clampToEdge

    var minFilter: MinMagFilter = .nearest
    var magFilter: MinMagFilter = .nearest
    var mipFilter: MipFilter = .notMipmapped

    var minLod: Float = 0.0
    var maxLod: Float = 3.402823466e+38 // FLT_MAX

    var maxAnisotropy: UInt32 = 1
    var normalizedCoordinates: Bool = true

    // comparison function used when sampling texels from a depth texture.
    var compareFunction: CompareFunction = .never
}

public protocol SamplerState {
    func device() -> GraphicsDevice
}
