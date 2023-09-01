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
    case modelViewProjectionMatrix
    case inverseModelViewProjectionMatrix
    case skeletalNodeTransformArray
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
    let set: Int
    let binding: Int
    let offset: Int

    var isPushConstant: Bool { 
        self.set == -1 && self.binding == -1
    }

    static func pushConstant(offset: Int) -> Self {
        .init(set: -1, binding: -1, offset: offset)
    }
}
