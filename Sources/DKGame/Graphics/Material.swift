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
        case buffer(_:[UInt8])
        case textures(_:[Texture])
        case samplers(_:[SamplerState])
        case combinedTextureSamplers(_:[CombinedTextureSampler])
        case intArray(_:[Int])
        case floatArray(_:[Float])
        case doubleArray(_:[Double])
    }
    public let value: Value
}

public class Material {
    public init() {
    }
}
