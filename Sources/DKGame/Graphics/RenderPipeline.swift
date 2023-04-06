//
//  File: RenderPipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct RenderPipelineColorAttachmentDescriptor {
    public var index: Int
    public var pixelFormat: PixelFormat
    public var blendState: BlendState

    public init(index: Int,
                pixelFormat: PixelFormat,
                blendState: BlendState) {
        self.index = index
        self.pixelFormat = pixelFormat
        self.blendState = blendState
    }
}

public enum PrimitiveType {
    case point
    case line
    case lineStrip
    case triangle
    case triangleStrip
}

public enum IndexType {
    case uint16
    case uint32
}

public enum TriangleFillMode {
    case fill
    case lines
}

public enum CullMode {
    case none
    case front
    case back
}

public enum Winding {
    case clockwise
    case counterClockwise
}

public enum DepthClipMode {
    case clip
    case clamp
}

public struct RenderPipelineDescriptor {
    public var vertexFunction: ShaderFunction?
    public var fragmentFunction: ShaderFunction?
    public var vertexDescriptor: VertexDescriptor
    public var colorAttachments: [RenderPipelineColorAttachmentDescriptor]
    public var depthStencilAttachmentPixelFormat: PixelFormat
    public var rasterizationEnabled: Bool

    public init(vertexFunction: ShaderFunction? = nil,
                fragmentFunction: ShaderFunction? = nil,
                vertexDescriptor: VertexDescriptor = .init(),
                colorAttachments: [RenderPipelineColorAttachmentDescriptor] = [],
                depthStencilAttachmentPixelFormat: PixelFormat = .invalid,
                rasterizationEnabled: Bool = true) {
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.vertexDescriptor = vertexDescriptor
        self.colorAttachments = colorAttachments
        self.depthStencilAttachmentPixelFormat = depthStencilAttachmentPixelFormat
        self.rasterizationEnabled = rasterizationEnabled
    }
}

public protocol RenderPipelineState {
    var device: GraphicsDevice { get }
}
