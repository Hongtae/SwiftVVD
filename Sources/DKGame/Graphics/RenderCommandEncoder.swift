//
//  File: RenderCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public enum VisibilityResultMode {
    case disabled
    case boolean
    case counting
}

public struct Viewport {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var nearZ: Double
    public var farZ: Double

    public init(x: Double,
                y: Double,
                width: Double,
                height: Double,
                nearZ: Double,
                farZ: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.nearZ = nearZ
        self.farZ = farZ
    }
}

public protocol RenderCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: Int)
    func setViewport(_: Viewport)
    func setRenderPipelineState(_: RenderPipelineState)

    func setVertexBuffer(_: Buffer, offset: Int, index: Int)
    func setVertexBuffers(_: [Buffer], offsets: [Int], index: Int)

    func setDepthStencilState(_: DepthStencilState?)
    func setDepthClipMode(_: DepthClipMode)
    func setCullMode(_: CullMode)
    func setFrontFacing(_: Winding)

    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float)
    func setStencilReferenceValue(_: UInt32)
    func setStencilReferenceValues(front: UInt32, back: UInt32)
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D)

    func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int)
    func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)
}
