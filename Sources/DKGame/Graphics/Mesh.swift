//
//  File: Mesh.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public class Submesh {
    public var material: Material?

    public struct VertexAttribute {
        let semantic: VertexAttributeSemantic
        let format: VertexFormat
        let offset: Int
        let name: String
    }
    public struct VertexBuffer {
        let byteOffset: Int
        let byteStride: Int
        let vertexCount: Int
        let buffer: Buffer
        let attributes: [VertexAttribute]
    }
    public var vertexBuffers: [VertexBuffer]
    public var indexBuffer: Buffer?
    public var indexBufferByteOffset: Int = 0
    public var indexBufferBaseVertexIndex: Int = 0
    public var vertexStart: Int = 0
    public var indexCount: Int
    public var indexType: IndexType
    public var primitiveType: PrimitiveType
    
    public enum BufferUsagePolicy {
        case useExternalBufferManually
        case singleBuffer
        case singleBufferPerSet
        case singleBufferPerResource
    }

    public init() {
        self.indexCount = 0
        self.indexType = .uint16
        self.vertexBuffers = []
        self.primitiveType = .triangle
    }

    var vertexDescriptor: VertexDescriptor {
        fatalError()
    }

    func initResources(device: GraphicsDevice, bufferPolicy: BufferUsagePolicy) -> Bool {
        false
    }

    func buildPipelineState(device: GraphicsDevice, reflection: UnsafeMutablePointer<PipelineReflection>? = nil) -> Bool {
        false
    }
    func updateShadingProperties(sceneState: SceneState) {
    }

    func encodeRenderCommand(encoder: RenderCommandEncoder, numInstances: Int, baseInstance: Int) -> Bool {
        false
    }
    func enumerateVertexBufferContent(semantic: VertexAttributeSemantic, queue: CommandQueue,
                                      handler: (_:UnsafeRawBufferPointer, _:VertexFormat, Int)->Void) {

    }
}

public struct Mesh {

    var submeshes: [Submesh] = []
}
