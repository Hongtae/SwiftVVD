//
//  File: Sampler.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

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

    public var lodMinClamp: Float
    public var lodMaxClamp: Float

    public var maxAnisotropy: Int
    public var normalizedCoordinates: Bool

    // comparison function used when sampling texels from a depth texture.
    public var compareFunction: CompareFunction

    public init(addressModeU: SamplerAddressMode = .clampToEdge,
                addressModeV: SamplerAddressMode = .clampToEdge,
                addressModeW: SamplerAddressMode = .clampToEdge,
                minFilter: SamplerMinMagFilter = .nearest,
                magFilter: SamplerMinMagFilter = .nearest,
                mipFilter: SamplerMipFilter = .notMipmapped,
                lodMinClamp: Float = 0.0,
                lodMaxClamp: Float = .greatestFiniteMagnitude, // 3.402823466e+38 // FLT_MAX
                maxAnisotropy: Int = 1,
                normalizedCoordinates: Bool = true,
                compareFunction: CompareFunction = .never) {
        self.addressModeU = addressModeU
        self.addressModeV = addressModeV
        self.addressModeW = addressModeW
        self.minFilter = minFilter
        self.magFilter = magFilter
        self.mipFilter = mipFilter
        self.lodMinClamp = lodMinClamp
        self.lodMaxClamp = lodMaxClamp
        self.maxAnisotropy = maxAnisotropy
        self.normalizedCoordinates = normalizedCoordinates
        self.compareFunction = compareFunction
    }
}

public protocol SamplerState: AnyObject {
    var device: GraphicsDevice { get }
}
