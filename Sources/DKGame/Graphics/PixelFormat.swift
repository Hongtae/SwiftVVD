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

public extension PixelFormat {
    func isColorFormat() -> Bool {
        switch (self) {
            case .invalid, .depth32Float, .stencil8, .depth32Float_stencil8:
                return false
            default:
                return true
        }
    }
    func isDepthFormat() -> Bool {
        switch (self) {
            case .depth32Float, .depth32Float_stencil8:
                return true
            default:
                return false
        }
    }
    func isStencilFormat() -> Bool {
        switch (self) {
            case .stencil8, .depth32Float_stencil8:
                return true
            default:
                return false
        }
    }
    func bytesPerPixel() -> Int {
        switch (self) {
        // 8 bit formats
        case .r8Unorm, .r8Snorm, .r8Uint, .r8Sint:
            return 1

        // 16 bit formats
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float,
             .rg8Unorm, .rg8Snorm, .rg8Uint, .rg8Sint:
            return 2

        // 32 bit formats
        case .r32Uint, .r32Sint, .r32Float,
             .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint, .rg16Float,
             .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Snorm, .rgba8Uint, .rgba8Sint,
             .bgra8Unorm, .bgra8Unorm_srgb:
            return 4

        // packed 32 bit formats
        case .rgb10a2Unorm, .rgb10a2Uint,
             .rg11b10Float, .rgb9e5Float:
            return 4

        // 64 bit formats
        case .rg32Uint, .rg32Sint, .rg32Float,
             .rgba16Unorm, .rgba16Snorm, .rgba16Uint, .rgba16Sint, .rgba16Float:
            return 8

        // 128 bit formats
        case .rgba32Uint, .rgba32Sint, .rgba32Float:
            return 16

        // Depth
        case .depth32Float:
            return 4

        // Stencil (Uint)
        case .stencil8:
            return 1

        // Depth Stencil
        case .depth32Float_stencil8: // 32-depth: 8-stencil: 24-unused.
            return 8

        case .invalid:
            return 0
        }
        // return 0 // unsupported pixel format!
    }
}
