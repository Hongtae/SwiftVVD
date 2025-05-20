//
//  File: VulkanShaderStage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Vulkan

extension ShaderStage {
    func from(vkFlagBits: VkShaderStageFlagBits) -> Self {
        let stage: ShaderStage = switch vkFlagBits {
        case VK_SHADER_STAGE_VERTEX_BIT:
                .vertex
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
                .tessellationControl
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
                .tessellationEvaluation
        case VK_SHADER_STAGE_GEOMETRY_BIT:
                .geometry
        case VK_SHADER_STAGE_FRAGMENT_BIT:
                .fragment
        case VK_SHADER_STAGE_COMPUTE_BIT:
                .compute
        default:
                .unknown
        }
        assert(stage != .unknown, "Unknown shader stage!")
        return stage
    }
    
    func vkFlagBits() -> VkShaderStageFlagBits
    {
        let flags: VkShaderStageFlagBits = switch self {
        case .vertex:
            VK_SHADER_STAGE_VERTEX_BIT
        case .tessellationControl:
            VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT
        case .tessellationEvaluation:
            VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT
        case .geometry:
            VK_SHADER_STAGE_GEOMETRY_BIT
        case .fragment:
            VK_SHADER_STAGE_FRAGMENT_BIT
        case .compute:
            VK_SHADER_STAGE_COMPUTE_BIT
        default:
            VkShaderStageFlagBits(0)
        }
        assert(flags != VkShaderStageFlagBits(0), "Unknown shader stage!")
        return flags
    }
    
    func vkFlags() -> VkShaderStageFlags {
        return VkShaderStageFlags(self.vkFlagBits().rawValue)
    }
}

extension ShaderStageFlags {
    static func from(vkFlags: VkShaderStageFlags) -> Self {
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

    func vkFlags() -> VkShaderStageFlags {
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
