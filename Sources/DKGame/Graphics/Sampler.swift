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
    public var addressModeU: SamplerAddressMode
    public var addressModeV: SamplerAddressMode
    public var addressModeW: SamplerAddressMode

    public var minFilter: SamplerMinMagFilter
    public var magFilter: SamplerMinMagFilter
    public var mipFilter: SamplerMipFilter

    public var minLod: Float
    public var maxLod: Float

    public var maxAnisotropy: UInt32
    public var normalizedCoordinates: Bool

    // comparison function used when sampling texels from a depth texture.
    public var compareFunction: CompareFunction

    public init(addressModeU: SamplerAddressMode = .clampToEdge,
                addressModeV: SamplerAddressMode = .clampToEdge,
                addressModeW: SamplerAddressMode = .clampToEdge,
                minFilter: SamplerMinMagFilter = .nearest,
                magFilter: SamplerMinMagFilter = .nearest,
                mipFilter: SamplerMipFilter = .notMipmapped,
                minLod: Float = 0.0,
                maxLod: Float = .greatestFiniteMagnitude, // 3.402823466e+38 // FLT_MAX
                maxAnisotropy: UInt32 = 1,
                normalizedCoordinates: Bool = true,
                compareFunction: CompareFunction = .never) {
        self.addressModeU = addressModeU
        self.addressModeV = addressModeV
        self.addressModeW = addressModeW
        self.minFilter = minFilter
        self.magFilter = magFilter
        self.mipFilter = mipFilter
        self.minLod = minLod
        self.maxLod = maxLod
        self.maxAnisotropy = maxAnisotropy
        self.normalizedCoordinates = normalizedCoordinates
        self.compareFunction = compareFunction
    }
}

public protocol SamplerState: AnyObject {
    var device: GraphicsDevice { get }
}
