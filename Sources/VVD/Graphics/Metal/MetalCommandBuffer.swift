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

final class MetalCommandBuffer: CommandBuffer {
    let commandQueue: CommandQueue
    var device: GraphicsDevice   { commandQueue.device }

    var encoders: [MetalCommandEncoder] = []
    var completedHandlers: [CommandBufferHandler] = []

    init(queue: MetalCommandQueue) {
        self.commandQueue = queue
    }

    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder? {
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

        return MetalRenderCommandEncoder(buffer: self, descriptor: desc)
    }

    func makeComputeCommandEncoder() -> ComputeCommandEncoder? {
        return MetalComputeCommandEncoder(buffer: self)
    }

    func makeCopyCommandEncoder() -> CopyCommandEncoder? {
        return MetalCopyCommandEncoder(buffer: self)
    }

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler) {
        self.completedHandlers.append(handler)
    }

    func commit() -> Bool {
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
