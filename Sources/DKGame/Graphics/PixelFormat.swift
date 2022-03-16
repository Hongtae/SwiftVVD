public enum PixelFormat {
    case invalid    

    // 8 bit formats
    case r8Unorm
    case r8Snorm
    case r8Uint
    case r8Sint    

    // 16 bit formats
    case r16Unorm
    case r16Snorm
    case r16Uint
    case r16Sint
    case r16Float    

    case rg8Unorm
    case rg8Snorm
    case rg8Uint
    case rg8Sint    

    // 32 bit formats
    case r32Uint
    case r32Sint
    case r32Float    

    case rg16Unorm
    case rg16Snorm
    case rg16Uint
    case rg16Sint
    case rg16Float    

    case rgba8Unorm
    case rgba8Unorm_srgb
    case rgba8Snorm
    case rgba8Uint
    case rgba8Sint    

    case bgra8Unorm
    case bgra8Unorm_srgb

    // packed 32 bit formats
    case rgb10a2Unorm
    case rgb10a2Uint    

    case rg11b10Float
    case rgb9e5Float    

    // 64 bit formats
    case rg32Uint
    case rg32Sint
    case rg32Float    

    case rgba16Unorm
    case rgba16Snorm
    case rgba16Uint
    case rgba16Sint
    case rgba16Float

    // 128 bit formats
    case rgba32Uint
    case rgba32Sint
    case rgba32Float

    // Depth
    case depth32Float    

    // Stencil (Uint)
    case stencil8    

    // Depth Stencil
    case depth32Float_stencil8 // 32-depth, 8-stencil, 24-unused.
}    

extension PixelFormat {
    public func isColorFormat() -> Bool {
        switch (self) {
            case .invalid:      fallthrough
            case .depth32Float: fallthrough
            case .stencil8:     fallthrough
            case .depth32Float_stencil8:    return false
            default:
                return true
        }
    }
    public func isDepthFormat() -> Bool {
        switch (self) {
            case .depth32Float: fallthrough
            case .depth32Float_stencil8:    return true
            default:
                return false
        }
    }
    public func isStencilFormat() -> Bool {
        if self == .stencil8 || self == .depth32Float_stencil8 {
            return true
        }
        return false
    }
    public func bytesPerPixel() -> Int {
        switch (self) {
            // 8 bit formats
            case .r8Unorm:      fallthrough
            case .r8Snorm:      fallthrough
            case .r8Uint:       fallthrough
            case .r8Sint:       return 1

            // 16 bit formats
            case .r16Unorm:     fallthrough
            case .r16Snorm:     fallthrough
            case .r16Uint:      fallthrough
            case .r16Sint:      fallthrough
            case .r16Float:     fallthrough
        
            case .rg8Unorm:     fallthrough
            case .rg8Snorm:     fallthrough
            case .rg8Uint:      fallthrough
            case .rg8Sint:      return 2

                // 32 bit formats
            case .r32Uint:          fallthrough
            case .r32Sint:          fallthrough
            case .r32Float:         fallthrough

            case .rg16Unorm:        fallthrough
            case .rg16Snorm:        fallthrough
            case .rg16Uint:         fallthrough
            case .rg16Sint:         fallthrough
            case .rg16Float:        fallthrough

            case .rgba8Unorm:       fallthrough
            case .rgba8Unorm_srgb:  fallthrough
            case .rgba8Snorm:       fallthrough
            case .rgba8Uint:        fallthrough
            case .rgba8Sint:        fallthrough

            case .bgra8Unorm:       fallthrough
            case .bgra8Unorm_srgb:  fallthrough  

                // packed 32 bit formats
            case .rgb10a2Unorm:     fallthrough
            case .rgb10a2Uint:      fallthrough
            
            case .rg11b10Float:     fallthrough
            case .rgb9e5Float:      return 4
    
            // 64 bit formats
            case .rg32Uint:         fallthrough
            case .rg32Sint:         fallthrough
            case .rg32Float:        fallthrough

            case .rgba16Unorm:      fallthrough
            case .rgba16Snorm:      fallthrough
            case .rgba16Uint:       fallthrough
            case .rgba16Sint:       fallthrough
            case .rgba16Float:      return 8

            // 128 bit formats
            case .rgba32Uint:       fallthrough
            case .rgba32Sint:       fallthrough
            case .rgba32Float:      return 16

            // Depth
            case .depth32Float:     return 4

            // Stencil (Uint)
            case .stencil8:         return 1

            // Depth Stencil
            case .depth32Float_stencil8: // 32-depth: 8-stencil: 24-unused.
                return 8

            case .invalid:          return 0
        }
        // return 0 // unsupported pixel format!
    }
}
