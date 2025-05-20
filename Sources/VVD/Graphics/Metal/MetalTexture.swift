//
//  File: MetalTexture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalTexture: Texture {
    let device: GraphicsDevice
    let parent: Texture?

    let texture: MTLTexture

    var width: Int       { texture.width }
    var height: Int      { texture.height }
    var depth: Int       { texture.depth }
    var mipmapCount: Int { texture.mipmapLevelCount }
    var arrayLength: Int { texture.arrayLength }
    var sampleCount: Int { texture.sampleCount }

    var type: TextureType {
        switch texture.textureType {
        case .type1D, .type1DArray:
            return .type1D
        case .type2D, .type2DArray, .type2DMultisample, .type2DMultisampleArray:
            return .type2D
        case .type3D:
            return .type3D
        case .typeCube:
            return .typeCube
        default:
            return .unknown
        }
    }

    var pixelFormat: PixelFormat {
        .from(mtlPixelFormat: texture.pixelFormat)
    }

    var isTransient: Bool {
        texture.storageMode == .memoryless
    }

    func makeTextureView(pixelFormat: PixelFormat) -> Texture? {
        if let texture = self.texture.makeTextureView(pixelFormat: pixelFormat.mtlPixelFormat()) {
            return MetalTexture(device: self.device as! MetalGraphicsDevice,
                                texture: texture,
                                parent: self)
        }
        return nil
    }

    init(device: MetalGraphicsDevice, texture: MTLTexture, parent: Texture? = nil) {
        self.device = device
        self.texture = texture
        self.parent = parent
    }
}
#endif //if ENABLE_METAL
