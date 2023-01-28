//
//  File: VulkanShaderStage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

extension ShaderStage {
    public func from(vkFlagBits: VkShaderStageFlagBits) -> Self {
        switch vkFlagBits {
        case VK_SHADER_STAGE_VERTEX_BIT:
            return .vertex
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            return .tessellationControl
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            return .tessellationEvaluation
        case VK_SHADER_STAGE_GEOMETRY_BIT:
            return .geometry
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            return .fragment
        case VK_SHADER_STAGE_COMPUTE_BIT:
            return .compute
        default:
            assertionFailure("Unknown shader stage!")
            return .unknown
        }
    }
    public func vkFlagBits() -> VkShaderStageFlagBits
    {
        switch self {
        case .vertex:
            return VK_SHADER_STAGE_VERTEX_BIT
        case .tessellationControl:
            return VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT
        case .tessellationEvaluation:
            return VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT
        case .geometry:
            return VK_SHADER_STAGE_GEOMETRY_BIT
        case .fragment:
            return VK_SHADER_STAGE_FRAGMENT_BIT
        case .compute:
            return VK_SHADER_STAGE_COMPUTE_BIT
        default:
            assertionFailure("Unknown shader stage!")
            return VkShaderStageFlagBits(0)
        }        
    }
    public func vkFlags() -> VkShaderStageFlags {
        return VkShaderStageFlags(self.vkFlagBits().rawValue)
    }
}

extension ShaderStageFlags {
    public static func from(vkFlags: VkShaderStageFlags) -> Self {
        var flags: Self = []
        if vkFlags & UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue) != 0 {
            flags.insert(.vertex)
        }
        if vkFlags & UInt32(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT.rawValue) != 0 {
            flags.insert(.tessellationControl)
        }
        if vkFlags & UInt32(VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT.rawValue) != 0 {
            flags.insert(.tessellationEvaluation)
        }
        if vkFlags & UInt32(VK_SHADER_STAGE_GEOMETRY_BIT.rawValue) != 0 {
            flags.insert(.geometry)
        }
        if vkFlags & UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue) != 0 {
            flags.insert(.fragment)
        }
        if vkFlags & UInt32(VK_SHADER_STAGE_COMPUTE_BIT.rawValue) != 0 {
            flags.insert(.compute)
        }
        return flags
    }

    public func vkFlags() -> VkShaderStageFlags {
        var flags: VkShaderStageFlags = 0
        if self.contains(.vertex) {
            flags |= UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue)
        }
        if self.contains(.tessellationControl) {
            flags |= UInt32(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT.rawValue)
        }
        if self.contains(.tessellationEvaluation) {
            flags |= UInt32(VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT.rawValue)
        }
        if self.contains(.geometry) {
            flags |= UInt32(VK_SHADER_STAGE_GEOMETRY_BIT.rawValue)
        }
        if self.contains(.fragment) {
            flags |= UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        }
        if self.contains(.compute) {
            flags |= UInt32(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)
        }
        return flags
    }
}

#endif //if ENABLE_VULKAN
