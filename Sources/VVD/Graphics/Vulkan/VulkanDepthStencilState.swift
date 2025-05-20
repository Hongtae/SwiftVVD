//
//  File: VulkanDepthStencilState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanDepthStencilState: DepthStencilState {
    let device: GraphicsDevice

    var depthTestEnable: VkBool32
    var depthWriteEnable: VkBool32
    var depthCompareOp: VkCompareOp
    var depthBoundsTestEnable: VkBool32
    var minDepthBounds: Float
    var maxDepthBounds: Float

    var front: VkStencilOpState
    var back: VkStencilOpState
    var stencilTestEnable: VkBool32

    init(device: VulkanGraphicsDevice) {
        self.device = device

        self.depthTestEnable = VK_FALSE
        self.depthWriteEnable = VK_FALSE
        self.depthCompareOp = VK_COMPARE_OP_ALWAYS
        self.depthBoundsTestEnable = VK_FALSE
        self.minDepthBounds = 0.0
        self.maxDepthBounds = 1.0

        let stencilOp = VkStencilOpState(failOp: VK_STENCIL_OP_KEEP,
                                         passOp: VK_STENCIL_OP_KEEP,
                                         depthFailOp: VK_STENCIL_OP_KEEP,
                                         compareOp: VK_COMPARE_OP_ALWAYS,
                                         compareMask: 0xffffffff,
                                         writeMask: 0xffffffff,
                                         reference: 0)
        self.front = stencilOp
        self.back = stencilOp
        self.stencilTestEnable = VK_FALSE
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
