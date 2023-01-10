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
}

#endif //if ENABLE_VULKAN
