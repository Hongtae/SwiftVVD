//
//  File: DepthStencil.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

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
    public var stencilCompareFunction: CompareFunction = .always
    public var stencilFailureOperation: StencilOperation = .keep
    public var depthFailOperation: StencilOperation = .keep
    public var depthStencilPassOperation: StencilOperation = .keep

    public var readMask: UInt32 = 0xffffffff
    public var writeMask: UInt32 = 0xffffffff

    public init(stencilCompareFunction: CompareFunction = .always,
                stencilFailureOperation: StencilOperation = .keep,
                depthFailOperation: StencilOperation = .keep,
                depthStencilPassOperation: StencilOperation = .keep,
                readMask: UInt32 = 0xffffffff,
                writeMask: UInt32 = 0xffffffff) {
        self.stencilCompareFunction = stencilCompareFunction
        self.stencilFailureOperation = stencilFailureOperation
        self.depthFailOperation = depthFailOperation
        self.depthStencilPassOperation = depthStencilPassOperation
        self.readMask = readMask
        self.writeMask = writeMask
    }
}

public struct DepthStencilDescriptor {
    public var depthCompareFunction: CompareFunction
    public var frontFaceStencil: StencilDescriptor
    public var backFaceStencil: StencilDescriptor
    public var isDepthWriteEnabled: Bool

    public init(depthCompareFunction: CompareFunction = .always,
                frontFaceStencil: StencilDescriptor = .init(),
                backFaceStencil: StencilDescriptor = .init(),
                isDepthWriteEnabled: Bool = false) {
        self.depthCompareFunction = depthCompareFunction
        self.frontFaceStencil = frontFaceStencil
        self.backFaceStencil = backFaceStencil
        self.isDepthWriteEnabled = isDepthWriteEnabled
    }
}
