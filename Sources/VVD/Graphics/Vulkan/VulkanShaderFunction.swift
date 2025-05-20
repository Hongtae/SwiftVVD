//
//  File: VulkanShaderFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class VulkanShaderFunction: ShaderFunction {
    let module: VulkanShaderModule
    var device: GraphicsDevice { self.module.device }
    var stage: ShaderStage { self.module.stage }
    let functionName: String
    let functionConstants: [String: ShaderFunctionConstant]
    var stageInputAttributes: [ShaderAttribute] { self.module.inputAttributes }

    var specializationInfo: VkSpecializationInfo
    var specializationData: UnsafeMutableRawPointer?

    init(module: VulkanShaderModule, name: String, constantValues: [ShaderFunctionConstantValue]) {
        self.module = module
        self.functionName = name
        self.specializationData = nil
        self.specializationInfo = VkSpecializationInfo()
        self.functionConstants = [:]

        if constantValues.isEmpty == false {
            var size = 0
            for sp in constantValues {
                size += Int(sp.size)
            }

            if size > 0 {
                typealias MemLayout = MemoryLayout<VkSpecializationMapEntry>
                let mapEntrySizeInBytes = MemLayout.stride * constantValues.count
                specializationData = .allocate(
                    byteCount: mapEntrySizeInBytes + size,
                    alignment: MemLayout.alignment)
                let mapEntry = specializationData!.bindMemory(to: VkSpecializationMapEntry.self, capacity: constantValues.count)
                var data = specializationData!.advanced(by: mapEntrySizeInBytes)

                self.specializationInfo.mapEntryCount = UInt32(constantValues.count)
                self.specializationInfo.pMapEntries = UnsafePointer(mapEntry)
                self.specializationInfo.pData = UnsafeRawPointer(data)
                self.specializationInfo.dataSize = size

                var offset = 0
                for (i, sp) in constantValues.enumerated() {
                    mapEntry[i].constantID = UInt32(sp.index)
                    mapEntry[i].offset = UInt32(offset)
                    mapEntry[i].size = sp.size

                    sp.data.withUnsafeBytes {
                        data.copyMemory(from: $0.baseAddress!, byteCount: sp.size)
                    }
                    offset += sp.size
                    data = data.advanced(by: sp.size)
                }
            }
        }
    }

    deinit {
        self.specializationData?.deallocate()
    }
}
#endif //if ENABLE_VULKAN
