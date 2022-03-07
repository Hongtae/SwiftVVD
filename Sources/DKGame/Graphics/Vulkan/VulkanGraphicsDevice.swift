import Vulkan
import Foundation

public class VulkanGraphicsDevice : GraphicsDevice {

    public var name: String { "" }

    public let instance: VulkanInstance
    public let physicalDevice: VulkanPhysicalDeviceDescription
    // public let device: VkDevice

    public init?(instance: VulkanInstance,
                 physicalDevice: VulkanPhysicalDeviceDescription,
                 requiredExtensions: [String],
                 optionalExtensions: [String]) {

        self.instance = instance
        self.physicalDevice = physicalDevice

    }

    public func makeCommandQueue() -> CommandQueue? {
        return nil
    }
    public func makeShaderModule() -> ShaderModule? {
        return nil
    }
    public func makeBindingSet() -> ShaderBindingSet? {
        return nil
    }
    public func makeRenderPipelineState() -> RenderPipelineState? {
        return nil
    }
    public func makeComputePipelineState() -> ComputePipelineState? {
        return nil
    }
    public func makeBuffer() -> Buffer? {
        return nil
    }
    public func makeTexture() -> Texture? {
        return nil
    }
    public func makeSamplerState() -> SamplerState? {
        return nil
    }
    public func makeEvent() -> Event? {
        return nil
    }
    public func makeSemaphore() -> Semaphore? {
        return nil
    }
}
