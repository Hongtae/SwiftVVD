#if ENABLE_VULKAN
import Vulkan
import Foundation

public class VulkanCopyCommandEncoder: VulkanCommandEncoder, CopyCommandEncoder {

    struct EncodingState {
    }

    class Encoder: VulkanCommandEncoder {
        unowned let commandBuffer: VulkanCommandBuffer

        var buffers: [Buffer] = []
        var textures: [Texture] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        typealias Command = (VkCommandBuffer, inout EncodingState)->Void
        var commands: [Command] = []
        var setupCommands: [Command] = []
        var cleanupCommands: [Command] = []

        init(commandBuffer: VulkanCommandBuffer) {
            self.commandBuffer = commandBuffer
            super.init()

            self.commands.reserveCapacity(self.initialNumberOfCommands)
            self.setupCommands.reserveCapacity(self.initialNumberOfCommands)
            self.cleanupCommands.reserveCapacity(self.initialNumberOfCommands)
        }

        override func encode(commandBuffer: VkCommandBuffer) -> Bool {
            var state = EncodingState()

            for cmd in self.setupCommands {
                cmd(commandBuffer, &state)
            }
            for cmd in self.commands {
                cmd(commandBuffer, &state)
            }
            for cmd in self.cleanupCommands {
                cmd(commandBuffer, &state)
            }
            return true
        }
    }

    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    public init(buffer: VulkanCommandBuffer) {   
        self.commandBuffer = buffer
        self.encoder = Encoder(commandBuffer: buffer)
    }

    public func reset(descriptor: RenderPassDescriptor) {   
        self.encoder = Encoder(commandBuffer: self.commandBuffer as! VulkanCommandBuffer)
    }

    public func endEncoding() {
        let commandBuffer = self.commandBuffer as! VulkanCommandBuffer
        commandBuffer.endEncoder(self.encoder!)
        self.encoder = nil
    }

    public var isCompleted: Bool { self.encoder == nil }

    public func waitEvent(_ event: Event) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue, flags: pipelineStages)
            self.encoder!.events.append(event)
        }
    }
    public func signalEvent(_ event: Event) {
        assert(event is VulkanSemaphore)
        if let semaphore = event as? VulkanSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: semaphore.nextWaitValue)
            self.encoder!.events.append(event)
        }
    }

    public func waitSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            let pipelineStages: VkPipelineStageFlags = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            self.encoder!.addWaitSemaphore(semaphore.semaphore, value: value, flags: pipelineStages)
            self.encoder!.semaphores.append(sema)
        }
    }
    public func signalSemaphoreValue(_ sema: Semaphore, value: UInt64) {
        assert(sema is VulkanTimelineSemaphore)
        if let semaphore = sema as? VulkanTimelineSemaphore {
            self.encoder!.addSignalSemaphore(semaphore.semaphore, value: value)
            self.encoder!.semaphores.append(sema)
        }
    }
    
    public func copy(from src: Buffer,
                     sourceOffset srcOffset: UInt64,
                     to dst: Buffer,
                     destinationOffset dstOffset: UInt64,
                     size: UInt64) {
        assert(src is VulkanBufferView)
        assert(dst is VulkanBufferView)

        let srcBuffer = (src as! VulkanBufferView).buffer!
        let dstBuffer = (dst as! VulkanBufferView).buffer!

        assert(srcBuffer.buffer != nil)
        assert(dstBuffer.buffer != nil)

        if srcOffset + size > srcBuffer.length || dstOffset + size > dstBuffer.length {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid buffer region");
            return
        }

        var region = VkBufferCopy(srcOffset: srcOffset, dstOffset: dstOffset, size: size)
        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdCopyBuffer(commandBuffer, srcBuffer.buffer, dstBuffer.buffer, 1, &region)
        }
        self.encoder!.commands.append(command)
        self.encoder!.buffers.append(src)
        self.encoder!.buffers.append(dst)
    }

    public func copy(from src: Buffer,
                     sourceOffset srcOffset: BufferImageOrigin,
                     to dst: Texture,
                     destinationOffset dstOffset: TextureOrigin,
                     size: TextureSize) {
        assert(src is VulkanBufferView)
        assert(dst is VulkanImageView)
        assert(srcOffset.offset % 4 == 0)

        let buffer = (src as! VulkanBufferView).buffer!
        let image = (dst as! VulkanImageView).image!

        let mipDimensions = TextureSize(
            width: max(image.width >> dstOffset.level, 1),
            height: max(image.height >> dstOffset.level, 1),
            depth: max(image.depth >> dstOffset.level, 1)
        )

        if dstOffset.x + size.width > mipDimensions.width ||
           dstOffset.y + size.height > mipDimensions.height ||
           dstOffset.z + size.depth > mipDimensions.depth {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid texture region")
            return
        }
        if size.width > srcOffset.imageWidth ||
           size.height > srcOffset.imageHeight {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid buffer region")
            return
        }

        let pixelFormat = image.pixelFormat
        let bufferLength = buffer.length
        let bytesPerPixel = pixelFormat.bytesPerPixel()
        assert(bytesPerPixel > 0)

        let requiredBufferLengthForCopy = UInt(srcOffset.imageWidth) * UInt(srcOffset.imageHeight) * UInt(size.depth) * UInt(bytesPerPixel) + srcOffset.offset
        if requiredBufferLengthForCopy > bufferLength {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: buffer is too small!")
            return
        }

        var region = VkBufferImageCopy()
        region.bufferOffset = VkDeviceSize(srcOffset.offset)
        region.bufferRowLength = srcOffset.imageWidth
        region.bufferImageHeight = srcOffset.imageHeight
        region.imageOffset = VkOffset3D(x: Int32(dstOffset.x), y: Int32(dstOffset.y), z: Int32(dstOffset.z))
        region.imageExtent = VkExtent3D(width: size.width, height: size.height, depth: size.depth)
        self.setupSubresource(&region.imageSubresource, origin: dstOffset, layerCount: 1, pixelFormat: pixelFormat)

        let queueFamilyIndex = self.encoder!.commandBuffer.queueFamily.familyIndex

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in

            image.setLayout(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                            accessMask: VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue),
                            stageBegin: UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue),
                            stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
                            queueFamilyIndex: queueFamilyIndex,
                            commandBuffer: commandBuffer)

            vkCmdCopyBufferToImage(commandBuffer,
                                   buffer.buffer,
                                   image.image,
                                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                   1, &region)
        }
        self.encoder!.commands.append(command)
        self.encoder!.buffers.append(src)
        self.encoder!.textures.append(dst)
    }

    public func copy(from src: Texture,
                     sourceOffset srcOffset: TextureOrigin,
                     to dst: Buffer,
                     destinationOffset dstOffset: BufferImageOrigin,
                     size: TextureSize) {
        assert(src is VulkanImageView)
        assert(dst is VulkanBufferView)
        assert(dstOffset.offset % 4 == 0)

        let image = (src as! VulkanImageView).image!
        let buffer = (dst as! VulkanBufferView).buffer!

        let mipDimensions = TextureSize(
            width: max(image.width >> srcOffset.level, 1),
            height: max(image.height >> srcOffset.level, 1),
            depth: max(image.depth >> srcOffset.level, 1)
        )
        if srcOffset.x + size.width > mipDimensions.width ||
           srcOffset.y + size.height > mipDimensions.height ||
           srcOffset.z + size.depth > mipDimensions.depth {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid texture region")
            return
        }
        if size.width > dstOffset.imageWidth ||
           size.height > dstOffset.imageHeight {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid buffer region")
            return
        }

        let pixelFormat = image.pixelFormat
        let bufferLength = buffer.length
        let bytesPerPixel = pixelFormat.bytesPerPixel()
        assert(bytesPerPixel > 0)   // Unsupported texture format!

        let requiredBufferLengthForCopy = UInt(dstOffset.imageWidth) * UInt(dstOffset.imageHeight) * UInt(size.depth) * UInt(bytesPerPixel) + dstOffset.offset
        if requiredBufferLengthForCopy > bufferLength {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: buffer is too small!")
            return
        }

        var region = VkBufferImageCopy()
        region.bufferOffset = VkDeviceSize(dstOffset.offset)
        region.bufferRowLength = dstOffset.imageWidth
        region.bufferImageHeight = dstOffset.imageHeight
        region.imageOffset = VkOffset3D(x: Int32(srcOffset.x), y: Int32(srcOffset.y), z: Int32(srcOffset.z))
        region.imageExtent = VkExtent3D(width: size.width, height: size.height, depth: size.depth)
        self.setupSubresource(&region.imageSubresource, origin: srcOffset, layerCount: 1, pixelFormat: pixelFormat)

        let queueFamilyIndex = self.encoder!.commandBuffer.queueFamily.familyIndex

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in

            image.setLayout(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                            accessMask: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
                            stageBegin: UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue),
                            stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
                            queueFamilyIndex: queueFamilyIndex,
                            commandBuffer: commandBuffer)

            vkCmdCopyImageToBuffer(commandBuffer,
                                   image.image,
                                   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                   buffer.buffer,
                                   1, &region)
        }
        self.encoder!.commands.append(command)
        self.encoder!.textures.append(src)
        self.encoder!.buffers.append(dst)
    }

    public func copy(from src: Texture,
                     sourceOffset srcOffset: TextureOrigin,
                     to dst: Texture,
                     destinationOffset dstOffset: TextureOrigin,
                     size: TextureSize) {
        assert(src is VulkanImageView)
        assert(dst is VulkanImageView)

        let srcImage = (src as! VulkanImageView).image!
        let dstImage = (dst as! VulkanImageView).image!

        let srcMipDimensions = TextureSize(
            width: max(srcImage.width >> srcOffset.level, 1),
            height: max(srcImage.height >> srcOffset.level, 1),
            depth: max(srcImage.depth >> srcOffset.level, 1)
        )
        let dstMipDimensions = TextureSize(
            width: max(dstImage.width >> dstOffset.level, 1),
            height: max(dstImage.height >> dstOffset.level, 1),
            depth: max(dstImage.depth >> dstOffset.level, 1)
        )

        if srcOffset.x + size.width > srcMipDimensions.width ||
           srcOffset.y + size.height > srcMipDimensions.height ||
           srcOffset.z + size.depth > srcMipDimensions.depth {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid source texture region")
            return
        }
        if dstOffset.x + size.width > dstMipDimensions.width ||
           dstOffset.y + size.height > dstMipDimensions.height ||
           dstOffset.z + size.depth > dstMipDimensions.depth {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid destination texture region")
            return
        }

        let srcPixelFormat = srcImage.pixelFormat
        let dstPixelFormat = dstImage.pixelFormat
        let srcBytesPerPixel = srcPixelFormat.bytesPerPixel()
        let dstBytesPerPixel = dstPixelFormat.bytesPerPixel()
        assert(srcBytesPerPixel > 0)    // Unsupported texture format!
        assert(dstBytesPerPixel > 0)    // Unsupported texture format!

        if srcBytesPerPixel != dstBytesPerPixel {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Incompatible pixel formats")
            return
        }

        var region = VkImageCopy()
        self.setupSubresource(&region.srcSubresource, origin: srcOffset, layerCount: 1, pixelFormat: srcPixelFormat)
        self.setupSubresource(&region.dstSubresource, origin: dstOffset, layerCount: 1, pixelFormat: dstPixelFormat)
        assert(region.srcSubresource.aspectMask != 0)
        assert(region.dstSubresource.aspectMask != 0)

        region.srcOffset = VkOffset3D(x: Int32(srcOffset.x), y: Int32(srcOffset.y), z: Int32(srcOffset.z))
        region.dstOffset = VkOffset3D(x: Int32(dstOffset.x), y: Int32(dstOffset.y), z: Int32(dstOffset.z))
        region.extent = VkExtent3D(width: size.width, height: size.height, depth: size.depth)

        let queueFamilyIndex = self.encoder!.commandBuffer.queueFamily.familyIndex

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in

            srcImage.setLayout(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               accessMask: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue),
                               stageBegin: UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue),
                               stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
                               queueFamilyIndex: queueFamilyIndex,
                               commandBuffer: commandBuffer)

            dstImage.setLayout(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                               accessMask: VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue),
                               stageBegin: UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue),
                               stageEnd: UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.rawValue),
                               queueFamilyIndex: queueFamilyIndex,
                               commandBuffer: commandBuffer)

            vkCmdCopyImage(commandBuffer,
                           srcImage.image,
                           VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           dstImage.image,
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           1, &region)
        }
        self.encoder!.commands.append(command)
        self.encoder!.textures.append(src)
        self.encoder!.textures.append(dst)
    }

    public func fill(buffer: Buffer, offset: UInt64, length: UInt64, value: UInt8) {
        assert(buffer is VulkanBufferView)
        let buf = (buffer as! VulkanBufferView).buffer!

        let bufferLength = buf.length
        if offset + length > bufferLength {
            Log.err("VulkanCopyCommandEncoder.\(#function) failed: Invalid buffer region")
            return       
        }

        let data: UInt32 = UInt32(value) << 24 | UInt32(value) << 16 | UInt32(value) << 8 | UInt32(value)

        let command = { (commandBuffer: VkCommandBuffer, state: inout EncodingState) in
            vkCmdFillBuffer(commandBuffer,
                            buf.buffer,
                            VkDeviceSize(offset),
                            VkDeviceSize(length),
                            data)
        }
        self.encoder!.commands.append(command)
        self.encoder!.buffers.append(buffer)
    }

    private func setupSubresource(_ subresource: inout VkImageSubresourceLayers,
                                  origin: TextureOrigin,
                                  layerCount: UInt32, 
                                  pixelFormat: PixelFormat) {
        if pixelFormat.isColorFormat() {
            subresource.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        } else {
            subresource.aspectMask = 0
            if pixelFormat.isDepthFormat() {
                subresource.aspectMask |= VkImageAspectFlags(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
            }
            if pixelFormat.isStencilFormat() {
                subresource.aspectMask |= VkImageAspectFlags(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
            }
        }
        subresource.mipLevel = origin.level
        subresource.baseArrayLayer = origin.layer
        subresource.layerCount = layerCount
    }

    private func setupSubresource(_ subresource: inout VkImageSubresourceRange,
                                  origin: TextureOrigin,
                                  layerCount: UInt32,
                                  levelCount: UInt32,
                                  pixelFormat: PixelFormat) {
        if pixelFormat.isColorFormat() {
            subresource.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        } else {
            subresource.aspectMask = 0
            if pixelFormat.isDepthFormat() {
                subresource.aspectMask |= VkImageAspectFlags(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
            }
            if pixelFormat.isStencilFormat() {
                subresource.aspectMask |= VkImageAspectFlags(VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
            }
        }
        subresource.baseMipLevel = origin.level
        subresource.baseArrayLayer = origin.layer
        subresource.layerCount = layerCount
        subresource.levelCount = levelCount
    }
}

#endif //if ENABLE_VULKAN
