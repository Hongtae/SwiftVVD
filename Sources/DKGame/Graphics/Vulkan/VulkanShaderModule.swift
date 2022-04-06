#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanShaderModule: ShaderModule {
    public let device: GraphicsDevice
    public let module: VkShaderModule
    public let functionNames: [String]

    public init(device: VulkanGraphicsDevice, module: VkShaderModule, shader: Shader) {
        self.device = device
        self.module = module

        self.functionNames = []
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyShaderModule(device.device, module, device.allocationCallbacks)
    }

    public func makeFunction(name: String) -> ShaderFunction? {
        return nil
    }

    public func makeSpecializedFunction(name: String, specializedValues: [ShaderSpecialization]) -> ShaderFunction? {
        return nil
    }
}

#endif //if ENABLE_VULKAN
