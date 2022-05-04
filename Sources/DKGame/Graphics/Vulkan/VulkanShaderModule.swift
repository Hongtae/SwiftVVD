#if ENABLE_VULKAN
import Vulkan
import Foundation

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
            return VulkanShaderFunction(module: self, name: name, specializationValues:[])
        }
        return nil
    }

    public func makeFunction(name: String, specializedValues: [ShaderSpecialization]) -> ShaderFunction? {
        // TODO: verify spir-v specialization constant
        return nil
    }
}

#endif //if ENABLE_VULKAN
