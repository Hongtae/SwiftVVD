//
//  File: MetalTexture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalTexture: Texture {
    public let device: GraphicsDevice
    let texture: MTLTexture

    public var width: Int       { texture.width }
    public var height: Int      { texture.height }
    public var depth: Int       { texture.depth }
    public var mipmapCount: Int { texture.mipmapLevelCount }
    public var arrayLength: Int { texture.arrayLength }

    public var type: TextureType {
        switch texture.textureType {
        case .type1D, .type1DArray:
            return .type1D
        case .type2D, .type2DArray:
            return .type2D
        case .type3D:
            return .type3D
        case .typeCube:
            return .typeCube
        default:
            return .unknown
        }
    }

    public var pixelFormat: PixelFormat {
        .from(mtlPixelFormat: texture.pixelFormat)
    }

    init(device: MetalGraphicsDevice, texture: MTLTexture) {
        self.device = device
        self.texture = texture
    }
}
#endif //if ENABLE_METAL
