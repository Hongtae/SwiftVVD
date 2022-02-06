public enum CompareFunction {
    case never
    case less
    case equal
    case lessEqual
    case greater
    case notEqual
    case greaterEqual
    case always
}

public enum StencilOperation {
    case keep
    case zero
    case replace
    case incrementClamp
    case decrementClamp
    case invert
    case incrementWrap
    case decrementWrap
}

public struct StencilDescriptor {
    var stencilCompareFunction: CompareFunction = .always
    var stencilFailureOperation: StencilOperation = .keep
    var depthFailOperation: StencilOperation = .keep
    var depthStencilPassOperation: StencilOperation = .keep

    var readMask: UInt32 = 0xffffffff
    var writeMask: UInt32 = 0xffffffff
}

public struct DepthStencilDescriptor {
    var depthCompareFunction: CompareFunction = .always
    var frontFaceStencil: StencilDescriptor
    var backFaceStencil: StencilDescriptor
    var depthWriteEnabled: Bool = false
}
