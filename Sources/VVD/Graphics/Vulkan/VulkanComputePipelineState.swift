//
//  File: VulkanComputePipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanComputePipelineState: ComputePipelineState {
    let device: GraphicsDevice
    let pipeline: VkPipeline
    let layout: VkPipelineLayout

    init(device: VulkanGraphicsDevice, pipeline: VkPipeline, layout: VkPipelineLayout) {
        self.device = device
        self.pipeline = pipeline
        self.layout = layout
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyPipeline(device.device, pipeline, device.allocationCallbacks)
        vkDestroyPipelineLayout(device.device, layout, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
