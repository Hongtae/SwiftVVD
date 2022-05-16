#if ENABLE_VULKAN
import Vulkan

extension PixelFormat {
    public static func from(vkFormat format: VkFormat) -> PixelFormat {
        switch (format)
        {
        case VK_FORMAT_R8_UNORM:                    return .r8Unorm
        case VK_FORMAT_R8_SNORM:                    return .r8Snorm
        case VK_FORMAT_R8_UINT:                     return .r8Uint
        case VK_FORMAT_R8_SINT:                     return .r8Sint

        case VK_FORMAT_R16_UNORM:                   return .r16Unorm
        case VK_FORMAT_R16_SNORM:                   return .r16Snorm
        case VK_FORMAT_R16_UINT:                    return .r16Uint
        case VK_FORMAT_R16_SINT:                    return .r16Sint
        case VK_FORMAT_R16_SFLOAT:                  return .r16Float

        case VK_FORMAT_R8G8_UNORM:                  return .rg8Unorm
        case VK_FORMAT_R8G8_SNORM:                  return .rg8Snorm
        case VK_FORMAT_R8G8_UINT:                   return .rg8Uint
        case VK_FORMAT_R8G8_SINT:                   return .rg8Sint

        case VK_FORMAT_R32_UINT:                    return .r32Uint
        case VK_FORMAT_R32_SINT:                    return .r32Sint
        case VK_FORMAT_R32_SFLOAT:                  return .r32Float

        case VK_FORMAT_R16G16_UNORM:                return .rg16Unorm
        case VK_FORMAT_R16G16_SNORM:                return .rg16Snorm
        case VK_FORMAT_R16G16_UINT:                 return .rg16Uint
        case VK_FORMAT_R16G16_SINT:                 return .rg16Sint
        case VK_FORMAT_R16G16_SFLOAT:               return .rg16Float

        case VK_FORMAT_R8G8B8A8_UNORM:              return .rgba8Unorm
        case VK_FORMAT_R8G8B8A8_SRGB:               return .rgba8Unorm_srgb
        case VK_FORMAT_R8G8B8A8_SNORM:              return .rgba8Snorm
        case VK_FORMAT_R8G8B8A8_UINT:               return .rgba8Uint
        case VK_FORMAT_R8G8B8A8_SINT:               return .rgba8Sint

        case VK_FORMAT_B8G8R8A8_UNORM:              return .bgra8Unorm
        case VK_FORMAT_B8G8R8A8_SRGB:               return .bgra8Unorm_srgb

        case VK_FORMAT_A2B10G10R10_UNORM_PACK32:    return .rgb10a2Unorm
        case VK_FORMAT_A2B10G10R10_UINT_PACK32:     return .rgb10a2Uint

        case VK_FORMAT_B10G11R11_UFLOAT_PACK32:     return .rg11b10Float
        case VK_FORMAT_E5B9G9R9_UFLOAT_PACK32:      return .rgb9e5Float

        case VK_FORMAT_R32G32_UINT:                 return .rg32Uint
        case VK_FORMAT_R32G32_SINT:                 return .rg32Sint
        case VK_FORMAT_R32G32_SFLOAT:               return .rg32Float

        case VK_FORMAT_R16G16B16A16_UNORM:          return .rgba16Unorm
        case VK_FORMAT_R16G16B16A16_SNORM:          return .rgba16Snorm
        case VK_FORMAT_R16G16B16A16_UINT:           return .rgba16Uint
        case VK_FORMAT_R16G16B16A16_SINT:           return .rgba16Sint
        case VK_FORMAT_R16G16B16A16_SFLOAT:         return .rgba16Float

        case VK_FORMAT_R32G32B32A32_UINT:           return .rgba32Uint
        case VK_FORMAT_R32G32B32A32_SINT:           return .rgba32Sint
        case VK_FORMAT_R32G32B32A32_SFLOAT:         return .rgba32Float

        case VK_FORMAT_D32_SFLOAT:                  return .depth32Float
        case VK_FORMAT_S8_UINT:                     return .stencil8

        case VK_FORMAT_D32_SFLOAT_S8_UINT:          return .depth32Float_stencil8
        default:
            return .invalid
        }
    }
    
    public func vkFormat() -> VkFormat {
        switch (self)
        {
        case .r8Unorm:          return VK_FORMAT_R8_UNORM
        case .r8Snorm:          return VK_FORMAT_R8_SNORM
        case .r8Uint:           return VK_FORMAT_R8_UINT
        case .r8Sint:           return VK_FORMAT_R8_SINT

        case .r16Unorm:         return VK_FORMAT_R16_UNORM
        case .r16Snorm:         return VK_FORMAT_R16_SNORM
        case .r16Uint:          return VK_FORMAT_R16_UINT
        case .r16Sint:          return VK_FORMAT_R16_SINT
        case .r16Float:         return VK_FORMAT_R16_SFLOAT

        case .rg8Unorm:         return VK_FORMAT_R8G8_UNORM
        case .rg8Snorm:         return VK_FORMAT_R8G8_SNORM
        case .rg8Uint:          return VK_FORMAT_R8G8_UINT
        case .rg8Sint:          return VK_FORMAT_R8G8_SINT

        case .r32Uint:          return VK_FORMAT_R32_UINT
        case .r32Sint:          return VK_FORMAT_R32_SINT
        case .r32Float:         return VK_FORMAT_R32_SFLOAT

        case .rg16Unorm:        return VK_FORMAT_R16G16_UNORM
        case .rg16Snorm:        return VK_FORMAT_R16G16_SNORM
        case .rg16Uint:         return VK_FORMAT_R16G16_UINT
        case .rg16Sint:         return VK_FORMAT_R16G16_SINT
        case .rg16Float:        return VK_FORMAT_R16G16_SFLOAT

        case .rgba8Unorm:       return VK_FORMAT_R8G8B8A8_UNORM
        case .rgba8Unorm_srgb:  return VK_FORMAT_R8G8B8A8_SRGB
        case .rgba8Snorm:       return VK_FORMAT_R8G8B8A8_SNORM
        case .rgba8Uint:        return VK_FORMAT_R8G8B8A8_UINT
        case .rgba8Sint:        return VK_FORMAT_R8G8B8A8_SINT

        case .bgra8Unorm:       return VK_FORMAT_B8G8R8A8_UNORM
        case .bgra8Unorm_srgb:  return VK_FORMAT_B8G8R8A8_SRGB

        case .rgb10a2Unorm:     return VK_FORMAT_A2B10G10R10_UNORM_PACK32
        case .rgb10a2Uint:      return VK_FORMAT_A2B10G10R10_UINT_PACK32

        case .rg11b10Float:     return VK_FORMAT_B10G11R11_UFLOAT_PACK32
        case .rgb9e5Float:      return VK_FORMAT_E5B9G9R9_UFLOAT_PACK32

        case .rg32Uint:	        return VK_FORMAT_R32G32_UINT
        case .rg32Sint:	        return VK_FORMAT_R32G32_SINT
        case .rg32Float:        return VK_FORMAT_R32G32_SFLOAT

        case .rgba16Unorm:      return VK_FORMAT_R16G16B16A16_UNORM
        case .rgba16Snorm:      return VK_FORMAT_R16G16B16A16_SNORM
        case .rgba16Uint:       return VK_FORMAT_R16G16B16A16_UINT
        case .rgba16Sint:       return VK_FORMAT_R16G16B16A16_SINT
        case .rgba16Float:      return VK_FORMAT_R16G16B16A16_SFLOAT

        case .rgba32Uint:       return VK_FORMAT_R32G32B32A32_UINT
        case .rgba32Sint:       return VK_FORMAT_R32G32B32A32_SINT
        case .rgba32Float:      return VK_FORMAT_R32G32B32A32_SFLOAT

        case .depth32Float:     return VK_FORMAT_D32_SFLOAT
        case .stencil8:         return VK_FORMAT_S8_UINT

        case .depth32Float_stencil8:    return VK_FORMAT_D32_SFLOAT_S8_UINT

        case .invalid:          return VK_FORMAT_UNDEFINED
        }
    }
}

#endif //if ENABLE_VULKAN
