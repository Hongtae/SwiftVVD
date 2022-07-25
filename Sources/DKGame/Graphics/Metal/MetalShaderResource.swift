//
//  File: MetalShaderResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

private func shaderResourceStructMember(from: MTLStructType) -> [ShaderResourceStructMember] {
    return []
}

extension ShaderResource {
    static func from(mtlArgument arg: MTLArgument,
                     bindingMap: [MetalResourceBinding],
                     stage: ShaderStage) -> ShaderResource {

        var resource = ShaderResource(set: 0,
                                      binding: 0,
                                      name: arg.name,
                                      type: .buffer,
                                      stages: .init(stage: stage),
                                      count: arg.arrayLength,
                                      stride: 0,
                                      enabled: arg.isActive,
                                      access: .readOnly,
                                      members: [])

        switch arg.access {
        case .readOnly:     resource.access = .readOnly
        case .writeOnly:    resource.access = .writeOnly
        case .readWrite:    resource.access = .readWrite
        @unknown default:
            Log.warn("Unhandled access type: \(arg.access)")
        }

        var indexNotFound = true
        switch arg.type {
        case .buffer:
            resource.type = .buffer
            resource.bufferTypeInfo = ShaderResourceBuffer(
                dataType: .from(mtlDataType: arg.bufferDataType),
                alignment: arg.bufferAlignment,
                size: arg.bufferDataSize)
            if arg.bufferDataType == .struct {
                resource.members = shaderResourceStructMember(from: arg.bufferStructType!)
            } else {
                Log.err("Unsupported buffer type: \(arg.bufferDataType)")
                assertionFailure("Unsupported buffer type")
            }

            if let binding = bindingMap.first(where: { $0.bufferIndex == arg.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
        case .texture:
            resource.type = .texture
            if let binding = bindingMap.first(where: { $0.textureIndex == arg.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
        case .sampler:
            resource.type = .sampler
            if let binding = bindingMap.first(where: { $0.samplerIndex == arg.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
        default:
            assertionFailure("Unsupported shader argument type: \(arg.type)")
        }

        assert(indexNotFound == false)
        return resource
    }
}

extension ShaderPushConstantLayout {
    static func from(mtlArgument arg: MTLArgument,
                     offset: Int,
                     size: Int,
                     stage: ShaderStage) -> ShaderPushConstantLayout {
        var layout = ShaderPushConstantLayout(name: arg.name,
                                        offset: offset,
                                        size: size,
                                        stages: .init(stage: stage),
                                        members: [])
        assert(arg.bufferDataType == .struct)
        layout.members = shaderResourceStructMember(from: arg.bufferStructType!)
        return layout
    }
}

func combineShaderResources(_ resources: inout [ShaderResource], resource: ShaderResource) {
    for (i, var r) in resources.enumerated() {
        if resource.set == r.set, resource.binding == r.binding {
            if (r.type == .texture && resource.type == .sampler) ||
                (r.type == .sampler && resource.type == .texture) {
                r.type = .textureSampler
            } else {
                assert(resource.type == r.type, "Invalid resource type!")
            }
            r.stages.formUnion(resource.stages)
            resources[i] = r
            return
        }
    }
    resources.append(resource)
}

#endif //if ENABLE_METAL
