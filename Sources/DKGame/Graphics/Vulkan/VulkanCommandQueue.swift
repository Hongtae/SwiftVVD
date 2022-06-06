#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanCommandQueue: CommandQueue {

    public let device: GraphicsDevice
    public let flags: CommandQueueFlags

    public let queue: VkQueue
    let family: VulkanQueueFamily

    private let lock = NSLock()

    public init(device: VulkanGraphicsDevice, family: VulkanQueueFamily, queue: VkQueue) {

        let queueFlags = family.properties.queueFlags

        let copy = (queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0
        let compute = (queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0
        let render = (queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0

        var flags: CommandQueueFlags = []
        if copy {
            flags.insert(.copy)
        }
        if render {
            flags.insert(.render)
        }
        if compute {
            flags.insert(.compute)
        }
        self.flags = flags
        self.device = device
        self.family = family
        self.queue = queue
    }

    deinit {
        vkQueueWaitIdle(self.queue)
        self.family.recycle(queue: self.queue)
    }

    public func makeCommandBuffer() -> CommandBuffer? {
        let device = self.device as! VulkanGraphicsDevice
        var commandPoolCreateInfo = VkCommandPoolCreateInfo()
        commandPoolCreateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        commandPoolCreateInfo.queueFamilyIndex = self.family.familyIndex
        commandPoolCreateInfo.flags = UInt32(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue)

        var commandPool: VkCommandPool? = nil
        let err = vkCreateCommandPool(device.device, &commandPoolCreateInfo, device.allocationCallbacks, &commandPool)
        if err == VK_SUCCESS {
            return VulkanCommandBuffer(pool: commandPool!, queue: self)
        }
        Log.err("vkCreateCommandPool failed: \(err)")
        return nil 
    }

    public func makeSwapChain(target: Window) async -> SwapChain? {
        guard self.family.supportPresentation else {
            Log.err("Vulkan WSI not supported with this queue family. Try to use other queue family!")
            return nil
        }
        if let swapchain = await VulkanSwapChain(queue: self, window: target) {
            //if await swapchain.setup() {  // <__ BUG???
            let r = await swapchain.setup()
            if r {
                return swapchain
            } else {
                Log.err("VulkanSwapChain.setup() failed.")
            }
        }
        return nil 
    }

    func submit(_ submits: [VkSubmitInfo], callback: (()->Void)?) -> Bool {
        let device = self.device as! VulkanGraphicsDevice
        var result: VkResult = VK_SUCCESS

        if let callback = callback {
            let fence: VkFence = device.fence(device: device)
            result = synchronizedBy(locking: self.lock) {
                vkQueueSubmit(self.queue, UInt32(submits.count), submits, fence)
            }
            if result == VK_SUCCESS {
                device.addCompletionHandler(fence: fence, op: callback)
            }
        } else {
            result = synchronizedBy(locking: self.lock) {
                vkQueueSubmit(self.queue, UInt32(submits.count), submits, nil)
            }
        }
        if result != VK_SUCCESS {
            Log.error("vkQueueSubmit failed: \(result)")
        }        
        return result == VK_SUCCESS 
    }
    
    @discardableResult
    func waitIdle() -> Bool { 
        synchronizedBy(locking: self.lock) { vkQueueWaitIdle(self.queue) } == VK_SUCCESS
    }
}
#endif //if ENABLE_VULKAN