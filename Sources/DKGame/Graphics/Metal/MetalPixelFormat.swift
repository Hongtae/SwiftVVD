#if ENABLE_METAL
import Foundation
import Metal

public extension PixelFormat {
    static func from(mtlPixelFormat format: MTLPixelFormat) -> PixelFormat {
        switch (format)
        {
        case .r8Unorm:                  return .r8Unorm
        case .r8Snorm:                  return .r8Snorm
        case .r8Uint:                   return .r8Uint
        case .r8Sint:                   return .r8Sint
        case .r16Unorm:                 return .r16Unorm
        case .r16Snorm:                 return .r16Snorm
        case .r16Uint:                  return .r16Uint
        case .r16Sint:                  return .r16Sint
        case .r16Float:                 return .r16Float
        case .rg8Unorm:                 return .rg8Unorm
        case .rg8Snorm:                 return .rg8Snorm
        case .rg8Uint:                  return .rg8Uint
        case .rg8Sint:                  return .rg8Sint
        case .r32Uint:                  return .r32Uint
        case .r32Sint:                  return .r32Sint
        case .r32Float:                 return .r32Float
        case .rg16Unorm:                return .rg16Unorm
        case .rg16Snorm:                return .rg16Snorm
        case .rg16Uint:                 return .rg16Uint
        case .rg16Sint:                 return .rg16Sint
        case .rg16Float:                return .rg16Float
        case .rgba8Unorm:               return .rgba8Unorm
        case .rgba8Unorm_srgb:          return .rgba8Unorm_srgb
        case .rgba8Snorm:               return .rgba8Snorm
        case .rgba8Uint:                return .rgba8Uint
        case .rgba8Sint:                return .rgba8Sint
        case .bgra8Unorm:               return .bgra8Unorm
        case .bgra8Unorm_srgb:          return .bgra8Unorm_srgb
        case .rgb10a2Unorm:             return .rgb10a2Unorm
        case .rgb10a2Uint:              return .rgb10a2Uint
        case .rg11b10Float:             return .rg11b10Float
        case .rgb9e5Float:              return .rgb9e5Float
        case .rg32Uint:                 return .rg32Uint
        case .rg32Sint:                 return .rg32Sint
        case .rg32Float:                return .rg32Float
        case .rgba16Unorm:              return .rgba16Unorm
        case .rgba16Snorm:              return .rgba16Snorm
        case .rgba16Uint:               return .rgba16Uint
        case .rgba16Sint:               return .rgba16Sint
        case .rgba16Float:              return .rgba16Float
        case .rgba32Uint:               return .rgba32Uint
        case .rgba32Sint:               return .rgba32Sint
        case .rgba32Float:              return .rgba32Float
        case .depth32Float:             return .depth32Float
        case .stencil8:                 return .stencil8
        case .depth32Float_stencil8:    return .depth32Float_stencil8
        default:
            return .invalid
        }
    }

    func mtlPixelFormat() -> MTLPixelFormat {
        switch (self)
        {
        case .r8Unorm:                  return .r8Unorm
        case .r8Snorm:                  return .r8Snorm
        case .r8Uint:                   return .r8Uint
        case .r8Sint:                   return .r8Sint
        case .r16Unorm:                 return .r16Unorm
        case .r16Snorm:                 return .r16Snorm
        case .r16Uint:                  return .r16Uint
        case .r16Sint:                  return .r16Sint
        case .r16Float:                 return .r16Float
        case .rg8Unorm:                 return .rg8Unorm
        case .rg8Snorm:                 return .rg8Snorm
        case .rg8Uint:                  return .rg8Uint
        case .rg8Sint:                  return .rg8Sint
        case .r32Uint:                  return .r32Uint
        case .r32Sint:                  return .r32Sint
        case .r32Float:                 return .r32Float
        case .rg16Unorm:                return .rg16Unorm
        case .rg16Snorm:                return .rg16Snorm
        case .rg16Uint:                 return .rg16Uint
        case .rg16Sint:                 return .rg16Sint
        case .rg16Float:                return .rg16Float
        case .rgba8Unorm:               return .rgba8Unorm
        case .rgba8Unorm_srgb:          return .rgba8Unorm_srgb
        case .rgba8Snorm:               return .rgba8Snorm
        case .rgba8Uint:                return .rgba8Uint
        case .rgba8Sint:                return .rgba8Sint
        case .bgra8Unorm:               return .bgra8Unorm
        case .bgra8Unorm_srgb:          return .bgra8Unorm_srgb
        case .rgb10a2Unorm:             return .rgb10a2Unorm
        case .rgb10a2Uint:              return .rgb10a2Uint
        case .rg11b10Float:             return .rg11b10Float
        case .rgb9e5Float:              return .rgb9e5Float
        case .rg32Uint:                 return .rg32Uint
        case .rg32Sint:                 return .rg32Sint
        case .rg32Float:                return .rg32Float
        case .rgba16Unorm:              return .rgba16Unorm
        case .rgba16Snorm:              return .rgba16Snorm
        case .rgba16Uint:               return .rgba16Uint
        case .rgba16Sint:               return .rgba16Sint
        case .rgba16Float:              return .rgba16Float
        case .rgba32Uint:               return .rgba32Uint
        case .rgba32Sint:               return .rgba32Sint
        case .rgba32Float:              return .rgba32Float
        case .depth32Float:             return .depth32Float
        case .stencil8:                 return .stencil8
        case .depth32Float_stencil8:    return .depth32Float_stencil8
        default:
            return .invalid
        }
    }
}

#endif //if ENABLE_METAL
