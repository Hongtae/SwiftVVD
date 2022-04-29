#if ENABLE_VULKAN
import Vulkan
import Foundation

extension ShaderStage {
    public func vkFlags() -> VkShaderStageFlags {
        switch (self) {
        case .vertex:
            return VkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT.rawValue)
        case .tessellationControl:
            return VkShaderStageFlags(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT.rawValue)
        case .tessellationEvaluation:
            return VkShaderStageFlags(VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT.rawValue)
        case .geometry:
            return VkShaderStageFlags(VK_SHADER_STAGE_GEOMETRY_BIT.rawValue)
        case .fragment:
            return VkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        case .compute:
            return VkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT.rawValue)
        default:
            return VkShaderStageFlags(0)
        }
    }
}

#endif //if ENABLE_VULKAN
