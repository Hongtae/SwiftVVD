//
//  File: MetalShaderBindingSet.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalShaderBindingSet: ShaderBindingSet {

    let device: GraphicsDevice
    let layout: [ShaderBinding]

    var buffers: [Int: Array<(buffer: MetalBuffer, offset: Int)>] = [:]
    var textures: [Int: Array<MetalTexture>] = [:]
    var samplers: [Int: Array<MetalSamplerState>] = [:]

    init(device: MetalGraphicsDevice, layout: [ShaderBinding]) {
        self.device = device
        self.layout = layout
    }

    func setBuffer(_ buffer: GPUBuffer, offset: Int, length: Int, binding: Int) {
        self.setBufferArray([BufferBindingInfo(buffer: buffer,
                                               offset: offset,
                                               length: length)],
                            binding:binding)
    }

    func setBufferArray(_ buffers: [BufferBindingInfo], binding: Int) {
        if let descriptor = self.layout.first(where: { $0.binding == binding }) {

            let startingIndex = 0
            let availableItems = min(buffers.count, descriptor.arrayLength - startingIndex)
            assert(buffers.count >= availableItems)

            var bufferArray = type(of: self.buffers).Value()
            bufferArray.reserveCapacity(availableItems)

            for i in 0..<availableItems {
                assert(buffers[i].buffer is MetalBuffer)
                let buffer = buffers[i].buffer as! MetalBuffer

                bufferArray.append( (buffer: buffer, offset: buffers[i].offset) )
            }
            self.buffers[binding] = bufferArray
        }
    }

    func setTexture(_ texture: Texture, binding: Int) {
        self.setTextureArray([texture], binding: binding)
    }

    func setTextureArray(_ textures: [Texture], binding: Int) {
        if let descriptor = self.layout.first(where: { $0.binding == binding }) {

            let startingIndex = 0
            let availableItems = min(textures.count, descriptor.arrayLength - startingIndex)
            assert(textures.count >= availableItems)

            var textureArray = type(of: self.textures).Value()
            textureArray.reserveCapacity(availableItems)

            for i in 0..<availableItems {
                assert(textures[i] is MetalTexture)
                let texture = textures[i] as! MetalTexture

                textureArray.append(texture)
            }
            self.textures[binding] = textureArray
        }
    }

    func setSamplerState(_ sampler: SamplerState, binding: Int) {
        self.setSamplerStateArray([sampler], binding: binding)
    }

    func setSamplerStateArray(_ samplers: [SamplerState], binding: Int) {
        if let descriptor = self.layout.first(where: { $0.binding == binding }) {

            let startingIndex = 0
            let availableItems = min(samplers.count, descriptor.arrayLength - startingIndex)
            assert(samplers.count >= availableItems)

            var samplerArray = type(of: self.samplers).Value()
            samplerArray.reserveCapacity(availableItems)

            for i in 0..<availableItems {
                assert(samplers[i] is MetalSamplerState)
                let sampler = samplers[i] as! MetalSamplerState

                samplerArray.append(sampler)
            }
            self.samplers[binding] = samplerArray
        }
    }
}
#endif //if ENABLE_METAL
