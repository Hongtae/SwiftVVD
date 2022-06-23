//
//  File: Mesh.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct VertexStreamDeclaration {
    let semantic: VertexStreamSemantic
    let format: VertexFormat
    let offset: Int // where the data begins, in bytes
    let name: String
}

public struct VertexBuffer {
    let declarations: [VertexStreamDeclaration]
    let buffer: Buffer
    let offset: Int // first vertex offset (bytes)
    let vertexSize: Int
    let vertexCount: Int
}

public class Mesh {
    public var vertexBuffers: [VertexBuffer] = []
    public var indexBuffer: Buffer?
    public var material: Material?

    public var primitiveType: PrimitiveType = .triangle
    public var cullMode: CullMode = .back
    public var frontFace: FrontFace = .ccw

    public var vertexStart: Int = 0
    public var vertexCount: Int = 0
    public var indexBufferByteOffset: Int = 0
    public var indexCount: Int = 0
    public var indexOffset: Int = 0
    public var vertexOffset: Int = 0
    public var indexType: IndexType = .uint16

    public enum BufferUsagePolicy {
        case useExternalBufferManually  // don't alloc buffer, use external resources manually.
        case singleBuffer               // single buffer per mesh
        case singleBufferPerSet         // single buffer per descriptor-set
        case singleBufferPerResource    // separated buffers for each resources
    }

    public var bufferProperties: [String: [Material.BufferInfo]] = [:]
    public var textureProperties: [String: [Texture]] = [:]
    public var samplerProperties: [String: [SamplerState]] = [:]
    public var structProperties: [String: [Material.StructProperty]] = [:]

    var pipelineReflection: PipelineReflection?
    var resourceBindings: [Material.ResourceBinding] = []
    var pushConstants: [Material.PushConstantData] = []

    public init() {

    }
}
