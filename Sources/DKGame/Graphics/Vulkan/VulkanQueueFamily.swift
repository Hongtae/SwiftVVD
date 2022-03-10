import Vulkan
import Foundation

public class VulkanQueueFamily {

    public let familyIndex: UInt32
    public let supportPresentation: Bool

    public let properties: VkQueueFamilyProperties
    public var freeQueues: [VkQueue] = []

    public init(device: VkDevice, index: UInt32, count: UInt32, properties: VkQueueFamilyProperties, presentationSupport: Bool) {
        self.familyIndex = index
        self.supportPresentation = presentationSupport
        self.properties = properties
    }

    public func makeCommandQueue(device: VulkanGraphicsDevice) -> CommandQueue? {
        return nil
    }

    public func recycle(queue: VkQueue) {

    }

    deinit {
        
    }
}
