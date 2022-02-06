public enum BlendFactor {
	case zero
	case one
	case sourceColor
	case oneMinusSourceColor
	case sourceAlpha
	case oneMinusSourceAlpha
	case destinationColor
	case oneMinusDestinationColor
	case destinationAlpha
	case oneMinusDestinationAlpha
	case sourceAlphaSaturated
	case blendColor
	case oneMinusBlendColor
	case blendAlpha
	case oneMinusBlendAlpha
}

public enum BlendOperation {
    case add
    case subtract
    case reverseSubtract
    case min
    case max
}

public enum ColorWriteMask : UInt8 {
    case none = 0
    case red = 8
    case green = 4
    case blue = 2
    case alpha = 1
    case all = 15
}

public struct BlendState {
    public var enabled : Bool = false 

    public var sourceRGBBlendFactor : BlendFactor = .one
    public var sourceAlphaBlendFactor : BlendFactor = .one

    public var destinationRGBBlendFactor : BlendFactor = .zero
    public var destinationAlphaBlendFactor : BlendFactor = .zero

    public var rgbBlendOperation : BlendOperation = .add
    public var alphaBlendOperation : BlendOperation = .add

    public var writeMask : ColorWriteMask = .all    
}
