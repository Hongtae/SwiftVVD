//
//  File: MaterialSemantics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public enum MaterialSemantic {
    case userDefined
    case baseColor
    case baseColorTexture
    case metallic
    case roughness
    case metallicRoughnessTexture
    case normalScaleFactor
    case normalTexture
    case occlusionScale
    case occlusionTexture
    case emissiveFactor
    case emissiveTexture
}

public enum ShaderUniformSemantic {
    case modelMatrix
    case viewMatrix
    case projectionMatrix
    case viewProjectionMatrix
    case modelViewProjectionMatrix
    case inverseModelMatrix
    case inverseViewMatrix
    case inverseProjectionMatrix
    case inverseViewProjectionMatrix
    case inverseModelViewProjectionMatrix
    case transformMatrixArray
    case directionalLightIndex
    case directionalLightDirection
    case directionalLightDiffuseColor
    case spotLightIndex
    case spotLightPosition
    case spotLightAttenuation
    case spotLightColor
}

public enum VertexAttributeSemantic {
    case userDefined
    case position
    case normal
    case color
    case textureCoordinates
    case tangent
    case bitangent
    case blendIndices
    case blendWeights
}

public struct ShaderBindingLocation: Hashable {
    public let set: Int
    public let binding: Int
    public let offset: Int

    public init(set: Int, binding: Int, offset: Int) {
        self.set = set
        self.binding = binding
        self.offset = offset
    }
    
    public var isPushConstant: Bool {
        self.set == -1 && self.binding == -1
    }

    public static func pushConstant(offset: Int) -> Self {
        .init(set: -1, binding: -1, offset: offset)
    }
}
