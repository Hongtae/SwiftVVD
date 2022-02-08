public enum SamplerMinMagFilter {
    case nearest
    case linear
}

public enum SamplerMipFilter {
    case notMipmapped
    case nearest
    case linear
}

public enum SamplerAddressMode {
    case clampToEdge
    case `repeat`
    case mirrorRepeat
    case clampToZero
}

public struct SamplerDescriptor {

    var addressModeU: SamplerAddressMode = .clampToEdge
    var addressModeV: SamplerAddressMode = .clampToEdge
    var addressModeW: SamplerAddressMode = .clampToEdge

    var minFilter: SamplerMinMagFilter = .nearest
    var magFilter: SamplerMinMagFilter = .nearest
    var mipFilter: SamplerMipFilter = .notMipmapped

    var minLod: Float = 0.0
    var maxLod: Float = .greatestFiniteMagnitude // 3.402823466e+38 // FLT_MAX

    var maxAnisotropy: UInt32 = 1
    var normalizedCoordinates: Bool = true

    // comparison function used when sampling texels from a depth texture.
    var compareFunction: CompareFunction = .never
}

public protocol SamplerState {
    func device() -> GraphicsDevice
}
