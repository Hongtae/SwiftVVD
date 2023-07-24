//
//  File: VulkanShaderModule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanShaderModule: ShaderModule {
    public let device: GraphicsDevice
    public let module: VkShaderModule
    public let functionNames: [String]

    public let stage: ShaderStage
    public let inputAttributes: [ShaderAttribute]
    public let pushConstantLayouts: [ShaderPushConstantLayout]
    public let resources: [ShaderResource]
    public let descriptors: [ShaderDescriptor]

    public init(device: VulkanGraphicsDevice, module: VkShaderModule, shader: Shader) {
        self.device = device
        self.module = module

        self.stage = shader.stage
        self.functionNames = shader.functionNames
        self.pushConstantLayouts = shader.pushConstantLayouts
        self.descriptors = shader.descriptors
        self.inputAttributes = shader.inputAttributes
        self.resources = shader.resources
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyShaderModule(device.device, module, device.allocationCallbacks)
    }

    public func makeFunction(name: String) -> ShaderFunction? {
        if self.functionNames.contains(name) {
            return VulkanShaderFunction(module: self, name: name, constantValues:[])
        }
        return nil
    }

    public func makeFunction(name: String, constantValues: [ShaderFunctionConstantValue]) -> ShaderFunction? {
        // TODO: verify spir-v specialization constant

        if self.functionNames.contains(name) {
            return VulkanShaderFunction(module: self, name: name, constantValues: constantValues)
        }
        return nil
    }
}

#endif //if ENABLE_VULKAN
