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

public struct ScissorRect {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public protocol RenderCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: Int)
    func setViewport(_: Viewport)
    func setScissorRect(_: ScissorRect)
    func setRenderPipelineState(_: RenderPipelineState)

    func setVertexBuffer(_: Buffer, offset: Int, index: Int)
    func setVertexBuffers(_: [Buffer], offsets: [Int], index: Int)

    func setDepthStencilState(_: DepthStencilState?)
    func setDepthClipMode(_: DepthClipMode)
    func setCullMode(_: CullMode)
    func setFrontFacing(_: Winding)
    func setTriangleFillMode(_: TriangleFillMode)

    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float)
    func setStencilReferenceValue(_: UInt32)
    func setStencilReferenceValues(front: UInt32, back: UInt32)
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D)

    func drawPrimitives(type: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int)
    func drawIndexedPrimitives(type: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)
}

public extension RenderCommandEncoder {
    func setViewport(frame: CGRect,
                     near: any BinaryFloatingPoint,
                     far: any BinaryFloatingPoint) {
        let frame = frame.standardized
        self.setViewport(Viewport(x: Double(frame.origin.x),
                                  y: Double(frame.origin.y),
                                  width: Double(frame.width),
                                  height: Double(frame.height),
                                  nearZ: Double(near), farZ: Double(far)))
    }

    func setScissorRect(_ rect: CGRect) {
        let rect = rect.standardized
        self.setScissorRect(ScissorRect(x: Int(rect.origin.x),
                                        y: Int(rect.origin.y),
                                        width: Int(rect.width),
                                        height: Int(rect.height)))
    }
}
