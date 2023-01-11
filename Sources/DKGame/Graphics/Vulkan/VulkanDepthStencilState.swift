//
//  File: VulkanDepthStencilState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanDepthStencilState: DepthStencilState {
    public let device: GraphicsDevice

    var depthTestEnable: VkBool32
    var depthWriteEnable: VkBool32
    var depthCompareOp: VkCompareOp
    var depthBoundsTestEnable: VkBool32

    var front: VkStencilOpState
    var back: VkStencilOpState
    var stencilTestEnable: VkBool32

    public init(device: VulkanGraphicsDevice) {
        self.device = device

        self.depthTestEnable = VK_FALSE
        self.depthWriteEnable = VK_FALSE
        self.depthCompareOp = VK_COMPARE_OP_ALWAYS
        self.depthBoundsTestEnable = VK_FALSE
        self.front = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP,
                                      passOp: VK_STENCIL_OP_KEEP,
                                      depthFailOp: VK_STENCIL_OP_KEEP,
                                      compareOp: VK_COMPARE_OP_ALWAYS,
                                      compareMask: 0xffffffff,
                                      writeMask: 0xffffffff,
                                      reference: 0)
        self.back = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP,
                                     passOp: VK_STENCIL_OP_KEEP,
                                     depthFailOp: VK_STENCIL_OP_KEEP,
                                     compareOp: VK_COMPARE_OP_ALWAYS,
                                     compareMask: 0xffffffff,
                                     writeMask: 0xffffffff,
                                     reference: 0)
        self.stencilTestEnable = VK_FALSE
    }

    func bind(commandBuffer: VkCommandBuffer) {
        let frontFaceFlags = VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT.rawValue)
        let backFaceFlags = VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT.rawValue)

        vkCmdSetDepthTestEnable(commandBuffer, self.depthTestEnable)
        vkCmdSetStencilTestEnable(commandBuffer, self.stencilTestEnable) 

        vkCmdSetDepthCompareOp(commandBuffer, self.depthCompareOp)
        vkCmdSetDepthWriteEnable(commandBuffer, self.depthWriteEnable)
        vkCmdSetDepthBoundsTestEnable(commandBuffer, self.depthBoundsTestEnable)

        // front face stencil
        vkCmdSetStencilCompareMask(commandBuffer,
                                   frontFaceFlags,
                                   self.front.compareMask)
        vkCmdSetStencilWriteMask(commandBuffer,
                                 frontFaceFlags,
                                 self.front.writeMask)
        vkCmdSetStencilOp(commandBuffer,
                          frontFaceFlags,
                          self.front.failOp,
                          self.front.passOp,
                          self.front.depthFailOp,
                          self.front.compareOp)
        // back face stencil
        vkCmdSetStencilCompareMask(commandBuffer,
                                   backFaceFlags,
                                   self.back.compareMask)
        vkCmdSetStencilWriteMask(commandBuffer,
                                 backFaceFlags,
                                 self.back.writeMask)
        vkCmdSetStencilOp(commandBuffer,
                          backFaceFlags,
                          self.back.failOp,
                          self.back.passOp,
                          self.back.depthFailOp,
                          self.back.compareOp)
    }

    static func resetToDefault(commandBuffer: VkCommandBuffer) {
        let frontFaceFlags = VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT.rawValue)
        let backFaceFlags = VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT.rawValue)

        vkCmdSetDepthTestEnable(commandBuffer, VK_FALSE)
        vkCmdSetStencilTestEnable(commandBuffer, VK_FALSE)

        vkCmdSetDepthCompareOp(commandBuffer, VK_COMPARE_OP_ALWAYS)
        vkCmdSetDepthWriteEnable(commandBuffer, VK_FALSE)
        vkCmdSetDepthBoundsTestEnable(commandBuffer, VK_FALSE)

        // front face stencil
        vkCmdSetStencilCompareMask(commandBuffer,
                                   frontFaceFlags,
                                   0xffffffff)
        vkCmdSetStencilWriteMask(commandBuffer,
                                 frontFaceFlags,
                                 0xffffffff)
        vkCmdSetStencilOp(commandBuffer,
                          frontFaceFlags,
                          VK_STENCIL_OP_KEEP,
                          VK_STENCIL_OP_KEEP,
                          VK_STENCIL_OP_KEEP,
                          VK_COMPARE_OP_ALWAYS)
        // back face stencil
        vkCmdSetStencilCompareMask(commandBuffer,
                                   backFaceFlags,
                                   0xffffffff)
        vkCmdSetStencilWriteMask(commandBuffer,
                                   backFaceFlags,
                                   0xffffffff)
        vkCmdSetStencilOp(commandBuffer,
                          backFaceFlags,
                          VK_STENCIL_OP_KEEP,
                          VK_STENCIL_OP_KEEP,
                          VK_STENCIL_OP_KEEP,
                          VK_COMPARE_OP_ALWAYS)
    }
}

#endif //if ENABLE_VULKAN
