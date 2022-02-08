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
