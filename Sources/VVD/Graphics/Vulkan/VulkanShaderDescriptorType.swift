//
//  File: VulkanShaderDescriptorType.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

extension ShaderDescriptorType {
    func vkType() -> VkDescriptorType {
        switch self {
        case .uniformBuffer:        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        case .storageBuffer:        VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
        case .storageTexture:       VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
        case .textureSampler:       VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        case .texture:              VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        case .uniformTexelBuffer:   VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
        case .storageTexelBuffer:   VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
        case .sampler:              VK_DESCRIPTOR_TYPE_SAMPLER
        }
    }
}
#endif //if ENABLE_VULKAN
