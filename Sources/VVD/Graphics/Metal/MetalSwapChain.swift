//
//  File: MetalSwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal
import QuartzCore

final class MetalSwapChain: SwapChain, @unchecked Sendable {

    let window: Window
    let queue: MetalCommandQueue
    var layer: CAMetalLayer

    private var _pixelFormat: PixelFormat
    var pixelFormat: PixelFormat {
        get { _pixelFormat }
        set {
            switch newValue {
            case .bgra8Unorm, .bgra8Unorm_srgb, .rgba16Float:
                break
            default:    // invalid format!
                Log.err("Invalid pixelFormat!")
                return
            }

            if (newValue != _pixelFormat)
            {
                _pixelFormat = newValue
                self.drawable = nil
            }
        }
    }
    var drawable: CAMetalDrawable?
    var renderPassDescriptor: RenderPassDescriptor

    var commandQueue: CommandQueue { queue }
    var maximumBufferCount: Int { self.layer.maximumDrawableCount }

    @MainActor
    init?(queue: MetalCommandQueue, window: Window) {
        self.window = window
        self.queue = queue

        self._pixelFormat = .bgra8Unorm
        self.renderPassDescriptor = RenderPassDescriptor()

        var layer: CAMetalLayer? = nil
#if ENABLE_APPKIT
        if layer == nil {
            if let view = (self.window as? AppKitWindow)?.view {
                layer = CAMetalLayer()
                view.wantsLayer = true
                view.layer = layer
                if let window = view.window {
                    layer!.contentsScale = window.backingScaleFactor
                }
                layer!.frame = view.bounds
            }
        }
#endif
#if ENABLE_UIKIT
        if layer == nil {
            if let window = self.window as? UIKitWindow {
                layer = window.view.layer as? CAMetalLayer
            }
        }
#endif
        guard let layer = layer else { return nil }

        self.layer = layer
        layer.device = self.queue.queue.device
        layer.pixelFormat = pixelFormat.mtlPixelFormat()

        window.addEventObserver(self) { [weak self](event: WindowEvent) in
            if event.type == .resized {
                if let self = self {
                    self.handleWindowEvent(event)
                }
            }
        }
    }

    func currentRenderPassDescriptor() -> RenderPassDescriptor {
        if self.drawable == nil {
            self.setupFrame()
        }
        return renderPassDescriptor
    }

    func setupFrame() {
        if self.drawable == nil {
            self.renderPassDescriptor.colorAttachments.removeAll()
            self.renderPassDescriptor.depthStencilAttachment.renderTarget = nil
            self.layer.pixelFormat = pixelFormat.mtlPixelFormat()

            let frame = self.layer.frame
            assert(frame.width > 0 && frame.height > 0)

            self.drawable = self.layer.nextDrawable()
        }
        if let drawable = self.drawable {
            self.renderPassDescriptor.colorAttachments.removeAll()
            self.renderPassDescriptor.depthStencilAttachment.renderTarget = nil

            // setup color-attachment
            let texture: MTLTexture = drawable.texture
            let renderTarget = MetalTexture(device: self.queue.device as! MetalGraphicsDevice,
                                            texture: texture)

            var colorAttachment = RenderPassColorAttachmentDescriptor()
            colorAttachment.renderTarget = renderTarget
            colorAttachment.clearColor = Color(0, 0, 0, 0)
            colorAttachment.loadAction = .clear
            colorAttachment.storeAction = .store // default for color-attachment

            renderPassDescriptor.colorAttachments.append(colorAttachment)

            // no depth stencil attachment
            renderPassDescriptor.depthStencilAttachment.renderTarget = nil
            renderPassDescriptor.depthStencilAttachment.clearDepth = 1.0  // default clear-depth value
            renderPassDescriptor.depthStencilAttachment.clearStencil = 0  // default clear-stencil value
            renderPassDescriptor.depthStencilAttachment.loadAction = .clear
            renderPassDescriptor.depthStencilAttachment.storeAction = .dontCare  // default for depth-stencil
        }
    }

    func present(waitEvents: [GPUEvent]) -> Bool {
        if waitEvents.isEmpty {
            if let drawable = drawable {
                drawable.present()
                self.drawable = nil
                return true
            }
        } else {
            if let buffer = self.queue.queue.makeCommandBuffer() {
                for event in waitEvents {
                    assert(event is MetalEvent)

                    if let event: MetalEvent = event as? MetalEvent {
                        buffer.encodeWaitForEvent(event.event, value: event.nextWaitValue())
                    }
                }
                if let drawable = drawable {
                    buffer.present(drawable)
                    buffer.commit()
                    self.drawable = nil
                    return true
                }
            } else {
                Log.err("MTLCommandQueue.makeCommandBuffer failed!")
            }
        }
        return false
    }

    func handleWindowEvent(_ event: WindowEvent) {
        if event.type == .resized {
            // update
            let contentScale = event.contentScaleFactor
            let bounds = event.contentBounds
            let resolution = event.contentBounds.size * contentScale

            self.layer.contentsScale = contentScale
            self.layer.bounds = bounds
            self.layer.drawableSize = resolution
        }
    }
}
#endif //if ENABLE_METAL
