//
//  File: GraphicsContext+Layer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    func makeLayerContext() -> Self? {
        let context = GraphicsContext(
            sharedContext: self.sharedContext,
            environment: self.environment,
            viewport: self.viewport,
            contentOffset: self.contentOffset,
            contentScaleFactor: self.contentScaleFactor,
            resolution: self.resolution,
            commandBuffer: self.commandBuffer)
        context?.clear(with: .clear)
        return context
    }

    func makeLayerContext(_ size: CGSize) -> Self? {
        let width = size.width * self.contentScaleFactor
        let height = size.height * self.contentScaleFactor

        guard width > 0 && height > 0 else { return nil }

        let context = GraphicsContext(
            sharedContext: self.sharedContext,
            environment: self.environment,
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero,
            contentScaleFactor: self.contentScaleFactor,
            resolution: CGSize(width: width, height: height),
            commandBuffer: self.commandBuffer)
        context?.clear(with: .clear)
        return context
    }

    func drawLayer(in frame: CGRect, content: (inout GraphicsContext, CGSize) throws -> Void) rethrows {
        if frame.minX > self.viewport.maxX * self.contentScaleFactor ||
            frame.minY > self.viewport.maxY * self.contentScaleFactor {
            return
        }

        if var context = self.makeLayerContext(frame.size) {
            let size = context.resolution / context.contentScaleFactor
            try content(&context, size)
            let texture = context.backdrop

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: frame,
                                              transform: .identity,
                                              textureFrame: context.viewport,
                                              textureTransform: .identity,
                                              blendState: .opaque,
                                              color: .white)
                renderPass.end()
                self.drawSource()
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            try content(&context)
            let offset = -context.contentOffset
            let scale = context.viewport.size / context.contentScaleFactor
            let texture = context.backdrop

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: CGRect(origin: offset,
                                                            size: scale),
                                              textureFrame: context.viewport,
                                              blendState: .opaque,
                                              color: .white)
                renderPass.end()
                self.drawSource()
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }
}
