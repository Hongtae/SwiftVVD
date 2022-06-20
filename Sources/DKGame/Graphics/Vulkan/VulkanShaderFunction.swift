//
//  File: VulkanShaderFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

public class VulkanShaderFunction: ShaderFunction {
    public let module: VulkanShaderModule
    public var device: GraphicsDevice { self.module.device }
    public var stage: ShaderStage { self.module.stage }
    public let functionName: String
    public let functionConstants: [String: ShaderFunctionConstant]
    public var stageInputAttributes: [ShaderAttribute] { self.module.inputAttributes }

    var specializationInfo: VkSpecializationInfo
    var specializationData: UnsafeMutableRawPointer?

    public init(module: VulkanShaderModule, name: String, specializationValues: [ShaderSpecialization]) {
        self.module = module
        self.functionName = name
        self.specializationData = nil
        self.specializationInfo = VkSpecializationInfo()
        self.functionConstants = [:]

        if specializationValues.isEmpty == false {
            var size = 0
            for sp in specializationValues {
                size += Int(sp.size)
            }

            if size > 0 {
                typealias MemLayout = MemoryLayout<VkSpecializationMapEntry>
                let mapEntrySizeInBytes = MemLayout.stride * specializationValues.count
                specializationData = .allocate(
                    byteCount: mapEntrySizeInBytes + size,
                    alignment: MemLayout.alignment)
                let mapEntry = specializationData!.bindMemory(to: VkSpecializationMapEntry.self, capacity: specializationValues.count)
                var data = specializationData!.advanced(by: mapEntrySizeInBytes)

                self.specializationInfo.mapEntryCount = UInt32(specializationValues.count)
                self.specializationInfo.pMapEntries = UnsafePointer(mapEntry)
                self.specializationInfo.pData = UnsafeRawPointer(data)

                var offset = 0
                for i in 0..<specializationValues.count {
                    let sp = specializationValues[i]
                    mapEntry[i].constantID = sp.index
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
