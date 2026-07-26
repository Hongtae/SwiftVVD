//
//  File: GraphicsContext+Mask.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var inverse: ClipOptions { .init(rawValue: 1) }
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
            let viewport = CGRect(x: 0, y: 0, width: width, height: height)
            if let renderPass = self.beginRenderPass(viewport: viewport,
                                                     renderTarget: maskTexture,
                                                     loadAction: .clear,
                                                     clearColor: .clear,
                                                     useStencil: true,
                                                     useMSAA: false) {
                var didDrawMask = false
                if self.encodeStencilPathFillCommand(renderPass: renderPass,
                                                     path: path) {
                    let makeVertex = { (x: Scalar, y: Scalar) in
                        _Vertex(position: Vector2(x, y).float2,
                                texcoord: Vector2.zero.float2,
                                color: BackendColor.white.float4)
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
                    self.encodeDrawCommand(renderPass: renderPass,
                                           shader: .vertexColor,
                                           stencil: stencil,
                                           vertices: vertices,
                                           texture: nil,
                                           blendState: .alphaBlend)
                    didDrawMask = true
                }
                renderPass.end()
                if didDrawMask {
                    if self.maskTexture === self.pipeline.defaultMaskTexture {
                        self.maskTexture = maskTexture
                    } else if let resolved = self._resolveR8MaskTexture(
                        self.maskTexture,
                        maskTexture
                    ) {
                        self.maskTexture = resolved
                    } else {
                        Log.err("GraphicsContext error: unable to combine path masks.")
                        return
                    }
                    self.clipBoundingRect = Self.resolvedClipBoundingRect(
                        self.clipBoundingRect,
                        pathBounds: path.boundingBoxOfPath,
                        options: options
                    )
                }
            } else {
                Log.error("GraphicsContext.makeEncoder failed.")
            }
        } else {
            Log.err("GraphicsContext error: makeTexture failed.")
        }
    }

    static func resolvedClipBoundingRect(
        _ current: CGRect,
        pathBounds: CGRect,
        options: ClipOptions
    ) -> CGRect {
        options.contains(.inverse) ? current : current.intersection(pathBounds)
    }

    static func resolvedLayerClipBoundingRect(
        _ current: CGRect,
        layerBounds: CGRect,
        opacity: Double,
        options: ClipOptions
    ) -> CGRect {
        if options.contains(.inverse) { return current }
        if opacity <= 0 || layerBounds.isNull { return .null }
        return current.intersection(layerBounds)
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            try content(&context)
            if let maskTexture = self._resolveMaskTexture(
                self.maskTexture,
                context.backdrop,
                opacity: opacity,
                inverse: options.contains(.inverse)) {
                self.maskTexture = maskTexture
                self.clipBoundingRect = Self.resolvedLayerClipBoundingRect(
                    self.clipBoundingRect,
                    layerBounds: context.contentBoundingRect,
                    opacity: opacity,
                    options: options
                )
            } else {
                Log.err("GraphicsContext error: unable to resolve mask image.")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    func _resolveMaskTexture(
        _ texture1: Texture,
        _ texture2: Texture,
        opacity: Double,
        inverse: Bool
    ) -> Texture? {
        self._resolveMaskTexture(
            texture1,
            texture2,
            sourceShader: .resolveMask,
            opacity: opacity,
            inverse: inverse
        )
    }

    func _resolveR8MaskTexture(_ texture1: Texture, _ texture2: Texture) -> Texture? {
        self._resolveMaskTexture(
            texture1,
            texture2,
            sourceShader: .rcImage,
            opacity: 1,
            inverse: false
        )
    }

    private func _resolveMaskTexture(
        _ texture1: Texture,
        _ texture2: Texture,
        sourceShader: _Shader,
        opacity: Double,
        inverse: Bool
    ) -> Texture? {
        let width = self.renderTargets.width
        let height = self.renderTargets.height
        guard let result = self.commandBuffer.device.makeTexture(
            descriptor: TextureDescriptor(
                textureType: .type2D,
                pixelFormat: .r8Unorm,
                width: width,
                height: height,
                usage: [.renderTarget, .sampled]
            )
        ) else {
            return nil
        }
        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        guard let renderPass = self.beginRenderPass(
            viewport: viewport,
            renderTarget: result,
            loadAction: .clear,
            clearColor: .clear,
            useStencil: false,
            useMSAA: false
        ) else {
            return nil
        }
        self._encodeMaskQuad(
            renderPass: renderPass,
            texture: texture1,
            shader: .image,
            opacity: 1,
            blendState: .opaque
        )
        self._encodeMaskQuad(
            renderPass: renderPass,
            texture: texture2,
            shader: sourceShader,
            opacity: opacity,
            blendState: Self._maskIntersectionBlendState(inverse: inverse)
        )
        renderPass.end()
        return result
    }

    func applyMaskToSource() -> Bool {
        // The shared default mask is fully opaque, so applying it cannot alter
        // source pixels. Preserve the render pass only after a clip installs a
        // context-specific mask.
        if self.maskTexture === self.pipeline.defaultMaskTexture {
            return true
        }
        let width = self.renderTargets.width
        let height = self.renderTargets.height
        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        guard let renderPass = self.beginRenderPass(
            viewport: viewport,
            renderTarget: self.renderTargets.source,
            loadAction: .load,
            clearColor: .clear,
            useStencil: false,
            useMSAA: false
        ) else {
            return false
        }
        self._encodeMaskQuad(
            renderPass: renderPass,
            texture: self.maskTexture,
            shader: .rcImage,
            opacity: 1,
            blendState: Self._maskIntersectionBlendState(inverse: false)
        )
        renderPass.end()
        return true
    }

    private static func _maskIntersectionBlendState(inverse: Bool) -> BlendState {
        let destinationFactor: BlendFactor = inverse ? .oneMinusSourceAlpha : .sourceAlpha
        return BlendState(
            sourceRGBBlendFactor: .zero,
            sourceAlphaBlendFactor: .zero,
            destinationRGBBlendFactor: destinationFactor,
            destinationAlphaBlendFactor: destinationFactor,
            rgbBlendOperation: .add,
            alphaBlendOperation: .add
        )
    }

    private func _encodeMaskQuad(
        renderPass: RenderPass,
        texture: Texture,
        shader: _Shader,
        opacity: Double,
        blendState: BlendState
    ) {
        let color = BackendColor(white: 1, opacity: opacity).float4
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(
                position: Vector2(x, y).float2,
                texcoord: Vector2(u, v).float2,
                color: color
            )
        }
        let vertices: [_Vertex] = [
            makeVertex(-1, -1, 0, 1),
            makeVertex(-1, 1, 0, 0),
            makeVertex(1, -1, 1, 1),
            makeVertex(1, -1, 1, 1),
            makeVertex(-1, 1, 0, 0),
            makeVertex(1, 1, 1, 0),
        ]
        self.encodeDrawCommand(
            renderPass: renderPass,
            shader: shader,
            stencil: .ignore,
            vertices: vertices,
            texture: texture,
            blendState: blendState
        )
    }
}
