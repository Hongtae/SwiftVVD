#if ENABLE_VULKAN
import Vulkan
import Foundation

extension ShaderStage {
    public func vkFlagBits() -> VkShaderStageFlagBits
    {
        switch (self) {
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

#endif //if ENABLE_VULKAN
