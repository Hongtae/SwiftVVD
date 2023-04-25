//
//  File: GraphicsContext+Layer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
    func makeLayerContext() -> Self? {
        return GraphicsContext(sharedContext: self.sharedContext,
                               environment: self.environment,
                               contentOffset: self.contentOffset,
                               contentScale: self.contentScale,
                               transform: self.transform,
                               resolution: self.resolution,
                               commandBuffer: self.commandBuffer,
                               backBuffer: nil, /* to make new buffer */
                               stencilBuffer: self.stencilBuffer)
    }

    func makeRegionLayerContext(_ frame: CGRect) -> Self? {
        let frame = frame.standardized

        let resolution = self.resolution
        let width = resolution.width * (frame.width / self.contentScale.width)
        let height = resolution.height * (frame.height / self.contentScale.height)

        var stencil: Texture? = nil
        if width.rounded() == resolution.width.rounded() &&
           height.rounded() == resolution.height.rounded() {
            stencil = self.stencilBuffer
        }
        return GraphicsContext(sharedContext: self.sharedContext,
                               environment: self.environment,
                               contentOffset: .zero,
                               contentScale: frame.size,
                               transform: self.transform,
                               resolution: CGSize(width: width, height: height),
                               commandBuffer: self.commandBuffer,
                               backBuffer: nil,
                               stencilBuffer: stencil)
    }

    func drawLayer(in frame: CGRect, content: (inout GraphicsContext, CGSize) throws -> Void) rethrows {
        if var context = self.makeRegionLayerContext(frame) {
            do {
                try content(&context, context.contentScale)
                let texture = context.backBuffer

                // FIXME:  Use the correct blendState for the blendMode.
                let blendState: BlendState = .alphaBlend
                self._draw(texture: texture,
                           in: frame,
                           transform: .identity,
                           textureFrame: CGRect(x: 0, y: 0,
                                                width: texture.width,
                                                height: texture.height),
                           textureTransform: .identity,
                           blendState: blendState,
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                let offset = -context.contentOffset
                let scale = context.contentScale
                let texture = context.backBuffer

                // FIXME:  Use the correct blendState for the blendMode.
                let blendState: BlendState = .alphaBlend

                self._draw(texture: texture,
                           in: CGRect(origin: offset, size: scale),
                           transform: .identity,
                           textureFrame: CGRect(x: 0, y: 0,
                                                width: texture.width,
                                                height: texture.height),
                           textureTransform: .identity,
                           blendState: blendState,
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }
}
