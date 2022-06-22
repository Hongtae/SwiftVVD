//
//  File: Material.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public enum MaterialSemantic {
    case none
    case userDefined

    case modelMatrix, modelMatrixInverse
    case viewMatrix, viewMatrixInverse
    case projectionMatrix, projectionMatrixInverse
    case viewProjectionMatrix, viewProjectionMatrixInverse
    case modelViewMatrix, modelViewMatrixInverse
    case modelViewProjectionMatrix, modelViewProjectionMatrixInverse

    case linearTransformArray
    case affineTransformArray
    case positionArray

    case texture2D
    case texture3D
    case textureCube

    case ambientColor
    case cameraPosition
}

public enum VertexStreamSemantic {
    case userDefined

    case position
    case normal
    case color
    case texcoord
    case tangent
    case bitangent
    case boneIndices
    case boneWeights
}

public typealias MaterialResourceBufferWriter = (_: UnsafeRawPointer, _ byteCount: Int) -> Int

public protocol MaterialResourceBinder {
    func bufferResource(_: ShaderResource) -> [Material.BufferInfo]
    func textureResource(_: ShaderResource) -> [Texture]
    func SamplerResource(_: ShaderResource) -> [SamplerState]

    func writeStructElement(path: String, element: ShaderResourceStructMember, index: Int, writer: MaterialResourceBufferWriter) -> Bool
    func writeStruct(path: String, size: Int, index: Int, writer: MaterialResourceBufferWriter) -> Bool
}

public class Material {

    public struct ShaderTemplate {
        let shader: Shader
        let function: ShaderFunction

        let materialSemantics: [String: MaterialSemantic]
        let vertexStreamSemantics: [String: VertexStreamSemantic]
    }
    public var shaderTemplate: [ShaderStage: ShaderTemplate] = [:]

    public struct ResourceIndex: Hashable {
        let set: UInt32
        let binding: UInt32
    }
    public var resourceIndexNames: [ResourceIndex: String] = [:]

    public struct BufferInfo {
        let buffer: Buffer
        let offset: Int
        let length: Int
    }

    public var bufferResourceProperties: [ResourceIndex: [BufferInfo]] = [:]
    public var textureResourceProperties: [ResourceIndex: [Texture]] = [:]
    public var samplerResourceProperties: [ResourceIndex: [SamplerState]] = [:]

    public var bufferProperties: [String: [BufferInfo]] = [:]
    public var textureProperties: [String: [Texture]] = [:]
    public var samplerProperties: [String: [SamplerState]] = [:]

    public struct StructProperty {
        var data: [UInt8] = []
        mutating func set<T>(_ value: T) {
            withUnsafeBytes(of: value) {
                data = .init($0)
            }
        }
        mutating func append<T>(_ value: T) {
            withUnsafeBytes(of: value) {
                data.append(contentsOf: $0)
            }
        }
        mutating func set<T: Sequence>(_ value: T) where T.Element == UInt8 {
            data = .init(value)
        }
        mutating func append<T: Sequence>(_ value: T) where T.Element == UInt8 {
            data.append(contentsOf: value)
        }
    }
    public var structProperties: [String: StructProperty] = [:]


    public struct ResourceBinding {
        let resource: ShaderResource
        let binding: ShaderBinding
    }

    public struct ResourceBindingSet {
        let index: UInt32
        let bindings: ShaderBindingSet
        let resources: [ResourceBinding]
    }

    public struct PushConstantData {
        let layout: ShaderPushConstantLayout
        let data: [UInt8]
    }

    public var colorAttachments: [RenderPipelineColorAttachmentDescriptor] = []
    public var depthStencilAttachmentPixelFormat: PixelFormat = .invalid
    public var depthStencilDescriptor: DepthStencilDescriptor = .init()

    public var triangleFillMode: TriangleFillMode = .fill
    public var depthClipMode: DepthClipMode = .clip

    public init() {
    }
}
