//
//  File: MetalCommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
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

final class MetalCommandBuffer: CommandBuffer {
    public let commandQueue: CommandQueue
    public var device: GraphicsDevice   { commandQueue.device }

    var encoders: [MetalCommandEncoder] = []
    var completedHandlers: [CommandBufferHandler] = []

    init(queue: MetalCommandQueue) {
        self.commandQueue = queue
    }

    public func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {

        let mtlLoadAction = { (action: RenderPassAttachmentLoadAction) -> MTLLoadAction in
            switch action {
            case .dontCare:     return .dontCare
            case .load:         return .load
            case .clear:        return .clear
            }
        }

        let mtlStoreAction = { (action: RenderPassAttachmentStoreAction) -> MTLStoreAction in
            switch action {
            case .dontCare:     return .dontCare
            case .store:        return .store
            }
        }

        let desc = MTLRenderPassDescriptor()

        for (i, ca) in descriptor.colorAttachments.enumerated() {
            let attachment = MTLRenderPassColorAttachmentDescriptor()

            if let rt = ca.renderTarget as? MetalTexture {
                attachment.texture = rt.texture
            }
            attachment.clearColor = MTLClearColor(red: Double(ca.clearColor.r),
                                                  green: Double(ca.clearColor.g),
                                                  blue: Double(ca.clearColor.b),
                                                  alpha: Double(ca.clearColor.a))
            attachment.loadAction = mtlLoadAction(ca.loadAction)
            attachment.storeAction = mtlStoreAction(ca.storeAction)
            desc.colorAttachments[i] = attachment
        }

        if let rt = descriptor.depthStencilAttachment.renderTarget as? MetalTexture {
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
                desc.depthAttachment = attachment
            }
            if hasStencil {
                let attachment = MTLRenderPassStencilAttachmentDescriptor()
                attachment.texture = rt.texture
                attachment.clearStencil = descriptor.depthStencilAttachment.clearStencil
                attachment.loadAction = mtlLoadAction(descriptor.depthStencilAttachment.loadAction)
                attachment.storeAction = mtlStoreAction(descriptor.depthStencilAttachment.storeAction)
                desc.stencilAttachment = attachment
            }
        }

        return MetalRenderCommandEncoder(buffer: self, descriptor: desc)
    }

    public func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        return MetalComputeCommandEncoder(buffer: self)
    }

    public func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return MetalCopyCommandEncoder(buffer: self)
    }

    public func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        self.completedHandlers.append(handler)
    }

    public func commit() -> Bool {
        if let queue = (self.commandQueue as? MetalCommandQueue)?.queue {
            if let buffer = queue.makeCommandBuffer() {

                for enc in self.encoders {
                    if enc.encode(buffer) == false {
                        return false
                    }
                }

                buffer.addCompletedHandler { _ in
                    self.completedHandlers.forEach { $0(self) }
                }

                buffer.commit()
                return true
            }
        }
        return false
    }

    func endEncoder(_ encoder: MetalCommandEncoder) {
        self.encoders.append(encoder)
    }
}
#endif //if ENABLE_METAL
