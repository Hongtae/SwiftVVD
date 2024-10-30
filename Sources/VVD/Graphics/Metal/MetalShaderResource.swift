//
//  File: MetalShaderResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

private func shaderResourceStructMember(from st: MTLStructType) -> [ShaderResourceStructMember] {
    var members: [ShaderResourceStructMember] = []
    members.reserveCapacity(st.members.count)

    for member in st.members {
        var mb = ShaderResourceStructMember(dataType: .unknown,
                                            name: member.name,
                                            offset: member.offset,
                                            size: 0,
                                            count: 0,
                                            stride: 0,
                                            members: [])

        let type = member.dataType
        var memberStruct: MTLStructType? = nil

        if type == .array {
            let arrayType = member.arrayType()!
            mb.count = arrayType.arrayLength
            mb.stride = arrayType.stride
            mb.dataType = .from(mtlDataType: arrayType.elementType)
            if arrayType.elementType == .struct {
                memberStruct = arrayType.elementStructType()
            }
        } else {
            mb.count = 1
            mb.dataType = .from(mtlDataType: type)
        }
        if type == .struct {
            memberStruct = member.structType()
        }
        if let memberStruct = memberStruct {
            mb.members = shaderResourceStructMember(from: memberStruct)
            var size = 0
            mb.members.forEach {
                size = max(size, $0.offset + $0.size)
            }
            if (size & 0x3) != 0 {
                size = (size | 0x3) + 1     // 4-bytes alignment
            }
            mb.size = size
        } else {
            if mb.count > 1 {
                mb.size = mb.stride * mb.count
            } else {
                mb.size = mb.dataType.size()
            }
        }
        if type == .pointer {
            Log.error("Pointer in struct!")
            assertionFailure("Not Implemented!")
        }
        if type == .texture {
            Log.error("TextureReference in struct!")
            assertionFailure("Not Implemented!")
        }
        members.append(mb)
    }
    return members
}

extension ShaderResource {
    static func from(mtlBinding binding: any MTLBinding,
                     bindingMap: [MetalResourceBinding],
                     stage: ShaderStage) -> ShaderResource {
        var resource = ShaderResource(set: 0,
                                      binding: 0,
                                      name: binding.name,
                                      type: .buffer,
                                      stages: .init(stage: stage),
                                      count: 1,
                                      stride: 0,
                                      enabled: binding.isUsed,
                                      access: .readOnly,
                                      members: [])
        switch binding.access {
        case .readOnly:     resource.access = .readOnly
        case .writeOnly:    resource.access = .writeOnly
        case .readWrite:    resource.access = .readWrite
        @unknown default:
            Log.warn("Unhandled access type: \(binding.access)")
        }

        var indexNotFound = true
        switch binding.type {
        case .buffer:
            resource.type = .buffer
            if let buffer = binding as? MTLBufferBinding {
                resource.bufferTypeInfo = ShaderResourceBuffer(
                    dataType: .from(mtlDataType: buffer.bufferDataType),
                    alignment: buffer.bufferAlignment,
                    size: buffer.bufferDataSize)
                if let structType = buffer.bufferStructType {
                    resource.members = shaderResourceStructMember(from: structType)
                } else {
                    Log.error("Unsupported buffer type: \(buffer.bufferDataType)")
                    assertionFailure("Unsupported buffer type")
                }
            } else {
                assertionFailure("Unsupported buffer type")
            }

            if let binding = bindingMap.first(where: { $0.bufferIndex == binding.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
        case .texture:
            resource.type = .texture
            if let texture = binding as? MTLTextureBinding {
                resource.count = texture.arrayLength
            }
            if let binding = bindingMap.first(where: { $0.textureIndex == binding.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
        case .sampler:
            resource.type = .sampler
            if let binding = bindingMap.first(where: { $0.samplerIndex == binding.index }) {
                resource.set = binding.set
                resource.binding = binding.binding
                indexNotFound = false
            }
            break
        default:
            fatalError("Unsupported shader argument type: \(binding.type)")
        }

        assert(indexNotFound == false, "Unable to find binding index for resource: \(binding.name)")
        return resource
    }
}

extension ShaderPushConstantLayout {
    static func from(mtlBufferBinding binding: any MTLBufferBinding,
                     offset: Int,
                     size: Int,
                     stage: ShaderStage) -> ShaderPushConstantLayout {
        var layout = ShaderPushConstantLayout(name: binding.name,
                                              offset: offset,
                                              size: size,
                                              stages: .init(stage: stage),
                                              members: [])
        if let structType = binding.bufferStructType {
            layout.members = shaderResourceStructMember(from: structType)
        }
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
