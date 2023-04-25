//
//  File: GraphicsContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct GraphicsContext {

    public var opacity: Double
    public var blendMode: BlendMode
    public internal(set) var environment: EnvironmentValues
    public var transform: CGAffineTransform

    // MARK: -
    var viewTransform: CGAffineTransform
    var contentOffset: CGPoint {
        didSet {
            let origin = self.contentOffset
            let scale = self.contentScale
            let offset = CGAffineTransform(translationX: origin.x, y: origin.y)
            let normalize = CGAffineTransform(scaleX: 1.0 / scale.width, y: 1.0 / scale.height)

            // transform to screen viewport space.
            let clipSpace = CGAffineTransform(scaleX: 2.0, y: -2.0)
                .concatenating(CGAffineTransform(translationX: -1.0, y: 1.0))

            self.viewTransform = CGAffineTransform.identity
                .concatenating(offset)
                .concatenating(normalize)
                .concatenating(clipSpace)
        }
    }
    let contentScale: CGSize
    let commandBuffer: CommandBuffer
    let backBuffer: Texture
    let stencilBuffer: Texture
    var maskTexture: Texture

    var resolution: CGSize {
        CGSize(width: self.backBuffer.width, height: self.backBuffer.height)
    }

    let sharedContext: SharedContext

    init?(sharedContext: SharedContext,
          environment: EnvironmentValues,
          contentOffset: CGPoint,
          contentScale: CGSize,
          transform: CGAffineTransform = .identity,
          resolution: CGSize,
          commandBuffer: CommandBuffer,
          backBuffer: Texture? = nil,
          stencilBuffer: Texture? = nil) {
        self.sharedContext = sharedContext
        self.opacity = 1
        self.blendMode = .normal
        self.transform = transform
        self.environment = environment
        self.commandBuffer = commandBuffer
        self.contentScale = .maximum(contentScale, CGSize(width: 1, height: 1))

        let device = commandBuffer.device

        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        assert(width > 0 && height > 0)

        if let backBuffer = backBuffer {
            assert(backBuffer.dimensions == (width, height, 1))
            self.backBuffer = backBuffer
        } else {
            guard let backBuffer = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .rgba8Unorm,
                                              width: width,
                                              height: height,
                                              usage: [.renderTarget, .sampled])) else {
                Log.err("GraphicsContext error: makeTexture failed.")
                return nil
            }
            if let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: RenderPassDescriptor(colorAttachments: [
                    RenderPassColorAttachmentDescriptor(renderTarget: backBuffer,
                                                        loadAction: .clear,
                                                        storeAction: .store)])) {
                encoder.endEncoding()
            } else {
                Log.err("GraphicsContext warning: makeRenderCommandEncoder failed.")
            }
            self.backBuffer = backBuffer
        }

        if let stencilBuffer {
            assert(stencilBuffer.dimensions == (width, height, 1))
            self.stencilBuffer = stencilBuffer
        } else {
            let width = self.backBuffer.width
            let height = self.backBuffer.height
            if let stencilBuffer = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .stencil8,
                                              width: width,
                                              height: height,
                                              usage: [.renderTarget])) {
                self.stencilBuffer = stencilBuffer
            } else {
                Log.err("GraphicsContext error: makeTexture failed.")
                return nil
            }
        }
        assert(self.backBuffer.dimensions == self.stencilBuffer.dimensions)

        let queue = commandBuffer.commandQueue
        guard let maskTexture = GraphicsPipelineStates.sharedInstance(
            commandQueue: queue)?.defaultMaskTexture
        else {
            Log.err("GraphicsPipelineStates error")
            return nil
        }
        self.maskTexture = maskTexture

        self.contentOffset = .zero
        self.viewTransform = .identity

        defer {
            // contentOffset.didSet will be called.
            self.contentOffset = contentOffset
        }
    }

    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.scaledBy(x: x, y: y)
    }

    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.translatedBy(x: x, y: y)
    }

    public mutating func rotate(by angle: Angle) {
        self.transform = self.transform.rotated(by: angle.radians)
    }

    public mutating func concatenate(_ matrix: CGAffineTransform) {
        self.transform = self.transform.concatenating(matrix)
    }

    public var clipBoundingRect: CGRect = .zero

    var unfilteredBackBuffer: Texture? = nil
    var filters: [(Filter, FilterOptions)] = []
}
