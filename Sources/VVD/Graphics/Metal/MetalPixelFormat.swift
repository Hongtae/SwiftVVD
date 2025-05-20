//
//  File: MetalPixelFormat.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

extension PixelFormat {
    static func from(mtlPixelFormat format: MTLPixelFormat) -> PixelFormat {
        switch format {
        case .r8Unorm:                  .r8Unorm
        case .r8Snorm:                  .r8Snorm
        case .r8Uint:                   .r8Uint
        case .r8Sint:                   .r8Sint
        case .r16Unorm:                 .r16Unorm
        case .r16Snorm:                 .r16Snorm
        case .r16Uint:                  .r16Uint
        case .r16Sint:                  .r16Sint
        case .r16Float:                 .r16Float
        case .rg8Unorm:                 .rg8Unorm
        case .rg8Snorm:                 .rg8Snorm
        case .rg8Uint:                  .rg8Uint
        case .rg8Sint:                  .rg8Sint
        case .r32Uint:                  .r32Uint
        case .r32Sint:                  .r32Sint
        case .r32Float:                 .r32Float
        case .rg16Unorm:                .rg16Unorm
        case .rg16Snorm:                .rg16Snorm
        case .rg16Uint:                 .rg16Uint
        case .rg16Sint:                 .rg16Sint
        case .rg16Float:                .rg16Float
        case .rgba8Unorm:               .rgba8Unorm
        case .rgba8Unorm_srgb:          .rgba8Unorm_srgb
        case .rgba8Snorm:               .rgba8Snorm
        case .rgba8Uint:                .rgba8Uint
        case .rgba8Sint:                .rgba8Sint
        case .bgra8Unorm:               .bgra8Unorm
        case .bgra8Unorm_srgb:          .bgra8Unorm_srgb
        case .rgb10a2Unorm:             .rgb10a2Unorm
        case .rgb10a2Uint:              .rgb10a2Uint
        case .rg11b10Float:             .rg11b10Float
        case .rgb9e5Float:              .rgb9e5Float
        case .bgr10a2Unorm:             .bgr10a2Unorm
        case .rg32Uint:                 .rg32Uint
        case .rg32Sint:                 .rg32Sint
        case .rg32Float:                .rg32Float
        case .rgba16Unorm:              .rgba16Unorm
        case .rgba16Snorm:              .rgba16Snorm
        case .rgba16Uint:               .rgba16Uint
        case .rgba16Sint:               .rgba16Sint
        case .rgba16Float:              .rgba16Float
        case .rgba32Uint:               .rgba32Uint
        case .rgba32Sint:               .rgba32Sint
        case .rgba32Float:              .rgba32Float
        case .depth16Unorm:             .depth16Unorm
        case .depth32Float:             .depth32Float
        case .stencil8:                 .stencil8
        case .depth32Float_stencil8:    .depth32Float_stencil8
        default:
                .invalid
        }
    }

    func mtlPixelFormat() -> MTLPixelFormat {
        switch self {
        case .r8Unorm:                  .r8Unorm
        case .r8Snorm:                  .r8Snorm
        case .r8Uint:                   .r8Uint
        case .r8Sint:                   .r8Sint
        case .r16Unorm:                 .r16Unorm
        case .r16Snorm:                 .r16Snorm
        case .r16Uint:                  .r16Uint
        case .r16Sint:                  .r16Sint
        case .r16Float:                 .r16Float
        case .rg8Unorm:                 .rg8Unorm
        case .rg8Snorm:                 .rg8Snorm
        case .rg8Uint:                  .rg8Uint
        case .rg8Sint:                  .rg8Sint
        case .r32Uint:                  .r32Uint
        case .r32Sint:                  .r32Sint
        case .r32Float:                 .r32Float
        case .rg16Unorm:                .rg16Unorm
        case .rg16Snorm:                .rg16Snorm
        case .rg16Uint:                 .rg16Uint
        case .rg16Sint:                 .rg16Sint
        case .rg16Float:                .rg16Float
        case .rgba8Unorm:               .rgba8Unorm
        case .rgba8Unorm_srgb:          .rgba8Unorm_srgb
        case .rgba8Snorm:               .rgba8Snorm
        case .rgba8Uint:                .rgba8Uint
        case .rgba8Sint:                .rgba8Sint
        case .bgra8Unorm:               .bgra8Unorm
        case .bgra8Unorm_srgb:          .bgra8Unorm_srgb
        case .rgb10a2Unorm:             .rgb10a2Unorm
        case .rgb10a2Uint:              .rgb10a2Uint
        case .rg11b10Float:             .rg11b10Float
        case .rgb9e5Float:              .rgb9e5Float
        case .bgr10a2Unorm:             .bgr10a2Unorm
        case .rg32Uint:                 .rg32Uint
        case .rg32Sint:                 .rg32Sint
        case .rg32Float:                .rg32Float
        case .rgba16Unorm:              .rgba16Unorm
        case .rgba16Snorm:              .rgba16Snorm
        case .rgba16Uint:               .rgba16Uint
        case .rgba16Sint:               .rgba16Sint
        case .rgba16Float:              .rgba16Float
        case .rgba32Uint:               .rgba32Uint
        case .rgba32Sint:               .rgba32Sint
        case .rgba32Float:              .rgba32Float
        case .depth16Unorm:             .depth16Unorm
        case .depth32Float:             .depth32Float
        case .stencil8:                 .stencil8
        case .depth32Float_stencil8:    .depth32Float_stencil8
        default:
                .invalid
        }
    }
}
#endif //if ENABLE_METAL
