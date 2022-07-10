//
//  File: MetalShaderFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalShaderFunction: ShaderFunction {
    public let stageInputAttributes: [ShaderAttribute]
    public let functionConstants: [String : ShaderFunctionConstant]
    public let functionName: String
    public let stage: ShaderStage

    public var device: GraphicsDevice { self.module.device }

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

        self.stageInputAttributes = function.stageInputAttributes?.map {
            ShaderAttribute(name: $0.name,
                            location: $0.attributeIndex,
                            type: .from(mtlDataType: $0.attributeType),
                            enabled: $0.isActive)
        } ?? []

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
