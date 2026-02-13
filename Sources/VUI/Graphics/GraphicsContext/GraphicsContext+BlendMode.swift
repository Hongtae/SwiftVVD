//
//  File: GraphicsContext+BlendMode.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {

    public struct BlendMode: RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static var normal: BlendMode             { .init(rawValue: 0) }
        public static var multiply: BlendMode           { .init(rawValue: 1) }
        public static var screen: BlendMode             { .init(rawValue: 2) }
        public static var overlay: BlendMode            { .init(rawValue: 3) }
        public static var darken: BlendMode             { .init(rawValue: 4) }
        public static var lighten: BlendMode            { .init(rawValue: 5) }
        public static var colorDodge: BlendMode         { .init(rawValue: 6) }
        public static var colorBurn: BlendMode          { .init(rawValue: 7) }
        public static var softLight: BlendMode          { .init(rawValue: 8) }
        public static var hardLight: BlendMode          { .init(rawValue: 9) }
        public static var difference: BlendMode         { .init(rawValue: 10) }
        public static var exclusion: BlendMode          { .init(rawValue: 11) }
        public static var hue: BlendMode                { .init(rawValue: 12) }
        public static var saturation: BlendMode         { .init(rawValue: 13) }
        public static var color: BlendMode              { .init(rawValue: 14) }
        public static var luminosity: BlendMode         { .init(rawValue: 15) }
        public static var clear: BlendMode              { .init(rawValue: 16) }
        public static var copy: BlendMode               { .init(rawValue: 17) }
        public static var sourceIn: BlendMode           { .init(rawValue: 18) }
        public static var sourceOut: BlendMode          { .init(rawValue: 19) }
        public static var sourceAtop: BlendMode         { .init(rawValue: 20) }
        public static var destinationOver: BlendMode    { .init(rawValue: 21) }
        public static var destinationIn: BlendMode      { .init(rawValue: 22) }
        public static var destinationOut: BlendMode     { .init(rawValue: 23) }
        public static var destinationAtop: BlendMode    { .init(rawValue: 24) }
        public static var xor: BlendMode                { .init(rawValue: 25) }
        public static var plusDarker: BlendMode         { .init(rawValue: 26) }
        public static var plusLighter: BlendMode        { .init(rawValue: 27) }
    }

    // references:
    //  https://developer.apple.com/documentation/coregraphics/cgblendmode/
    //  https://www.w3.org/TR/compositing/#blending
    //  https://www.w3.org/TR/compositing/#advancedcompositing

    @discardableResult
    func applyBlendMode(blendMode: BlendMode? = nil,
                        opacity: Double? = nil,
                        applyMask: Bool) -> Bool {
        let blendMode = blendMode ?? self.blendMode

        let blendSrc = self.renderTargets.source
        let blendDst = self.renderTargets.backdrop
        //let blendResult = self.renderTargets.composited

        let opacity = opacity ?? self.opacity
        let color = VVD.Color(white: opacity, opacity: opacity)

        if let renderPass = self.beginRenderPassCompositionTarget() {
            if self.encodeBlendTexturesCommand(renderPass: renderPass,
                                               source: blendSrc,
                                               backdrop: blendDst,
                                               textureFrame: self.viewport,
                                               blendMode: blendMode,
                                               color: color) {
                renderPass.end()

                // swap buffers
                self.renderTargets.switchCompositedToBackdrop()
                return true
            } else {
                Log.error("GraphicsContext.encodeBlendTexturesCommand failed.")
            }
        } else {
            Log.error("GraphicsContext.beginRenderPassCompositionTarget failed!")
        }
        return false
    }

    func encodeBlendTexturesCommand(renderPass: RenderPass,
                                    source: Texture,
                                    backdrop: Texture,
                                    textureFrame: CGRect,
                                    blendMode: BlendMode,
                                    color: VVD.Color) -> Bool {
        if source.dimensions != backdrop.dimensions {
            Log.error("GraphicsContext.encodeBlendTexturesCommand failed.")
            return false
        }

        let shader: _Shader
        switch blendMode {
        case .normal:           shader = .blendNormal
        case .multiply:         shader = .blendMultiply
        case .screen:           shader = .blendScreen
        case .overlay:          shader = .blendOverlay
        case .darken:           shader = .blendDarken
        case .lighten:          shader = .blendLighten
        case .colorDodge:       shader = .blendColorDodge
        case .colorBurn:        shader = .blendColorBurn
        case .softLight:        shader = .blendSoftLight
        case .hardLight:        shader = .blendHardLight
        case .difference:       shader = .blendDifference
        case .exclusion:        shader = .blendExclusion
        case .hue:              shader = .blendHue
        case .saturation:       shader = .blendSaturation
        case .color:            shader = .blendColor
        case .luminosity:       shader = .blendLuminosity
        case .clear:            shader = .blendClear
        case .copy:             shader = .blendCopy
        case .sourceIn:         shader = .blendSourceIn
        case .sourceOut:        shader = .blendSourceOut
        case .sourceAtop:       shader = .blendSourceAtop
        case .destinationOver:  shader = .blendDestinationOver
        case .destinationIn:    shader = .blendDestinationIn
        case .destinationOut:   shader = .blendDestinationOut
        case .destinationAtop:  shader = .blendDestinationAtop
        case .xor:              shader = .blendXor
        case .plusDarker:       shader = .blendPlusDarker
        case .plusLighter:      shader = .blendPlusLighter
        default:                shader = .blendNormal
        }

        let color = color.float4
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(position: Vector2(x, y).float2,
                    texcoord: Vector2(u, v).float2,
                    color: color)
        }

        let invW = 1.0 / CGFloat(source.width)
        let invH = 1.0 / CGFloat(source.height)
        let u1 = textureFrame.minX * invW
        let u2 = textureFrame.maxX * invW
        let v1 = textureFrame.minY * invH
        let v2 = textureFrame.maxY * invH
        let vertices = [
            makeVertex(-1, -1, u1, v2),
            makeVertex(-1,  1, u1, v1),
            makeVertex( 1, -1, u2, v2),
            makeVertex( 1, -1, u2, v2),
            makeVertex(-1,  1, u1, v1),
            makeVertex( 1,  1, u2, v1)
        ]

        guard let renderState = pipeline.renderState(
            shader: shader,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: .opaque,
            sampleCount: renderPass.sampleCount) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.ignore) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
        }
        guard let vertexBuffer = self.makeBuffer(vertices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(renderState)
        encoder.setDepthStencilState(depthState)
        self.bindingSet2.setTexture(source, binding: 0)
        self.bindingSet2.setTexture(backdrop, binding: 1)
        self.bindingSet2.setSamplerState(pipeline.defaultSampler, binding: 0)
        self.bindingSet2.setSamplerState(pipeline.defaultSampler, binding: 1)
        encoder.setResource(self.bindingSet2, index: 0)

        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        encoder.draw(vertexStart: 0,
                     vertexCount: vertices.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }
}
