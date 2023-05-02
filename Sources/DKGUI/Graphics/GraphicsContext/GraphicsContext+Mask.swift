//
//  File: GraphicsContext+Mask.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var inverse = ClipOptions(rawValue: 1)
    }

    public mutating func clip(to path: Path,
                              style: FillStyle = FillStyle(),
                              options: ClipOptions = ClipOptions()) {
        let resolution = self.resolution
        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        let device = self.commandBuffer.device
        if let maskTexture = device.makeTexture(
            descriptor: TextureDescriptor(textureType: .type2D,
                                          pixelFormat: .r8Unorm,
                                          width: width,
                                          height: height,
                                          usage: [.renderTarget, .sampled])) {
            if let encoder = self.makeEncoder(renderTarget: maskTexture,
                                              enableStencil: true,
                                              clear: true) {
                if self.encodeStencilPathFillCommand(path, encoder: encoder) {

                    let makeVertex = { x, y in
                        _Vertex(position: Vector2(x, y).float2,
                                texcoord: Vector2.zero.float2,
                                color: DKGame.Color.white.float4)
                    }
                    let vertices: [_Vertex] = [
                        makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                        makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
                    ]

                    let stencil: _Stencil
                    if options.contains(.inverse) {
                        stencil = style.isEOFilled ? .testOdd : .testZero
                    } else {
                        stencil = style.isEOFilled ? .testEven : .testNonZero
                    }
                    self.encodeDrawCommand(shader: .vertexColor,
                                           stencil: stencil,
                                           vertices: vertices,
                                           texture: nil,
                                           blendState: .alphaBlend,
                                           encoder: encoder)

                    self.clipBoundingRect = self.clipBoundingRect.union(path.boundingBoxOfPath)
                    self.maskTexture = maskTexture
                }
                encoder.endEncoding()
            } else {
                Log.error("GraphicsContext.makeEncoder failed.")
            }
        } else {
            Log.err("GraphicsContext error: makeTexture failed.")
        }
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                if let maskTexture = self._resolveMaskTexture(
                    self.maskTexture,
                    context.backdrop,
                    opacity: self.opacity,
                    inverse: options.contains(.inverse)) {
                    self.maskTexture = maskTexture
                } else {
                    Log.err("GraphicsContext error: unable to resolve mask image.")
                }
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    func _resolveMaskTexture(_ texture1: Texture, _ texture2: Texture, opacity: Double, inverse: Bool) -> Texture? {
        fatalError("Not implemented")
    }
}
