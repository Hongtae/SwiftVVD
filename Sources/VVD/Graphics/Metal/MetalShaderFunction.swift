//
//  File: MetalShaderFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalShaderFunction: ShaderFunction {
    let stageInputAttributes: [ShaderAttribute]
    let functionConstants: [String : ShaderFunctionConstant]
    let functionName: String
    let stage: ShaderStage

    var device: GraphicsDevice { self.module.device }

    let function: MTLFunction
    let module: MetalShaderModule

    init(module: MetalShaderModule, function: MTLFunction, workgroupSize: MTLSize, name: String) {
        self.module = module
        self.function = function
        self.functionName = name

        self.functionConstants = function.functionConstantsDictionary.mapValues {
            ShaderFunctionConstant(name: $0.name,
                                   type: .from(mtlDataType: $0.type),
                                   index: $0.index,
                                   required: $0.required)
        }

        let stageInputAttrs: [AnyObject] = function.stageInputAttributes ?? []
        self.stageInputAttributes = stageInputAttrs.compactMap {
            if let attr = $0 as? MTLAttribute {
                return ShaderAttribute(name: attr.name,
                                       location: attr.attributeIndex,
                                       type: .from(mtlDataType: attr.attributeType),
                                       enabled: attr.isActive)
            }
            if let attr = $0 as? MTLVertexAttribute {
                return ShaderAttribute(name: attr.name,
                                       location: attr.attributeIndex,
                                       type: .from(mtlDataType: attr.attributeType),
                                       enabled: attr.isActive)
            }
            return nil
        }

        switch function.functionType {
        case .vertex:
            self.stage = .vertex
        case .fragment:
            self.stage = .fragment
        case .kernel:
            self.stage = .compute
        default:
            Log.err("Unknown shader type: \(function.functionType)")
            self.stage = .unknown
        }
    }
}
#endif //if ENABLE_METAL
