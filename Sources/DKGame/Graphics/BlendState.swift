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

public struct ColorWriteMask: OptionSet, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let red      = ColorWriteMask(rawValue: 0x1 << 3)
    public static let green    = ColorWriteMask(rawValue: 0x1 << 2)
    public static let blue     = ColorWriteMask(rawValue: 0x1 << 1)
    public static let alpha    = ColorWriteMask(rawValue: 0x1)
    public static let all      = ColorWriteMask(rawValue: 0xf)
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
