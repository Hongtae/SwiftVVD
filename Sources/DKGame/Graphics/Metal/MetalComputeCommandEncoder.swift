//
//  File: MetalComputeCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalComputeCommandEncoder: ComputeCommandEncoder {

    struct EncodingState {
        let encoder: Encoder
        var pipelineState: MetalComputePipelineState?
    }

    class Encoder: MetalCommandEncoder {
        typealias Command = (MTLComputeCommandEncoder, inout EncodingState)->Void
        var commands: [Command] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        var waitEvents: Set<MetalHashable<MetalEvent>> = []
        var signalEvents: Set<MetalHashable<MetalEvent>> = []
        var waitSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]
        var signalSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]

        var pushConstants: [UInt8] = []

        override init() {
            super.init()
            self.commands.reserveCapacity(self.initialNumberOfCommands)
        }

        override func encode(_ buffer: MTLCommandBuffer) -> Bool {
            if let encoder = buffer.makeComputeCommandEncoder() {
                self.waitEvents.forEach {
                    let event: MetalEvent = $0.object
                    buffer.encodeWaitForEvent(event.event,
                                              value: event.nextWaitValue())
                }
                self.waitSemaphores.forEach { (key, value) in
                    let event: MetalSemaphore = key.object
                    buffer.encodeWaitForEvent(event.event, value: value)
                }

                var state = EncodingState(encoder: self)
                self.commands.forEach { $0(encoder, &state) }
                encoder.endEncoding()

                self.signalEvents.forEach {
                    let event: MetalEvent = $0.object
                    buffer.encodeSignalEvent(event.event,
                                             value: event.nextSignalValue())
                }
                self.signalSemaphores.forEach { (key, value) in
                    let event: MetalSemaphore = key.object
                    buffer.encodeSignalEvent(event.event, value: value)
                }

                return true
            }
            return false
        }
    }

    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    init(buffer: MetalCommandBuffer) {
        self.commandBuffer = buffer
        self.encoder = Encoder()
    }

    public func setResource(_ bindingSet: ShaderBindingSet, index: Int) {
        assert(self.encoder != nil)
        assert(bindingSet is MetalShaderBindingSet)

        if let bindingSet = bindingSet as? MetalShaderBindingSet,
           let encoder = self.encoder {
            // copy resources
            let buffers = bindingSet.buffers
            let textures = bindingSet.textures
            let samplers = bindingSet.samplers

            encoder.commands.append {
                (encoder: MTLComputeCommandEncoder, state: inout EncodingState) in

                if let pipelineState = state.pipelineState {
                    for binding in pipelineState.bindings.resourceBindings {
                        if binding.set != index { continue }

                        if binding.type == .buffer {
                            if let bufferOffsets = buffers[binding.binding] {
                                if bufferOffsets.count > 0 {
                                    let buffers: [MTLBuffer] = bufferOffsets.map { $0.buffer.buffer }
                                    let offsets: [Int] = bufferOffsets.map { $0.offset }

                                    encoder.setBuffers(buffers,
                                                       offsets: offsets,
                                                       range: index..<(index + bufferOffsets.count))
                                }
                            }
                        }
                        if binding.type == .texture || binding.type == .textureSampler {
                            if let textures = textures[binding.binding] {
                                if textures.count > 0 {
                                    let textures: [MTLTexture] = textures.map { $0.texture }

                                    encoder.setTextures(textures,
                                                        range: index..<(index + textures.count))
                                }
                            }
                        }
                        if binding.type == .sampler || binding.type == .textureSampler {
                            if let samplers = samplers[binding.binding] {
                                if samplers.count > 0 {
                                    let samplers: [MTLSamplerState] = samplers.map { $0.sampler }

                                    encoder.setSamplerStates(samplers,
                                                             range: index..<(index + samplers.count))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        assert(self.encoder != nil)
        assert(pipelineState is MetalComputePipelineState)

        if let pipelineState = pipelineState as? MetalComputePipelineState,
           let encoder = self.encoder {

            if pipelineState.bindings.pushConstantBufferSize > 0 {
                encoder.pushConstants.reserveCapacity(pipelineState.bindings.pushConstantBufferSize)
            }

            encoder.commands.append {
                (encoder: MTLComputeCommandEncoder, state: inout EncodingState) in

                encoder.setComputePipelineState(pipelineState.pipelineState)
                state.pipelineState = pipelineState
            }
        }
    }

    public func pushConstant<D>(stages: ShaderStageFlags, offset: Int, data: D) where D : DataProtocol {
        assert(self.encoder != nil)
        let size = data.count
        if stages.contains(.compute), size > 0 {
            let buffer = Array<UInt8>(data)
            self.encoder?.commands.append {
                (encoder: MTLComputeCommandEncoder, state: inout EncodingState) in

                if let pipelineState = state.pipelineState {
                    let s = offset + size
                    if state.encoder.pushConstants.count < s {
                        state.encoder.pushConstants.append(
                            contentsOf: [UInt8](repeating: 0,
                                                count: s - state.encoder.pushConstants.count))
                    }
                    // copy buffer
                    state.encoder.pushConstants.replaceSubrange(offset..<s, with: buffer)

                    if pipelineState.bindings.pushConstantBufferSize > state.encoder.pushConstants.count {
                        state.encoder.pushConstants.append(
                            contentsOf: [UInt8](repeating: 0,
                                                count: pipelineState.bindings.pushConstantBufferSize - state.encoder.pushConstants.count))
                    }

                    encoder.setBytes(state.encoder.pushConstants,
                                     length: pipelineState.bindings.pushConstantBufferSize,
                                     index: pipelineState.bindings.pushConstantIndex)
                }
            }
        }
    }

    public func dispatch(numGroupX: Int, numGroupY: Int, numGroupZ: Int) {
        assert(self.encoder != nil)
        self.encoder?.commands.append {
            (encoder: MTLComputeCommandEncoder, state: inout EncodingState) in

            if let pipelineState = state.pipelineState {
                encoder.dispatchThreadgroups(
                    MTLSize(width: numGroupX, height: numGroupY, depth: numGroupZ),
                    threadsPerThreadgroup: pipelineState.workgroupSize)
            } else {
                assertionFailure("ComputePipelineState must be bound first.")
            }
        }
    }

    public func endEncoding() {
        assert(self.encoder != nil)
        if let commandBuffer = self.commandBuffer as? MetalCommandBuffer,
           let encoder = self.encoder {
            commandBuffer.endEncoder(encoder)
        }
        self.encoder = nil
    }

    public var isCompleted: Bool {
        return self.encoder == nil
    }

    public func waitEvent(_ event: Event) {
        assert(event is MetalEvent)
        assert(self.encoder != nil)
        if let event = event as? MetalEvent, let encoder = self.encoder {
            encoder.events.append(event)
            encoder.waitEvents.insert(MetalHashable(event))
        }
    }

    public func signalEvent(_ event: Event) {
        assert(event is MetalEvent)
        assert(self.encoder != nil)
        if let event = event as? MetalEvent, let encoder = self.encoder {
            encoder.events.append(event)
            encoder.signalEvents.insert(MetalHashable(event))
        }
    }

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
        assert(semaphore is MetalSemaphore)
        assert(self.encoder != nil)
        if let semaphore = semaphore as? MetalSemaphore,
           let encoder = self.encoder {
            let key = MetalHashable(semaphore)
            if let waitValue = encoder.waitSemaphores[key] {
                if value > waitValue {
                    encoder.waitSemaphores[key] = value
                }
            } else {
                encoder.semaphores.append(semaphore)
                encoder.waitSemaphores[key] = value
            }
        }
    }

    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
        assert(semaphore is MetalSemaphore)
        assert(self.encoder != nil)
        if let semaphore = semaphore as? MetalSemaphore,
           let encoder = self.encoder {
            let key = MetalHashable(semaphore)
            if let signalValue = encoder.signalSemaphores[key] {
                if value > signalValue {
                    encoder.waitSemaphores[key] = value
                }
            } else {
                encoder.semaphores.append(semaphore)
                encoder.signalSemaphores[key] = value
            }
        }
    }
}
#endif //if ENABLE_METAL
