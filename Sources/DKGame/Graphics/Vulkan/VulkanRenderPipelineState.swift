//
//  File: VulkanRenderPipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanRenderPipelineState: RenderPipelineState {
    public let device: GraphicsDevice
    public let pipeline: VkPipeline
    public let layout: VkPipelineLayout
    public let renderPass: VkRenderPass

    public init(device: VulkanGraphicsDevice, pipeline: VkPipeline, layout: VkPipelineLayout, renderPass: VkRenderPass) {
        self.device = device
        self.pipeline = pipeline
        self.layout = layout
        self.renderPass = renderPass
    }

    deinit {
        let device = self.device as! VulkanGraphicsDevice
        vkDestroyPipeline(device.device, pipeline, device.allocationCallbacks)
	    vkDestroyPipelineLayout(device.device, layout, device.allocationCallbacks)
    	vkDestroyRenderPass(device.device, renderPass, device.allocationCallbacks)
    }
}

#endif //if ENABLE_VULKAN
