//
//  File: Material.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct MaterialProperty {
    public let semantic: MaterialSemantic

    public typealias CombinedTextureSampler = (texture: Texture, sampler: SamplerState)
    public enum Value {
        case none
        case buffer(_:[UInt8])
        case textures(_:[Texture])
        case samplers(_:[SamplerState])
        case combinedTextureSamplers(_:[CombinedTextureSampler])
        case int8Array(_:[Int8])
        case uint8Array(_:[UInt8])
        case int16Array(_:[Int16])
        case uint16Array(_:[UInt16])
        case int32Array(_:[Int32])
        case uint32Array(_:[UInt32])
        case halfArray(_:[Float16])
        case floatArray(_:[Float])
        case doubleArray(_:[Double])
    }
    public let value: Value

    public var count: Int {
        switch value {
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
        if case let .buffer(s) = value {
            return s
        }
        return []
    }

    public func integers() -> [Int] {
        switch value {
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
        switch value {
        case .halfArray(let s):     return s.map { Float($0) }
        case .floatArray(let s):    return s.map { Float($0) }
        case .doubleArray(let s):   return s.map { Float($0) }
        default:
            return []
        }
    }

    public func textures() -> [Texture] {
        if case let .textures(t) = value {
            return t.map { $0 }
        }
        if case let .combinedTextureSamplers(t) = value {
            return t.map { $0.texture }
        }
        return []
    }

    public func samplers() -> [SamplerState] {
        if case let .samplers(s) = value {
            return s.map { $0 }
        }
        if case let .combinedTextureSamplers(s) = value {
            return s.map { $0.sampler }
        }
        return []
    }

    public func castArray<T>(as: T.Type) -> [T] {
        switch value {
        case .int8Array(let s):     return s.map { $0 as! T }
        case .uint8Array(let s):    return s.map { $0 as! T }
        case .int16Array(let s):    return s.map { $0 as! T }
        case .uint16Array(let s):   return s.map { $0 as! T }
        case .int32Array(let s):    return s.map { $0 as! T }
        case .uint32Array(let s):   return s.map { $0 as! T }
        case .halfArray(let s):     return s.map { $0 as! T }
        case .floatArray(let s):    return s.map { $0 as! T }
        case .doubleArray(let s):   return s.map { $0 as! T }
        default:
            return []
        }
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        switch value {
        case .buffer(let s):        return try s.withUnsafeBytes(body)
        case .int8Array(let s):     return try s.withUnsafeBytes(body)
        case .uint8Array(let s):    return try s.withUnsafeBytes(body)
        case .int16Array(let s):    return try s.withUnsafeBytes(body)
        case .uint16Array(let s):   return try s.withUnsafeBytes(body)
        case .int32Array(let s):    return try s.withUnsafeBytes(body)
        case .uint32Array(let s):   return try s.withUnsafeBytes(body)
        case .halfArray(let s):     return try s.withUnsafeBytes(body)
        case .floatArray(let s):    return try s.withUnsafeBytes(body)
        case .doubleArray(let s):   return try s.withUnsafeBytes(body)
        default:
            return try body(UnsafeRawBufferPointer(start: nil, count: 0))
        }
    }

    public init() {
        self.semantic = .userDefined
        self.value = .none
    }
    public init(semantic: MaterialSemantic, _ data: UnsafeRawBufferPointer) {
        self.semantic = semantic
        self.value = .buffer(.init(data))
    }
    public init(semantic: MaterialSemantic, _ texture: Texture) {
        self.semantic = semantic
        self.value = .textures([texture])
    }
    public init(semantic: MaterialSemantic, _ sampler: SamplerState) {
        self.semantic = semantic
        self.value = .samplers([sampler])
    }
    public init(semantic: MaterialSemantic, _ textureSampler: CombinedTextureSampler) {
        self.semantic = semantic
        self.value = .combinedTextureSamplers([textureSampler])
    }
    public init(semantic: MaterialSemantic, _ f: [Float]) {
        self.semantic = semantic
        self.value = .floatArray(f)
    }
    public init(semantic: MaterialSemantic, _ d: [Double]) {
        self.semantic = semantic
        self.value = .doubleArray(d)
    }
    public init<V: Vector>(semantic: MaterialSemantic, _ vector: V) {
        var scalars: [V.Scalar] = []
        for n in 0..<V.components {
            scalars.append(vector[n])
        }
        if MemoryLayout<V.Scalar>.size == MemoryLayout<Float>.size {
            self.init(semantic: semantic, scalars.map { Float($0) })
        } else {
            self.init(semantic: semantic, scalars.map { Double($0) })
        }
    }
    public init<M: Matrix>(semantic: MaterialSemantic, _ matrix: M) {
        var scalars: [Scalar] = []
        for r in 0..<M.numRows {
            for c in 0..<M.numCols {
                scalars.append(matrix[r, c])
            }
        }
        if MemoryLayout<Scalar>.size == MemoryLayout<Float>.size {
            self.init(semantic: semantic, scalars.map { Float($0) })
        } else {
            self.init(semantic: semantic, scalars.map { Double($0) })
        }
    }
}

public struct MaterialShaderMap {
    public typealias BindingLocation = ShaderBindingLocation

    public struct Function {
        public let function: ShaderFunction
        public let descriptors: [ShaderDescriptor]
    }

    public enum Semantic {
        case material(_:MaterialSemantic)
        case uniform(_:ShaderUniformSemantic)
    }

    public let functions: [Function]
    public let resourceSemantics: [BindingLocation: Semantic]
    public let inputAttributeSemantics: [Int: VertexAttributeSemantic]

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

    public init(shaderMap: ShaderMap) {
        self.shader = shaderMap
        self.attachments = [RenderPassAttachment(format: .rgba8Unorm, blendState: .alphaBlend)]
        self.depthFormat = .depth24Unorm_stencil8
        self.properties = [:]
        self.userDefinedProperties = [:]
        self.name = ""
    }

    public var name: String
    public struct RenderPassAttachment {
        public let format: PixelFormat
        public let blendState: BlendState
    }
    public var attachments: [RenderPassAttachment]
    public var depthFormat: PixelFormat
    public var triangleFillMode: TriangleFillMode = .fill
    public var cullMode: CullMode = .none
    public var frontFace: Winding = .clockwise

    public var properties: [Semantic: Property]
    public var userDefinedProperties: [BindingLocation: Property]
    public let shader: ShaderMap

    public var defaultTexture: Texture?
    public var defaultSampler: SamplerState?
}
