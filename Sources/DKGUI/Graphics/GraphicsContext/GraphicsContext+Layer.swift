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
        GraphicsContext(sharedContext: self.sharedContext,
                        environment: self.environment,
                        viewport: self.viewport,
                        contentOffset: self.contentOffset,
                        contentScaleFactor: self.contentScaleFactor,
                        resolution: self.resolution,
                        commandBuffer: self.commandBuffer)
    }

    func makeRegionLayerContext(_ frame: CGRect) -> Self? {
        let frame = frame.standardized

        let width = frame.width * self.contentScaleFactor
        let height = frame.height * self.contentScaleFactor

        return GraphicsContext(sharedContext: self.sharedContext,
                               environment: self.environment,
                               viewport: CGRect(x: 0, y: 0, width: width, height: height),
                               contentOffset: .zero,
                               contentScaleFactor: self.contentScaleFactor,
                               resolution: CGSize(width: width, height: height),
                               commandBuffer: self.commandBuffer)
    }

    func drawLayer(in frame: CGRect, content: (inout GraphicsContext, CGSize) throws -> Void) rethrows {
        if var context = self.makeRegionLayerContext(frame) {
            do {
                let size = context.resolution / context.contentScaleFactor
                try content(&context, size)
                if context.renderTargets.initialized {
                    let texture = context.backdrop

                    if let encoder = self.makeEncoder(enableStencil: false) {
                        let textureFrame = CGRect(x: 0, y: 0,
                                                  width: texture.width,
                                                  height: texture.height)
                        self.encodeDrawTextureCommand(
                            texture: texture,
                            in: frame,
                            transform: .identity,
                            textureFrame: textureFrame,
                            textureTransform: .identity,
                            blendState: self.blendState,
                            color: .white,
                            encoder: encoder)
                        encoder.endEncoding()

                        self.applyFilters()
                        self.applyBlendModeAndMask()
                    }
                }
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
                if context.renderTargets.initialized {
                    let offset = -context.contentOffset
                    let scale = context.resolution / context.contentScaleFactor
                    let texture = context.backdrop

                    let textureFrame = CGRect(x: 0, y: 0,
                                              width: texture.width,
                                              height: texture.height)

                    if let encoder = self.makeEncoder(enableStencil: false) {
                        self.encodeDrawTextureCommand(
                            texture: texture,
                            in: CGRect(origin: offset, size: scale),
                            textureFrame: textureFrame,
                            blendState: self.blendState,
                            color: .white,
                            encoder: encoder)
                        encoder.endEncoding()

                        self.applyFilters()
                        self.applyBlendModeAndMask()
                    }
                }
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }
}
