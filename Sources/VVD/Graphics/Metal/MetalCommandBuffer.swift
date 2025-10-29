//
//  File: MetalCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

class MetalCommandEncoder {
    var initialNumberOfCommands: Int { 128 }

    func encode(_ buffer: MTLCommandBuffer) -> Bool {
        return false
    }
}

final class MetalCommandBuffer: CommandBuffer, @unchecked Sendable {
    let commandQueue: CommandQueue
    var device: GraphicsDevice   { commandQueue.device }

    private enum Encoding {
        case encoder(MetalCommandEncoder)
        case waitEvent(MetalEvent)
        case signalEvent(MetalEvent)
        case waitSemaphore(MetalSemaphore, UInt64)
        case signalSemaphore(MetalSemaphore, UInt64)
    }
    private var encodings: [Encoding] = []
    private var completedHandlers: [CommandBufferHandler] = []

    private let lock = NSLock()
    private var _status: CommandBufferStatus
    var status: CommandBufferStatus { self.lock.withLock { _status } }
    
    init(queue: MetalCommandQueue) {
        self.commandQueue = queue
        self._status = .ready
    }

    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
        self.lock.lock()
        defer { self.lock.unlock() }

        if self._status != .ready {
            Log.err("CommandBuffer.makeRenderCommandEncoder failed: CommandBuffer is not in ready state.")
            return nil
        }

        if descriptor.colorAttachments.isEmpty && descriptor.depthStencilAttachment.renderTarget == nil {
            Log.err("RenderPassDescriptor must have at least one color or depth/stencil attachment.")
            return nil
        }

        let mtlLoadAction = { (action: RenderPassAttachmentLoadAction) -> MTLLoadAction in
            switch action {
            case .dontCare:     .dontCare
            case .load:         .load
            case .clear:        .clear
            }
        }

        let mtlStoreAction = { (action: RenderPassAttachmentStoreAction) -> MTLStoreAction in
            switch action {
            case .dontCare:     .dontCare
            case .store:        .store
            }
        }

        let desc = MTLRenderPassDescriptor()

        for (i, ca) in descriptor.colorAttachments.enumerated() {
            let attachment = MTLRenderPassColorAttachmentDescriptor()

            if let rt = ca.renderTarget {
                assert(rt is MetalTexture)
                let rt = rt as! MetalTexture
                attachment.texture = rt.texture
            }
            attachment.clearColor = MTLClearColor(red: Double(ca.clearColor.r),
                                                  green: Double(ca.clearColor.g),
                                                  blue: Double(ca.clearColor.b),
                                                  alpha: Double(ca.clearColor.a))
            attachment.loadAction = mtlLoadAction(ca.loadAction)
            attachment.storeAction = mtlStoreAction(ca.storeAction)

            if let rt = ca.renderTarget, rt.isTransient {
                assert(attachment.loadAction != .load, "Transient texture must not be loaded.")
                assert(attachment.storeAction != .store, "Transient texture must not be stored.")
            }

            if ca.renderTarget != nil {
                let renderTarget = ca.renderTarget as! MetalTexture
                if let rt = ca.resolveTarget {
                    assert(rt is MetalTexture)
                    let resolveTarget = rt as! MetalTexture
                    attachment.resolveTexture = resolveTarget.texture
                    attachment.storeAction = switch ca.storeAction {
                    case .dontCare: .multisampleResolve
                    case .store:    .storeAndMultisampleResolve
                    }

                    assert(renderTarget !== resolveTarget,
                           "Resolve target must be different from render target.")
                    assert(resolveTarget.pixelFormat == renderTarget.pixelFormat,
                           "Resolve target must have the same pixel format with render target.")
                    assert(resolveTarget.sampleCount == 1, "Resolve target must be single-sampled.")
                    assert(resolveTarget.isTransient == false, "Resolve target must not be transient.")
                }
            }
            desc.colorAttachments[i] = attachment
        }

        if let rt = descriptor.depthStencilAttachment.renderTarget {
            assert(rt is MetalTexture)
            let rt = rt as! MetalTexture
            
            var hasDepth = false
            var hasStencil = false

            switch rt.texture.pixelFormat {
#if os(macOS) || targetEnvironment(macCatalyst)
            case .depth16Unorm:
                hasDepth = true
            case .depth24Unorm_stencil8:
                hasDepth = true
                hasStencil = true
            case .x24_stencil8:
                hasStencil = true
#endif
            case .depth32Float:
                hasDepth = true
            case .stencil8:
                hasStencil = true
            case .depth32Float_stencil8:
                hasDepth = true
                hasStencil = true
            case .x32_stencil8:
                hasStencil = true
            default:
                break
            }

            if hasDepth {
                let attachment = MTLRenderPassDepthAttachmentDescriptor()
                attachment.texture = rt.texture
                attachment.clearDepth = descriptor.depthStencilAttachment.clearDepth
                attachment.loadAction = mtlLoadAction(descriptor.depthStencilAttachment.loadAction)
                attachment.storeAction = mtlStoreAction(descriptor.depthStencilAttachment.storeAction)
                if let resolveTarget = descriptor.depthStencilAttachment.resolveTarget {
                    assert(resolveTarget is MetalTexture)
                    let resolveTarget = resolveTarget as! MetalTexture
                    
                    assert(resolveTarget.texture.pixelFormat == rt.texture.pixelFormat,
                           "Resolve target must have the same pixel format with render target.")
                    assert(resolveTarget.sampleCount == 1, "Resolve target must be single-sampled.")
                    assert(resolveTarget.isTransient == false, "Resolve target must not be transient.")

                    attachment.resolveTexture = resolveTarget.texture
                    attachment.depthResolveFilter = switch descriptor.depthStencilAttachment.resolveFilter {
                    case .sample0: .sample0
                    case .min:     .min
                    case .max:     .max
                    }
                    attachment.storeAction = switch descriptor.depthStencilAttachment.storeAction {
                    case .dontCare: .multisampleResolve
                    case .store:    .storeAndMultisampleResolve
                    }
                }
                if rt.isTransient {
                    assert(attachment.loadAction != .load, "Transient texture must not be loaded.")
                    assert(attachment.storeAction != .store, "Transient texture must not be stored.")
                }
                desc.depthAttachment = attachment
            }
            if hasStencil {
                let attachment = MTLRenderPassStencilAttachmentDescriptor()
                attachment.texture = rt.texture
                attachment.clearStencil = descriptor.depthStencilAttachment.clearStencil
                attachment.loadAction = mtlLoadAction(descriptor.depthStencilAttachment.loadAction)
                attachment.storeAction = mtlStoreAction(descriptor.depthStencilAttachment.storeAction)
                if let resolveTarget = descriptor.depthStencilAttachment.resolveTarget {
                    assert(resolveTarget is MetalTexture)
                    let resolveTarget = resolveTarget as! MetalTexture
                    
                    assert(resolveTarget.texture.pixelFormat == rt.texture.pixelFormat,
                           "Resolve target must have the same pixel format with render target.")
                    assert(resolveTarget.sampleCount == 1, "Resolve target must be single-sampled.")
                    assert(resolveTarget.isTransient == false, "Resolve target must not be transient.")
                    
                    attachment.resolveTexture = resolveTarget.texture
                    attachment.stencilResolveFilter = hasDepth ? .depthResolvedSample : .sample0
                    attachment.storeAction = switch descriptor.depthStencilAttachment.storeAction {
                    case .dontCare: .multisampleResolve
                    case .store:    .storeAndMultisampleResolve
                    }
                }
                if rt.isTransient {
                    assert(attachment.loadAction != .load, "Transient texture must not be loaded.")
                    assert(attachment.storeAction != .store, "Transient texture must not be stored.")
                }
                desc.stencilAttachment = attachment
            }
        }

        self._status = .encoding
        return MetalRenderCommandEncoder(buffer: self, descriptor: desc)
    }

    func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self._status != .ready {
            Log.err("CommandBuffer.makeComputeCommandEncoder failed: CommandBuffer is not in ready state.")
            return nil
        }
        self._status = .encoding
        return MetalComputeCommandEncoder(buffer: self)
    }

    func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self._status != .ready {
            Log.err("CommandBuffer.makeCopyCommandEncoder failed: CommandBuffer is not in ready state.")
            return nil
        }
        self._status = .encoding
        return MetalCopyCommandEncoder(buffer: self)
    }

    func encodeWaitEvent(_ event: any GPUEvent) {
        assert(event is MetalEvent)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let event = event as? MetalEvent {
            self.encodings.append(.waitEvent(event))
        }
    }
    
    func encodeSignalEvent(_ event: any GPUEvent) {
        assert(event is MetalEvent)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let event = event as? MetalEvent {
            self.encodings.append(.signalEvent(event))
        }
    }
    
    func encodeWaitSemaphore(_ sema: any GPUSemaphore, value: UInt64) {
        assert(sema is MetalSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = sema as? MetalSemaphore {
            self.encodings.append(.waitSemaphore(semaphore, value))
        }
    }
    
    func encodeSignalSemaphore(_ sema: any GPUSemaphore, value: UInt64) {
        assert(sema is MetalSemaphore)
        self.lock.lock()
        defer { self.lock.unlock() }

        assert(self._status == .ready, "CommandBuffer must be in ready state.")
        if let semaphore = sema as? MetalSemaphore {
            self.encodings.append(.signalSemaphore(semaphore, value))
        }
    }

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        self.lock.withLock {
            self.completedHandlers.append(handler)
        }
    }

    func commit() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self._status != .ready {
            Log.err("CommandBuffer.commit failed: CommandBuffer is not in ready state.")
            return false
        }

        if let queue = (self.commandQueue as? MetalCommandQueue)?.queue {
            if let buffer = queue.makeCommandBuffer() {

                for encoding in self.encodings {
                    switch encoding {
                    case .waitEvent(let event):
                        buffer.encodeWaitForEvent(event.event,
                                                  value: event.nextWaitValue())
                    case .signalEvent(let event):
                        buffer.encodeSignalEvent(event.event,
                                                 value: event.nextSignalValue())
                    case .waitSemaphore(let semaphore, let value):
                        buffer.encodeWaitForEvent(semaphore.event, value: value)
                    case .signalSemaphore(let semaphore, let value):
                        buffer.encodeSignalEvent(semaphore.event, value: value)
                    case .encoder(let encoder):
                        if encoder.encode(buffer) == false {
                            return false
                        }
                    }
                }

                buffer.addCompletedHandler { _ in
                    let handlers = self.lock.withLock {
                        assert(self._status == .committed)
                        self._status = .ready
                        return self.completedHandlers
                    }
                    handlers.forEach { $0(self) }
                }

                buffer.commit()
                self._status = .committed
                return true
            }
        }
        return false
    }

    func endEncoder(_ encoder: MetalCommandEncoder) {
        self.lock.withLock {
            if self._status != .encoding {
                Log.warning("CommandBuffer was not in encoding state.")
            }
            self._status = .ready
            self.encodings.append(.encoder(encoder))
        }
    }
}
#endif //if ENABLE_METAL
