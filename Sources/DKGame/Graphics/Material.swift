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
    func samplerResource(_: ShaderResource) -> [SamplerState]

    func write(structPath: String, element: ShaderResourceStructMember, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool
    func write(structPath: String, structSize: Int, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool
}

class ChainedMaterialResourceBinder: MaterialResourceBinder {
    let first: MaterialResourceBinder
    let second: MaterialResourceBinder
    init(_ first: MaterialResourceBinder, _ second: MaterialResourceBinder) {
        self.first = first
        self.second = second
    }
    func bufferResource(_ resource: ShaderResource) -> [Material.BufferInfo] {
        let value = first.bufferResource(resource)
        if value.isEmpty == false { return value }
        return second.bufferResource(resource)
    }
    func textureResource(_ resource: ShaderResource) -> [Texture] {
        let value = first.textureResource(resource)
        if value.isEmpty == false { return value }
        return second.textureResource(resource)
    }
    func samplerResource(_ resource: ShaderResource) -> [SamplerState] {
        let value = first.samplerResource(resource)
        if value.isEmpty == false { return value }
        return second.samplerResource(resource)
    }
    func write(structPath: String, element: ShaderResourceStructMember, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool {
        if first.write(structPath: structPath, element: element, arrayIndex: arrayIndex, writer: writer) {
            return true
        }
        return second.write(structPath: structPath, element: element, arrayIndex: arrayIndex, writer: writer)
    }
    func write(structPath: String, structSize: Int, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool {
        if first.write(structPath: structPath, structSize: structSize, arrayIndex: arrayIndex, writer: writer) {
            return true
        }
        return second.write(structPath: structPath, structSize: structSize, arrayIndex: arrayIndex, writer: writer)
    }
}

public extension MaterialResourceBinder {
    static func makeChained(_ first: MaterialResourceBinder, _ second: MaterialResourceBinder)-> MaterialResourceBinder {
        return ChainedMaterialResourceBinder(first, second)
    }
}

fileprivate func makeBufferWriter(buffer: UnsafeMutableRawPointer, length bufferLength: Int, offset: Int, allowPatialWrites: Bool = true) -> MaterialResourceBufferWriter {
    if allowPatialWrites {
        return { (data: UnsafeRawPointer, length: Int) -> Int in
            if bufferLength > offset && length > 0 {
                let s = min(bufferLength - offset, length)
                buffer.advanced(by: offset).copyMemory(from: data, byteCount: s)
                return s
            }
            return 0
        }
    }
    return { (data: UnsafeRawPointer, length: Int) -> Int in
        if length + offset <= bufferLength && length > 0 {
            buffer.advanced(by: offset).copyMemory(from: data, byteCount: length)
            return length
        }
        return 0
    }
}

struct ShaderResourceStructMemberBinder {
    let member: ShaderResourceStructMember
    let parentPath: String
    let arrayIndex: Int
    let offset: Int
    let buffer: UnsafeMutableRawPointer
    let bufferLength: Int

    func bind(_ binder: MaterialResourceBinder, recursive: Bool = true) -> Int {
        let path = "\(parentPath).\(member.name)"
        let type = member.dataType
        let memberOffset = Int(member.offset) + offset

        if memberOffset >= bufferLength { return 0} // Insufficient buffer

        let writer = makeBufferWriter(buffer: buffer, length: bufferLength, offset: memberOffset)

        let bound =  binder.write(structPath: path, element: member, arrayIndex: arrayIndex, writer: writer)

        var memberBounds = 0
        if bound == false || recursive {
            for m in member.members {
                memberBounds += ShaderResourceStructMemberBinder(member: m,
                    parentPath: path,
                    arrayIndex: arrayIndex,
                    offset: offset + Int(m.offset),
                    buffer: buffer, bufferLength: bufferLength).bind(binder, recursive: recursive)
            }
        }
        if bound {
            return type.size()
        }
        return memberBounds
    }
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
        var data: [UInt8]
    }

    public var colorAttachments: [RenderPipelineColorAttachmentDescriptor] = []
    public var depthStencilAttachmentPixelFormat: PixelFormat = .invalid
    public var depthStencilDescriptor: DepthStencilDescriptor = .init()

    public var triangleFillMode: TriangleFillMode = .fill
    public var depthClipMode: DepthClipMode = .clip

    public init() {
    }

    public func bindResource(set: inout ResourceBindingSet, customBinder: MaterialResourceBinder?) -> Bool {
        return false
    }

    public func bindResource(data pc: inout PushConstantData, customBinder: MaterialResourceBinder?) -> Bool {
        let binder = makePropertyBinder(withCustomBinder: customBinder)

        var structSize = Int(pc.layout.offset + pc.layout.size)
        pc.layout.members.forEach { structSize = max(structSize, Int($0.offset + $0.size)) }
        pc.data = .init(repeating: 0, count: structSize)

        var bound: Bool = pc.data.withUnsafeMutableBytes {
            let writer = makeBufferWriter(buffer: $0.baseAddress!, length: $0.count, offset: 0)
            return binder.write(structPath: pc.layout.name,
                                structSize: structSize,
                                arrayIndex: 0,
                                writer: writer)
        }
        var memberBounds = 0
        for member in pc.layout.members {
            if member.offset < pc.layout.offset ||
            member.offset >= pc.layout.offset + pc.layout.size { continue }

            let s = pc.data.withUnsafeMutableBytes { (buffer) -> Int in
                return ShaderResourceStructMemberBinder(member: member,
                    parentPath: pc.layout.name,
                    arrayIndex: 0,
                    offset: 0,
                    buffer: buffer.baseAddress!,
                    bufferLength: structSize).bind(binder, recursive: true)
            }

            memberBounds += s
            if s == 0 && bound == false {
                let path = "\(pc.layout.name).\(member.name)"
                Log.err("Material error: Cannot bind struct resource: \(path)")
            }
        }
        if memberBounds == pc.layout.size {
            bound = true
        }
        return bound
    }

    public func makePropertyBinder(withCustomBinder binder: MaterialResourceBinder? = nil) -> MaterialResourceBinder {
        class MaterialPropertyBinder: MaterialResourceBinder {
            unowned let material: Material
            init(material: Material) {
                self.material = material
            }
            func bufferResource(_ resource: ShaderResource) -> [Material.BufferInfo] {
                if let value = material.bufferResourceProperties[ResourceIndex(set: resource.set, binding: resource.binding)] {
                    if value.isEmpty == false { return value }
                }
                if let value = material.bufferProperties[resource.name] {
                    if value.isEmpty == false { return value }
                }
                return []
            }
            func textureResource(_ resource: ShaderResource) -> [Texture] {
                if let value = material.textureResourceProperties[ResourceIndex(set: resource.set, binding: resource.binding)] {
                    if value.isEmpty == false { return value }
                }
                if let value = material.textureProperties[resource.name] {
                    if value.isEmpty == false { return value }
                }
                return []
            }
            func samplerResource(_ resource: ShaderResource) -> [SamplerState] {
                if let value = material.samplerResourceProperties[ResourceIndex(set: resource.set, binding: resource.binding)] {
                    if value.isEmpty == false { return value }
                }
                if let value = material.samplerProperties[resource.name] {
                    if value.isEmpty == false { return value }
                }
                return []
            }
            func write(structPath: String, element: ShaderResourceStructMember, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool {
                if let value = material.structProperties[structPath] {
                    assert(element.size > 0)

                    let elementSize = Int(element.size)
                    let offset = elementSize * arrayIndex

                    if value.data.count > offset {
                        let size = min(value.data.count - offset, elementSize)
                        return value.data.withUnsafeBytes {
                            return writer($0.baseAddress!.advanced(by: offset), size) == size
                        }
                    }
                }
                return false
            }
            func write(structPath: String, structSize: Int, arrayIndex: Int, writer: MaterialResourceBufferWriter) -> Bool {
                if let value = material.structProperties[structPath] {
                    assert(structSize > 0)

                    let offset = structSize * arrayIndex

                    if value.data.count > offset {
                        let size = min(value.data.count - offset, structSize)
                        return value.data.withUnsafeBytes {
                            return writer($0.baseAddress!.advanced(by: offset), size) == size
                        }
                    }
                }
                return false
            }
        }
        if let binder = binder {
            return ChainedMaterialResourceBinder(binder, MaterialPropertyBinder(material: self))
        }
        return MaterialPropertyBinder(material: self)
    }
}
