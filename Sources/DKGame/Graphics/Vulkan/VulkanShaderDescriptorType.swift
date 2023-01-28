//
//  File: VulkanShaderDescriptorType.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

public extension ShaderDescriptorType {
    func vkType() -> VkDescriptorType {
        switch self {
        case .uniformBuffer:
            return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        case .storageBuffer:
            return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
        case .storageTexture:
            return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
        case .textureSampler:
            return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        case .texture:
            return VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        case .uniformTexelBuffer:
            return VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
        case .storageTexelBuffer:
            return VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
        case .sampler:
            return VK_DESCRIPTOR_TYPE_SAMPLER
        }
    }
}

#endif //if ENABLE_VULKAN
