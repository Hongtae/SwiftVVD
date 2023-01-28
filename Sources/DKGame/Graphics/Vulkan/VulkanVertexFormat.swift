//
//  File: VulkanVertexFormat.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

public extension VertexFormat {
    func vkFormat() -> VkFormat {
        switch self {
        case .uchar2:               return VK_FORMAT_R8G8_UINT
        case .uchar3:               return VK_FORMAT_R8G8B8_UINT
        case .uchar4:               return VK_FORMAT_R8G8B8A8_UINT
        case .char2:                return VK_FORMAT_R8G8_SINT
        case .char3:                return VK_FORMAT_R8G8B8_SINT
        case .char4:                return VK_FORMAT_R8G8B8A8_SINT
        case .uchar2Normalized:     return VK_FORMAT_R8G8_UNORM
        case .uchar3Normalized:     return VK_FORMAT_R8G8B8_UNORM
        case .uchar4Normalized:     return VK_FORMAT_R8G8B8A8_UNORM
        case .char2Normalized:      return VK_FORMAT_R8G8_SNORM
        case .char3Normalized:      return VK_FORMAT_R8G8B8_SNORM
        case .char4Normalized:      return VK_FORMAT_R8G8B8A8_SNORM
        case .ushort2:              return VK_FORMAT_R16G16_UINT
        case .ushort3:              return VK_FORMAT_R16G16B16_UINT
        case .ushort4:              return VK_FORMAT_R16G16B16A16_UINT
        case .short2:               return VK_FORMAT_R16G16_SINT
        case .short3:               return VK_FORMAT_R16G16B16_SINT
        case .short4:               return VK_FORMAT_R16G16B16A16_SINT
        case .ushort2Normalized:    return VK_FORMAT_R16G16_UNORM
        case .ushort3Normalized:    return VK_FORMAT_R16G16B16_UNORM
        case .ushort4Normalized:    return VK_FORMAT_R16G16B16A16_UNORM
        case .short2Normalized:     return VK_FORMAT_R16G16_SNORM
        case .short3Normalized:     return VK_FORMAT_R16G16B16_SNORM
        case .short4Normalized:     return VK_FORMAT_R16G16B16A16_SNORM
        case .half2:                return VK_FORMAT_R16G16_SFLOAT
        case .half3:                return VK_FORMAT_R16G16B16_SFLOAT
        case .half4:                return VK_FORMAT_R16G16B16A16_SFLOAT
        case .float:                return VK_FORMAT_R32_SFLOAT
        case .float2:               return VK_FORMAT_R32G32_SFLOAT
        case .float3:               return VK_FORMAT_R32G32B32_SFLOAT
        case .float4:               return VK_FORMAT_R32G32B32A32_SFLOAT
        case .int:                  return VK_FORMAT_R32_SINT
        case .int2:                 return VK_FORMAT_R32G32_SINT
        case .int3:                 return VK_FORMAT_R32G32B32_SINT
        case .int4:                 return VK_FORMAT_R32G32B32A32_SINT
        case .uint:                 return VK_FORMAT_R32_UINT
        case .uint2:                return VK_FORMAT_R32G32_UINT
        case .uint3:                return VK_FORMAT_R32G32B32_UINT
        case .uint4:                return VK_FORMAT_R32G32B32A32_UINT
        case .int1010102Normalized:     return VK_FORMAT_A2B10G10R10_SNORM_PACK32
        case .uint1010102Normalized:    return VK_FORMAT_A2B10G10R10_UNORM_PACK32
        default:
            assertionFailure("Unknown type! (or not implemented yet)")
            break
        }
        return VK_FORMAT_UNDEFINED
    }
}
#endif //if ENABLE_VULKAN
