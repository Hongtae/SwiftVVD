//
//  File: Material.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public enum MaterialProperty {
    public typealias CombinedTextureSampler = (texture: Texture, sampler: SamplerState)

    case none
    case buffer(_: [UInt8])
    case textures(_: [Texture])
    case samplers(_: [SamplerState])
    case combinedTextureSamplers(_: [CombinedTextureSampler])
    case int8Array(_: [Int8])
    case uint8Array(_: [UInt8])
    case int16Array(_: [Int16])
    case uint16Array(_: [UInt16])
    case int32Array(_: [Int32])
    case uint32Array(_: [UInt32])
    case halfArray(_: [Float16])
    case floatArray(_: [Float])
    case doubleArray(_: [Double])


    public var count: Int {
        switch self {
        case .none:                             return 0
        case .buffer(let s):                    return s.count
        case .textures(let s):                  return s.count
        case .samplers(let s):                  return s.count
        case .combinedTextureSamplers(let s):   return s.count
        case .int8Array(let s):                 return s.count
        case .uint8Array(let s):                return s.count
        case .int16Array(let s):                return s.count
        case .uint16Array(let s):               return s.count
        case .int32Array(let s):                return s.count
        case .uint32Array(let s):               return s.count
        case .halfArray(let s):                 return s.count
        case .floatArray(let s):                return s.count
        case .doubleArray(let s):               return s.count
        }
    }

    public func buffer() -> [UInt8] {
        if case let .buffer(s) = self {
            return s
        }
        return []
    }

    public func integers() -> [Int] {
        switch self {
        case .int8Array(let s):     return s.map { Int($0) }
        case .uint8Array(let s):    return s.map { Int($0) }
        case .int16Array(let s):    return s.map { Int($0) }
        case .uint16Array(let s):   return s.map { Int($0) }
        case .int32Array(let s):    return s.map { Int($0) }
        case .uint32Array(let s):   return s.map { Int($0) }
        default:
            return []
        }
    }

    public func floats() -> [Float] {
        switch self {
        case .halfArray(let s):     return s.map { Float($0) }
        case .floatArray(let s):    return s.map { Float($0) }
        case .doubleArray(let s):   return s.map { Float($0) }
        default:
            return []
        }
    }

    public func doubles() -> [Double] {
        switch self {
        case .halfArray(let s):     return s.map { Double($0) }
        case .floatArray(let s):    return s.map { Double($0) }
        case .doubleArray(let s):   return s.map { Double($0) }
        default:
            return []
        }
    }

    public func textures() -> [Texture] {
        if case let .textures(t) = self {
            return t.map { $0 }
        }
        if case let .combinedTextureSamplers(t) = self {
            return t.map { $0.texture }
        }
        return []
    }

    public func samplers() -> [SamplerState] {
        if case let .samplers(s) = self {
            return s.map { $0 }
        }
        if case let .combinedTextureSamplers(s) = self {
            return s.map { $0.sampler }
        }
        return []
    }

    public func castIntegerArray<T: FixedWidthInteger>(as: T.Type) -> [T] {
        switch self {
        case .int8Array(let s):     return s.map { T($0) }
        case .uint8Array(let s):    return s.map { T($0) }
        case .int16Array(let s):    return s.map { T($0) }
        case .uint16Array(let s):   return s.map { T($0) }
        case .int32Array(let s):    return s.map { T($0) }
        case .uint32Array(let s):   return s.map { T($0) }
        case .halfArray(let s):     return s.map { T($0) }
        case .floatArray(let s):    return s.map { T($0) }
        case .doubleArray(let s):   return s.map { T($0) }
        default:
            return []
        }
    }

    public func castFloatArray<T: BinaryFloatingPoint>(as: T.Type) -> [T] {
        switch self {
        case .int8Array(let s):     return s.map { T($0) }
        case .uint8Array(let s):    return s.map { T($0) }
        case .int16Array(let s):    return s.map { T($0) }
        case .uint16Array(let s):   return s.map { T($0) }
        case .int32Array(let s):    return s.map { T($0) }
        case .uint32Array(let s):   return s.map { T($0) }
        case .halfArray(let s):     return s.map { T($0) }
        case .floatArray(let s):    return s.map { T($0) }
        case .doubleArray(let s):   return s.map { T($0) }
        default:
            return []
        }
    }

    public func castNumericArray<T: Numeric>(as: T.Type) -> [T] {
        if let t = T.self as? any BinaryFloatingPoint.Type {
            return castFloatArray(as: t).map { $0 as! T }
        }
        if let t = T.self as? any FixedWidthInteger.Type {
            return castIntegerArray(as: t).map { $0 as! T }
        }
        return []
    }

    public static func texture(_ value: Texture) -> Self {
        .textures([value])
    }

    public static func sampler(_ value: SamplerState) -> Self {
        .samplers([value])
    }

    public static func scalar(_ value: some BinaryFloatingPoint) -> Self {
        .scalars([value])
    }

    public static func color(_ value: Color) -> Self {
        .vector(value.vector4)
    }

    public static func combinedTextureSampler(_ value: CombinedTextureSampler) -> Self {
        .combinedTextureSamplers([value])
    }

    public static func scalars<V: BinaryFloatingPoint>(_ values: some Sequence<V>) -> Self {
        switch MemoryLayout<V>.size {
        case MemoryLayout<Float16>.size:
            return .halfArray(values.map { Float16($0) })
        case MemoryLayout<Float32>.size:
            return .floatArray(values.map { Float32($0) })
        default:
            return .doubleArray(values.map { Double($0) })
        }
    }

    public static func vector<V: Vector>(_ vector: V) -> Self {
        var scalars: [V.Scalar] = []
        for n in 0..<V.components {
            scalars.append(vector[n])
        }
        return .scalars(scalars)
    }

    public static func matrix<M: Matrix>(_ matrix: M) -> Self {
        var scalars: [Scalar] = []
        for r in 0..<M.numRows {
            for c in 0..<M.numColumns {
                scalars.append(matrix[r, c])
            }
        }
        return .scalars(scalars)
    }

    public static func data<T>(_ data: UnsafePointer<T>) -> Self {
        let p = UnsafeBufferPointer(start: data, count: 1)
        return .buffer(Array<UInt8>(UnsafeRawBufferPointer(p)))
    }

    public static func data(_ data: UnsafeRawBufferPointer) -> Self {
        .buffer(Array<UInt8>(data))
    }
}

public struct MaterialShaderMap {
    public typealias BindingLocation = ShaderBindingLocation

    public struct Function {
        public var function: ShaderFunction
        public var descriptors: [ShaderDescriptor]
        public init(function: ShaderFunction, descriptors: [ShaderDescriptor]) {
            self.function = function
            self.descriptors = descriptors
        }
    }

    public enum Semantic {
        case material(_:MaterialSemantic)
        case uniform(_:ShaderUniformSemantic)
    }

    public var functions: [Function]
    public var resourceSemantics: [BindingLocation: Semantic]
    public var inputAttributeSemantics: [Int: VertexAttributeSemantic]

    public init(functions: [Function], resourceSemantics: [BindingLocation : Semantic], inputAttributeSemantics: [Int : VertexAttributeSemantic]) {
        self.functions = functions
        self.resourceSemantics = resourceSemantics
        self.inputAttributeSemantics = inputAttributeSemantics
    }

    public func function(stage: ShaderStage) -> ShaderFunction? {
        if let fn = functions.first(where: { $0.function.stage == stage }) {
            return fn.function
        }
        return nil
    }

    public func descriptor(location: BindingLocation, stages: ShaderStageFlags) -> ShaderDescriptor? {
        for fn in functions {
            if stages.contains( ShaderStageFlags(stage: fn.function.stage) ) {
                if let descriptor = fn.descriptors.first(where: {
                    $0.set == location.set && $0.binding == location.binding
                }) {
                    return descriptor
                }
            }
        }
        return nil
    }
}

public class Material {
    public typealias Semantic = MaterialSemantic
    public typealias Property = MaterialProperty
    public typealias ShaderMap = MaterialShaderMap
    public typealias BindingLocation = ShaderBindingLocation

    public init(shaderMap: ShaderMap, name: String? = nil) {
        self.shader = shaderMap
        self.attachments = [RenderPassAttachment(format: .rgba8Unorm, blendState: .alphaBlend)]
        self.depthFormat = .depth24Unorm_stencil8
        self.properties = [:]
        self.userDefinedProperties = [:]
        self.name = name ?? ""
    }

    public var name: String
    public struct RenderPassAttachment {
        public var format: PixelFormat
        public var blendState: BlendState
        public init(format: PixelFormat, blendState: BlendState) {
            self.format = format
            self.blendState = blendState
        }
    }
    public var attachments: [RenderPassAttachment]
    public var depthFormat: PixelFormat
    public var triangleFillMode: TriangleFillMode = .fill
    public var cullMode: CullMode = .none
    public var frontFace: Winding = .clockwise

    public var properties: [Semantic: Property]
    public var userDefinedProperties: [BindingLocation: Property]
    public var shader: ShaderMap

    public var defaultTexture: Texture?
    public var defaultSampler: SamplerState?
}
