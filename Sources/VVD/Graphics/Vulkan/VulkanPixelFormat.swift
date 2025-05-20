//
//  File: VulkanPixelFormat.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

extension PixelFormat {
    static func from(vkFormat format: VkFormat) -> PixelFormat {
        switch format {
        case VK_FORMAT_R8_UNORM:                    .r8Unorm
        case VK_FORMAT_R8_SNORM:                    .r8Snorm
        case VK_FORMAT_R8_UINT:                     .r8Uint
        case VK_FORMAT_R8_SINT:                     .r8Sint

        case VK_FORMAT_R16_UNORM:                   .r16Unorm
        case VK_FORMAT_R16_SNORM:                   .r16Snorm
        case VK_FORMAT_R16_UINT:                    .r16Uint
        case VK_FORMAT_R16_SINT:                    .r16Sint
        case VK_FORMAT_R16_SFLOAT:                  .r16Float

        case VK_FORMAT_R8G8_UNORM:                  .rg8Unorm
        case VK_FORMAT_R8G8_SNORM:                  .rg8Snorm
        case VK_FORMAT_R8G8_UINT:                   .rg8Uint
        case VK_FORMAT_R8G8_SINT:                   .rg8Sint

        case VK_FORMAT_R32_UINT:                    .r32Uint
        case VK_FORMAT_R32_SINT:                    .r32Sint
        case VK_FORMAT_R32_SFLOAT:                  .r32Float

        case VK_FORMAT_R16G16_UNORM:                .rg16Unorm
        case VK_FORMAT_R16G16_SNORM:                .rg16Snorm
        case VK_FORMAT_R16G16_UINT:                 .rg16Uint
        case VK_FORMAT_R16G16_SINT:                 .rg16Sint
        case VK_FORMAT_R16G16_SFLOAT:               .rg16Float

        case VK_FORMAT_R8G8B8A8_UNORM:              .rgba8Unorm
        case VK_FORMAT_R8G8B8A8_SRGB:               .rgba8Unorm_srgb
        case VK_FORMAT_R8G8B8A8_SNORM:              .rgba8Snorm
        case VK_FORMAT_R8G8B8A8_UINT:               .rgba8Uint
        case VK_FORMAT_R8G8B8A8_SINT:               .rgba8Sint

        case VK_FORMAT_B8G8R8A8_UNORM:              .bgra8Unorm
        case VK_FORMAT_B8G8R8A8_SRGB:               .bgra8Unorm_srgb

        case VK_FORMAT_A2B10G10R10_UNORM_PACK32:    .rgb10a2Unorm
        case VK_FORMAT_A2B10G10R10_UINT_PACK32:     .rgb10a2Uint
        case VK_FORMAT_B10G11R11_UFLOAT_PACK32:     .rg11b10Float
        case VK_FORMAT_E5B9G9R9_UFLOAT_PACK32:      .rgb9e5Float
        case VK_FORMAT_A2R10G10B10_UNORM_PACK32:    .bgr10a2Unorm

        case VK_FORMAT_R32G32_UINT:                 .rg32Uint
        case VK_FORMAT_R32G32_SINT:                 .rg32Sint
        case VK_FORMAT_R32G32_SFLOAT:               .rg32Float

        case VK_FORMAT_R16G16B16A16_UNORM:          .rgba16Unorm
        case VK_FORMAT_R16G16B16A16_SNORM:          .rgba16Snorm
        case VK_FORMAT_R16G16B16A16_UINT:           .rgba16Uint
        case VK_FORMAT_R16G16B16A16_SINT:           .rgba16Sint
        case VK_FORMAT_R16G16B16A16_SFLOAT:         .rgba16Float

        case VK_FORMAT_R32G32B32A32_UINT:           .rgba32Uint
        case VK_FORMAT_R32G32B32A32_SINT:           .rgba32Sint
        case VK_FORMAT_R32G32B32A32_SFLOAT:         .rgba32Float

        case VK_FORMAT_D16_UNORM:                   .depth16Unorm
        case VK_FORMAT_D32_SFLOAT:                  .depth32Float
        case VK_FORMAT_S8_UINT:                     .stencil8

        case VK_FORMAT_D24_UNORM_S8_UINT:           .depth24Unorm_stencil8
        case VK_FORMAT_D32_SFLOAT_S8_UINT:          .depth32Float_stencil8
        default:
            .invalid
        }
    }
    
    func vkFormat() -> VkFormat {
        switch self {
        case .r8Unorm:                  VK_FORMAT_R8_UNORM
        case .r8Snorm:                  VK_FORMAT_R8_SNORM
        case .r8Uint:                   VK_FORMAT_R8_UINT
        case .r8Sint:                   VK_FORMAT_R8_SINT

        case .r16Unorm:                 VK_FORMAT_R16_UNORM
        case .r16Snorm:                 VK_FORMAT_R16_SNORM
        case .r16Uint:                  VK_FORMAT_R16_UINT
        case .r16Sint:                  VK_FORMAT_R16_SINT
        case .r16Float:                 VK_FORMAT_R16_SFLOAT

        case .rg8Unorm:                 VK_FORMAT_R8G8_UNORM
        case .rg8Snorm:                 VK_FORMAT_R8G8_SNORM
        case .rg8Uint:                  VK_FORMAT_R8G8_UINT
        case .rg8Sint:                  VK_FORMAT_R8G8_SINT

        case .r32Uint:                  VK_FORMAT_R32_UINT
        case .r32Sint:                  VK_FORMAT_R32_SINT
        case .r32Float:                 VK_FORMAT_R32_SFLOAT

        case .rg16Unorm:                VK_FORMAT_R16G16_UNORM
        case .rg16Snorm:                VK_FORMAT_R16G16_SNORM
        case .rg16Uint:                 VK_FORMAT_R16G16_UINT
        case .rg16Sint:                 VK_FORMAT_R16G16_SINT
        case .rg16Float:                VK_FORMAT_R16G16_SFLOAT

        case .rgba8Unorm:               VK_FORMAT_R8G8B8A8_UNORM
        case .rgba8Unorm_srgb:          VK_FORMAT_R8G8B8A8_SRGB
        case .rgba8Snorm:               VK_FORMAT_R8G8B8A8_SNORM
        case .rgba8Uint:                VK_FORMAT_R8G8B8A8_UINT
        case .rgba8Sint:                VK_FORMAT_R8G8B8A8_SINT

        case .bgra8Unorm:               VK_FORMAT_B8G8R8A8_UNORM
        case .bgra8Unorm_srgb:          VK_FORMAT_B8G8R8A8_SRGB

        case .rgb10a2Unorm:             VK_FORMAT_A2B10G10R10_UNORM_PACK32
        case .rgb10a2Uint:              VK_FORMAT_A2B10G10R10_UINT_PACK32
        case .rg11b10Float:             VK_FORMAT_B10G11R11_UFLOAT_PACK32
        case .rgb9e5Float:              VK_FORMAT_E5B9G9R9_UFLOAT_PACK32
        case .bgr10a2Unorm:             VK_FORMAT_A2R10G10B10_UNORM_PACK32

        case .rg32Uint:                 VK_FORMAT_R32G32_UINT
        case .rg32Sint:                 VK_FORMAT_R32G32_SINT
        case .rg32Float:                VK_FORMAT_R32G32_SFLOAT

        case .rgba16Unorm:              VK_FORMAT_R16G16B16A16_UNORM
        case .rgba16Snorm:              VK_FORMAT_R16G16B16A16_SNORM
        case .rgba16Uint:               VK_FORMAT_R16G16B16A16_UINT
        case .rgba16Sint:               VK_FORMAT_R16G16B16A16_SINT
        case .rgba16Float:              VK_FORMAT_R16G16B16A16_SFLOAT

        case .rgba32Uint:               VK_FORMAT_R32G32B32A32_UINT
        case .rgba32Sint:               VK_FORMAT_R32G32B32A32_SINT
        case .rgba32Float:              VK_FORMAT_R32G32B32A32_SFLOAT

        case .depth16Unorm:             VK_FORMAT_D16_UNORM
        case .depth32Float:             VK_FORMAT_D32_SFLOAT
        case .stencil8:                 VK_FORMAT_S8_UINT

        case .depth24Unorm_stencil8:    VK_FORMAT_D24_UNORM_S8_UINT
        case .depth32Float_stencil8:    VK_FORMAT_D32_SFLOAT_S8_UINT

        case .invalid:                  VK_FORMAT_UNDEFINED
        }
    }
}
#endif //if ENABLE_VULKAN
