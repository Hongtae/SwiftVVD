//
//  File: MetalRenderCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalRenderCommandEncoder: RenderCommandEncoder {

    struct EncodingState {
        let encoder: Encoder
        var pipelineState: MetalRenderPipelineState?
    }

    class Encoder: MetalCommandEncoder {
        typealias Command = (MTLRenderCommandEncoder, inout EncodingState)->Void
        var commands: [Command] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        var waitEvents: Set<MetalHashable<MetalEvent>> = []
        var signalEvents: Set<MetalHashable<MetalEvent>> = []
        var waitSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]
        var signalSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]

        var pushConstants: [UInt8] = []

        let renderPassDescriptor: MTLRenderPassDescriptor

        init(descriptor: MTLRenderPassDescriptor) {
            self.renderPassDescriptor = descriptor
            super.init()
            self.commands.reserveCapacity(self.initialNumberOfCommands)
        }

        override func encode(_ buffer: MTLCommandBuffer) -> Bool {
            if let encoder = buffer.makeRenderCommandEncoder(descriptor: self.renderPassDescriptor) {
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

    init(buffer: MetalCommandBuffer, descriptor: MTLRenderPassDescriptor) {
        self.commandBuffer = buffer
        self.encoder = Encoder(descriptor: descriptor)
    }

    public func setResource(_ bindingSet: ShaderBindingSet, atIndex index: Int) {
        assert(self.encoder != nil)
        assert(bindingSet is MetalShaderBindingSet)

        if let bindingSet = bindingSet as? MetalShaderBindingSet,
           let encoder = self.encoder {
            // copy resources
            let buffers = bindingSet.buffers
            let textures = bindingSet.textures
            let samplers = bindingSet.samplers

            encoder.commands.append {
                (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

                if let pipelineState = state.pipelineState {
                    // vertex shader resources
                    for binding in pipelineState.vertexBindings.resourceBindings {
                        if binding.set != index { continue }

                        if binding.type == .buffer {
                            if let bufferOffsets = buffers[binding.binding] {
                                if bufferOffsets.count > 0 {
                                    let buffers: [MTLBuffer?] = bufferOffsets.map { $0.buffer.buffer }
                                    let offsets: [Int] = bufferOffsets.map { $0.offset }
                                    let index = binding.bufferIndex
                                    encoder.setVertexBuffers(buffers,
                                                             offsets: offsets,
                                                             range: index..<(index + bufferOffsets.count))
                                }
                            }
                        }
                        if binding.type == .texture || binding.type == .textureSampler {
                            if let textures = textures[binding.binding] {
                                if textures.count > 0 {
                                    let textures: [MTLTexture?] = textures.map { $0.texture }
                                    let index = binding.textureIndex
                                    encoder.setVertexTextures(textures,
                                                              range: index..<(index + textures.count))
                                }
                            }
                        }
                        if binding.type == .sampler || binding.type == .textureSampler {
                            if let samplers = samplers[binding.binding] {
                                if samplers.count > 0 {
                                    let samplers: [MTLSamplerState?] = samplers.map { $0.sampler }
                                    let index = binding.samplerIndex
                                    encoder.setVertexSamplerStates(samplers,
                                                                   range: index..<(index + samplers.count))
                                }
                            }
                        }
                    }
                    // fragment shader resources
                    for binding in pipelineState.fragmentBindings.resourceBindings {
                        if binding.set != index { continue }

                        if binding.type == .buffer {
                            if let bufferOffsets = buffers[binding.binding] {
                                if bufferOffsets.count > 0 {
                                    let buffers: [MTLBuffer?] = bufferOffsets.map { $0.buffer.buffer }
                                    let offsets: [Int] = bufferOffsets.map { $0.offset }
                                    let index = binding.bufferIndex
                                    encoder.setFragmentBuffers(buffers,
                                                               offsets: offsets,
                                                               range: index..<(index + bufferOffsets.count))
                                }
                            }
                        }
                        if binding.type == .texture || binding.type == .textureSampler {
                            if let textures = textures[binding.binding] {
                                if textures.count > 0 {
                                    let textures: [MTLTexture?] = textures.map { $0.texture }
                                    let index = binding.textureIndex
                                    encoder.setFragmentTextures(textures,
                                                                range: index..<(index + textures.count))
                                }
                            }
                        }
                        if binding.type == .sampler || binding.type == .textureSampler {
                            if let samplers = samplers[binding.binding] {
                                if samplers.count > 0 {
                                    let samplers: [MTLSamplerState?] = samplers.map { $0.sampler }
                                    let index = binding.samplerIndex
                                    encoder.setFragmentSamplerStates(samplers,
                                                                     range: index..<(index + samplers.count))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func setViewport(_ v: Viewport) {
        assert(self.encoder != nil)
        let viewport = MTLViewport(originX: v.x,
                                   originY: v.y,
                                   width: v.width,
                                   height: v.height,
                                   znear: v.nearZ,
                                   zfar: v.farZ)

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setViewport(viewport)
        }
    }

    public func setScissorRect(_ r: ScissorRect) {
        assert(self.encoder != nil)
        let rect = MTLScissorRect(x: r.x, y: r.y,
                                  width: r.width, height: r.height)

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setScissorRect(rect)
        }
    }

    public func setRenderPipelineState(_ pipelineState: RenderPipelineState) {
        assert(self.encoder != nil)
        assert(pipelineState is MetalRenderPipelineState)

        if let pipelineState = pipelineState as? MetalRenderPipelineState,
           let encoder = self.encoder {

            if pipelineState.vertexBindings.pushConstantBufferSize > 0 {
                encoder.pushConstants.reserveCapacity(pipelineState.vertexBindings.pushConstantBufferSize)
            }
            if pipelineState.fragmentBindings.pushConstantBufferSize > 0 {
                encoder.pushConstants.reserveCapacity(pipelineState.fragmentBindings.pushConstantBufferSize)
            }

            encoder.commands.append {
                (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

                encoder.setRenderPipelineState(pipelineState.pipelineState)
                state.pipelineState = pipelineState
            }
        }
    }

    public func setVertexBuffer(_ buffer: Buffer, offset: Int, index: Int) {
        assert(self.encoder != nil)
        assert(buffer is MetalBuffer)

        if let buffer = buffer as? MetalBuffer, let encoder = self.encoder {
            encoder.commands.append {
                (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

                var bufferIndex = index
                if let pipelineState = state.pipelineState {
                    bufferIndex = pipelineState.vertexBindings.inputAttributeIndexOffset + index
                }
                encoder.setVertexBuffer(buffer.buffer,
                                        offset: offset,
                                        index: bufferIndex)
            }
        }
    }

    public func setVertexBuffers(_ buffers: [Buffer], offsets: [Int], index: Int) {
        assert(self.encoder != nil)
        let count = min(buffers.count, offsets.count)
        if count > 0, let encoder = self.encoder {
            let buffers: [MTLBuffer?] = buffers[0..<count].map { ($0 as? MetalBuffer)?.buffer }
            let offsets: [Int] = .init(offsets[0..<count])

            encoder.commands.append {
                (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

                encoder.setVertexBuffers(buffers,
                                         offsets: offsets,
                                         range: index..<(index+count))
            }
        }
    }

    public func setDepthStencilState(_ state: DepthStencilState?) {
        assert(self.encoder != nil)

        var depthStencilState: MTLDepthStencilState? = nil
        if let state {
            assert(state is MetalDepthStencilState)
            depthStencilState = (state as! MetalDepthStencilState).depthStencilState
        }

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setDepthStencilState(depthStencilState)
        }
    }

    public func setDepthClipMode(_ mode: DepthClipMode) {
        assert(self.encoder != nil)

        let depthClipMode: MTLDepthClipMode
        switch mode {
        case .clip:     depthClipMode = .clip
        case .clamp:    depthClipMode = .clamp
        }

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setDepthClipMode(depthClipMode)
        }
    }

    public func setCullMode(_ mode: CullMode) {
        assert(self.encoder != nil)

        let cullMode: MTLCullMode
        switch mode {
        case .none:     cullMode = .none
        case .front:    cullMode = .front
        case .back:     cullMode = .back
        }

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setCullMode(cullMode)
        }
    }

    public func setFrontFacing(_ front: Winding) {
        assert(self.encoder != nil)

        let frontFacingWinding: MTLWinding
        switch front {
        case .clockwise:        frontFacingWinding = .clockwise
        case .counterClockwise: frontFacingWinding = .counterClockwise
        }
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setFrontFacing(frontFacingWinding)
        }
    }

    public func setTriangleFillMode(_ fillMode: TriangleFillMode) {
        assert(self.encoder != nil)

        let triangleFillMode: MTLTriangleFillMode
        switch fillMode {
        case .fill:     triangleFillMode = .fill
        case .lines:    triangleFillMode = .lines
        }
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setTriangleFillMode(triangleFillMode)
        }
    }

    public func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
        assert(self.encoder != nil)
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setBlendColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

    public func setStencilReferenceValue(_ value: UInt32) {
        assert(self.encoder != nil)
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setStencilReferenceValue(value)
        }
    }

    public func setStencilReferenceValues(front: UInt32, back: UInt32) {
        assert(self.encoder != nil)
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setStencilReferenceValues(front: front, back: back)
        }
    }

    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        assert(self.encoder != nil)
        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in
            encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
        }
    }

    public func pushConstant<D>(stages: ShaderStageFlags, offset: Int, data: D) where D : DataProtocol {
        assert(self.encoder != nil)
        let size = data.count
        if stages.intersection([.vertex, .fragment]).isEmpty == false, size > 0 {
            let buffer = Array<UInt8>(data)
            self.encoder?.commands.append {
                (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

                if let pipelineState = state.pipelineState {
                    let s = offset + size
                    if state.encoder.pushConstants.count < s {
                        state.encoder.pushConstants.append(
                            contentsOf: [UInt8](repeating: 0,
                                                count: s - state.encoder.pushConstants.count))
                    }
                    // copy buffer
                    state.encoder.pushConstants.replaceSubrange(offset..<s, with: buffer)

                    if stages.contains(.vertex) {
                        let bindings = pipelineState.vertexBindings
                        if bindings.pushConstantBufferSize > state.encoder.pushConstants.count {
                            state.encoder.pushConstants.append(
                                contentsOf: [UInt8](repeating: 0,
                                                    count: bindings.pushConstantBufferSize - state.encoder.pushConstants.count))
                        }

                        encoder.setVertexBytes(state.encoder.pushConstants,
                                               length: bindings.pushConstantBufferSize,
                                               index: bindings.pushConstantIndex)
                    }
                    if stages.contains(.fragment) {
                        let bindings = pipelineState.fragmentBindings
                        if bindings.pushConstantBufferSize > state.encoder.pushConstants.count {
                            state.encoder.pushConstants.append(
                                contentsOf: [UInt8](repeating: 0,
                                                    count: bindings.pushConstantBufferSize - state.encoder.pushConstants.count))
                        }

                        encoder.setFragmentBytes(state.encoder.pushConstants,
                                                 length: bindings.pushConstantBufferSize,
                                                 index: bindings.pushConstantIndex)
                    }
                }
            }
        }
    }

    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
        assert(self.encoder != nil)

        let primitiveTopology: MTLPrimitiveType
        switch primitiveType {
        case .point:            primitiveTopology = .point
        case .line:             primitiveTopology = .line
        case .lineStrip:        primitiveTopology = .lineStrip
        case .triangle:         primitiveTopology = .triangle
        case .triangleStrip:    primitiveTopology = .triangleStrip
        }

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

            encoder.drawPrimitives(type: primitiveTopology,
                                   vertexStart: vertexStart,
                                   vertexCount: vertexCount,
                                   instanceCount: instanceCount,
                                   baseInstance: baseInstance)
        }
    }

    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int) {
        assert(self.encoder != nil)
        assert(indexBuffer is MetalBuffer)

        let buffer = indexBuffer as! MetalBuffer
        let indexBufferType: MTLIndexType
        switch indexType {
        case .uint16:   indexBufferType = .uint16
        case .uint32:   indexBufferType = .uint32
        }

        let primitiveTopology: MTLPrimitiveType
        switch primitiveType {
        case .point:            primitiveTopology = .point
        case .line:             primitiveTopology = .line
        case .lineStrip:        primitiveTopology = .lineStrip
        case .triangle:         primitiveTopology = .triangle
        case .triangleStrip:    primitiveTopology = .triangleStrip
        }

        self.encoder?.commands.append {
            (encoder: MTLRenderCommandEncoder, state: inout EncodingState) in

            if baseVertex == 0 && baseInstance == 0 {
                encoder.drawIndexedPrimitives(type: primitiveTopology,
                                              indexCount: indexCount,
                                              indexType: indexBufferType,
                                              indexBuffer: buffer.buffer,
                                              indexBufferOffset: indexBufferOffset,
                                              instanceCount: instanceCount)
            } else {
                encoder.drawIndexedPrimitives(type: primitiveTopology,
                                              indexCount: indexCount,
                                              indexType: indexBufferType,
                                              indexBuffer: buffer.buffer,
                                              indexBufferOffset: indexBufferOffset,
                                              instanceCount: instanceCount,
                                              baseVertex: baseVertex,
                                              baseInstance: baseInstance)
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
