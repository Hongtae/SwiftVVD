//
//  File: VulkanVertexFormat.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

extension VertexFormat {
    func vkFormat() -> VkFormat {
        let format = switch self {
        case .uchar:                    VK_FORMAT_R8_UINT
        case .uchar2:                   VK_FORMAT_R8G8_UINT
        case .uchar3:                   VK_FORMAT_R8G8B8_UINT
        case .uchar4:                   VK_FORMAT_R8G8B8A8_UINT
        case .char:                     VK_FORMAT_R8_SINT
        case .char2:                    VK_FORMAT_R8G8_SINT
        case .char3:                    VK_FORMAT_R8G8B8_SINT
        case .char4:                    VK_FORMAT_R8G8B8A8_SINT
        case .ucharNormalized:          VK_FORMAT_R8_UNORM
        case .uchar2Normalized:         VK_FORMAT_R8G8_UNORM
        case .uchar3Normalized:         VK_FORMAT_R8G8B8_UNORM
        case .uchar4Normalized:         VK_FORMAT_R8G8B8A8_UNORM
        case .charNormalized:           VK_FORMAT_R8_SNORM
        case .char2Normalized:          VK_FORMAT_R8G8_SNORM
        case .char3Normalized:          VK_FORMAT_R8G8B8_SNORM
        case .char4Normalized:          VK_FORMAT_R8G8B8A8_SNORM
        case .ushort:                   VK_FORMAT_R16_UINT
        case .ushort2:                  VK_FORMAT_R16G16_UINT
        case .ushort3:                  VK_FORMAT_R16G16B16_UINT
        case .ushort4:                  VK_FORMAT_R16G16B16A16_UINT
        case .short:                    VK_FORMAT_R16_SINT
        case .short2:                   VK_FORMAT_R16G16_SINT
        case .short3:                   VK_FORMAT_R16G16B16_SINT
        case .short4:                   VK_FORMAT_R16G16B16A16_SINT
        case .ushortNormalized:         VK_FORMAT_R16_UNORM
        case .ushort2Normalized:        VK_FORMAT_R16G16_UNORM
        case .ushort3Normalized:        VK_FORMAT_R16G16B16_UNORM
        case .ushort4Normalized:        VK_FORMAT_R16G16B16A16_UNORM
        case .shortNormalized:          VK_FORMAT_R16_SNORM
        case .short2Normalized:         VK_FORMAT_R16G16_SNORM
        case .short3Normalized:         VK_FORMAT_R16G16B16_SNORM
        case .short4Normalized:         VK_FORMAT_R16G16B16A16_SNORM
        case .half:                     VK_FORMAT_R16_SFLOAT
        case .half2:                    VK_FORMAT_R16G16_SFLOAT
        case .half3:                    VK_FORMAT_R16G16B16_SFLOAT
        case .half4:                    VK_FORMAT_R16G16B16A16_SFLOAT
        case .float:                    VK_FORMAT_R32_SFLOAT
        case .float2:                   VK_FORMAT_R32G32_SFLOAT
        case .float3:                   VK_FORMAT_R32G32B32_SFLOAT
        case .float4:                   VK_FORMAT_R32G32B32A32_SFLOAT
        case .int:                      VK_FORMAT_R32_SINT
        case .int2:                     VK_FORMAT_R32G32_SINT
        case .int3:                     VK_FORMAT_R32G32B32_SINT
        case .int4:                     VK_FORMAT_R32G32B32A32_SINT
        case .uint:                     VK_FORMAT_R32_UINT
        case .uint2:                    VK_FORMAT_R32G32_UINT
        case .uint3:                    VK_FORMAT_R32G32B32_UINT
        case .uint4:                    VK_FORMAT_R32G32B32A32_UINT
        case .int1010102Normalized:     VK_FORMAT_A2B10G10R10_SNORM_PACK32
        case .uint1010102Normalized:    VK_FORMAT_A2B10G10R10_UNORM_PACK32
        default:
            VK_FORMAT_UNDEFINED
        }
        assert(format != VK_FORMAT_UNDEFINED, "Unknown vertex format!")
        return format
    }
}
#endif //if ENABLE_VULKAN
