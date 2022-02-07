public enum PixelFormat {
    case unknown    

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

    case rG8Unorm
    case rG8Snorm
    case rG8Uint
    case rG8Sint    

    // 32 bit formats
    case r32Uint
    case r32Sint
    case r32Float    

    case rG16Unorm
    case rG16Snorm
    case rG16Uint
    case rG16Sint
    case rG16Float    

    case rGBA8Unorm
    case rGBA8Unorm_sRGB
    case rGBA8Snorm
    case rGBA8Uint
    case rGBA8Sint    

    case bGRA8Unorm
    case bGRA8Unorm_sRGB    

    // packed 32 bit formats
    case rGB10A2Unorm
    case rGB10A2Uint    

    case rG11B10Float
    case rGB9E5Float    

    // 64 bit formats
    case rG32Uint
    case rG32Sint
    case rG32Float    

    case rGBA16Unorm
    case rGBA16Snorm
    case rGBA16Uint
    case rGBA16Sint
    case rGBA16Float    

    // 128 bit formats
    case rGBA32Uint
    case rGBA32Sint
    case rGBA32Float    

    // Depth
    case d32Float    

    // Stencil (Uint)
    case s8    

    // Depth Stencil
    case d32FloatS8 // 32-depth, 8-stencil, 24-unused.
}    
