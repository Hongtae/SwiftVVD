//
//  File: VulkanDepthStencilState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanDepthStencilState: DepthStencilState {
    let device: GraphicsDevice

    let depthTestEnable: VkBool32
    let depthWriteEnable: VkBool32
    let depthCompareOp: VkCompareOp
    let depthBoundsTestEnable: VkBool32
    let minDepthBounds: Float
    let maxDepthBounds: Float

    let front: VkStencilOpState
    let back: VkStencilOpState
    let stencilTestEnable: VkBool32

    init(device: VulkanGraphicsDevice,
         depthWriteEnable: VkBool32,
         depthCompareOp: VkCompareOp,
         front: VkStencilOpState,
         back: VkStencilOpState) {
        self.device = device

        self.depthWriteEnable = depthWriteEnable
        self.depthCompareOp = depthCompareOp
        self.depthBoundsTestEnable = VK_FALSE
        self.front = front
        self.back = back
        self.minDepthBounds = 0.0
        self.maxDepthBounds = 1.0

        if front.compareOp == VK_COMPARE_OP_ALWAYS &&
           front.failOp == VK_STENCIL_OP_KEEP &&
           front.passOp == VK_STENCIL_OP_KEEP &&
           front.depthFailOp == VK_STENCIL_OP_KEEP &&
           back.compareOp == VK_COMPARE_OP_ALWAYS &&
           back.failOp == VK_STENCIL_OP_KEEP &&
           back.passOp == VK_STENCIL_OP_KEEP &&
           back.depthFailOp == VK_STENCIL_OP_KEEP {
            self.stencilTestEnable = VK_FALSE
        } else {
            self.stencilTestEnable = VK_TRUE
        }
        if depthWriteEnable == VK_FALSE && depthCompareOp == VK_COMPARE_OP_ALWAYS {
            self.depthTestEnable = VK_FALSE
        } else {
            self.depthTestEnable = VK_TRUE
        }
    }

    func bind(commandBuffer: VkCommandBuffer) {

        vkCmdSetDepthTestEnable(commandBuffer, self.depthTestEnable)
        vkCmdSetStencilTestEnable(commandBuffer, self.stencilTestEnable) 
        vkCmdSetDepthBoundsTestEnable(commandBuffer, self.depthBoundsTestEnable)

        vkCmdSetDepthCompareOp(commandBuffer, self.depthCompareOp)
        vkCmdSetDepthWriteEnable(commandBuffer, self.depthWriteEnable)
        
        vkCmdSetDepthBounds(commandBuffer,
                            self.minDepthBounds,
                            self.maxDepthBounds)

        let flags = [VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT.rawValue),
                     VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT.rawValue)]
        let faces = [self.front, self.back]

        for (flag, face) in zip(flags, faces) {
            vkCmdSetStencilCompareMask(commandBuffer, flag,
                                        face.compareMask)
            vkCmdSetStencilWriteMask(commandBuffer, flag, face.writeMask)
            vkCmdSetStencilOp(commandBuffer,
                              flag,
                              face.failOp,
                              face.passOp,
                              face.depthFailOp,
                              face.compareOp)
        }
    }
}
#endif //if ENABLE_VULKAN
