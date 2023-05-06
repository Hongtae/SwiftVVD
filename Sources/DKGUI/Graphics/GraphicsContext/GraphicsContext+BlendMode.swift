//
//  File: GraphicsContext+BlendMode.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {

    public struct BlendMode: RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static var normal            = BlendMode(rawValue: 0)
        public static var multiply          = BlendMode(rawValue: 1)
        public static var screen            = BlendMode(rawValue: 2)
        public static var overlay           = BlendMode(rawValue: 3)
        public static var darken            = BlendMode(rawValue: 4)
        public static var lighten           = BlendMode(rawValue: 5)
        public static var colorDodge        = BlendMode(rawValue: 6)
        public static var colorBurn         = BlendMode(rawValue: 7)
        public static var softLight         = BlendMode(rawValue: 8)
        public static var hardLight         = BlendMode(rawValue: 9)
        public static var difference        = BlendMode(rawValue: 10)
        public static var exclusion         = BlendMode(rawValue: 11)
        public static var hue               = BlendMode(rawValue: 12)
        public static var saturation        = BlendMode(rawValue: 13)
        public static var color             = BlendMode(rawValue: 14)
        public static var luminosity        = BlendMode(rawValue: 15)
        public static var clear             = BlendMode(rawValue: 16)
        public static var copy              = BlendMode(rawValue: 17)
        public static var sourceIn          = BlendMode(rawValue: 18)
        public static var sourceOut         = BlendMode(rawValue: 19)
        public static var sourceAtop        = BlendMode(rawValue: 20)
        public static var destinationOver   = BlendMode(rawValue: 21)
        public static var destinationIn     = BlendMode(rawValue: 22)
        public static var destinationOut    = BlendMode(rawValue: 23)
        public static var destinationAtop   = BlendMode(rawValue: 24)
        public static var xor               = BlendMode(rawValue: 25)
        public static var plusDarker        = BlendMode(rawValue: 26)
        public static var plusLighter       = BlendMode(rawValue: 27)
    }

    // references:
    //  https://developer.apple.com/documentation/coregraphics/cgblendmode/
    //  https://www.w3.org/TR/compositing/#blending
    // GLSL:
    //  https://hg.mozilla.org/mozilla-central/file/tip/gfx/wr/webrender/res/cs_svg_filter.glsl
    //  https://fossies.org/linux/firefox/gfx/wr/webrender/res/cs_svg_filter.glsl

    var blendState: BlendState {
        BlendMode.singlePassBlendModeStates[self.blendMode, default: .opaque]
    }

    func applyBlendModeAndMask() {
        if let encoder = self.makeEncoderCompositionTarget() {
            let shader: _Shader
            switch self.blendMode {
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

            let color = DKGame.Color(white: 1, opacity: self.opacity).float4
            let makeVertex = { x, y, u, v in
                _Vertex(position: Vector2(x, y).float2,
                        texcoord: Vector2(u, v).float2,
                        color: color)
            }

            let invW = 1.0 / CGFloat(self.renderTargets.width)
            let invH = 1.0 / CGFloat(self.renderTargets.height)
            let u1 = self.viewport.minX * invW
            let u2 = self.viewport.maxX * invW
            let v1 = self.viewport.minY * invH
            let v2 = self.viewport.maxY * invH
            let vertices = [
                makeVertex(-1, -1, u1, v2),
                makeVertex(-1,  1, u1, v1),
                makeVertex( 1, -1, u2, v2),
                makeVertex( 1, -1, u2, v2),
                makeVertex(-1,  1, u1, v1),
                makeVertex( 1,  1, u2, v1)
            ]

            let blendSrc = self.renderTargets.source
            let blendDst = self.renderTargets.backdrop
            let blendResult = self.renderTargets.composited

            guard let renderState = pipeline.renderState(
                shader: shader,
                colorFormat: self.renderTargets.colorFormat,
                depthFormat: .invalid,
                blendState: .opaque) else {
                Log.err("GraphicsContext error: pipeline.renderState failed.")
                return
            }
            guard let depthState = pipeline.depthStencilState(.ignore) else {
                Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
                return
            }
            guard let vertexBuffer = self.makeBuffer(vertices) else {
                Log.err("GraphicsContext error: _makeBuffer failed.")
                return
            }

            encoder.setRenderPipelineState(renderState)
            encoder.setDepthStencilState(depthState)

            pipeline.defaultBindingSet2.setTexture(blendSrc, binding: 0)
            pipeline.defaultBindingSet2.setTexture(blendDst, binding: 1)
            pipeline.defaultBindingSet2.setSamplerState(pipeline.defaultSampler, binding: 0)
            pipeline.defaultBindingSet2.setSamplerState(pipeline.defaultSampler, binding: 1)
            encoder.setResource(pipeline.defaultBindingSet2, atIndex: 0)

            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)
            encoder.setStencilReferenceValue(0)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            encoder.draw(vertexStart: 0,
                         vertexCount: vertices.count,
                         instanceCount: 1,
                         baseInstance: 0)
            encoder.endEncoding()

            // swap buffers
            self.renderTargets.backdrop = blendResult
            self.renderTargets.composited = blendDst
        } else {
            Log.error("makeEncoder failed!")
        }
    }
}

extension GraphicsContext.BlendMode: Hashable {
    static let singlePassBlendModeStates: [Self: BlendState] = [
        .copy: BlendState(
            sourceBlendFactor: .one,
            destinationBlendFactor: .zero,
            blendOperation: .add),
        .sourceIn: BlendState(
            sourceBlendFactor: .destinationAlpha,
            destinationBlendFactor: .zero,
            blendOperation: .add),
        .sourceOut: BlendState(
            sourceBlendFactor: .oneMinusDestinationAlpha,
            destinationBlendFactor: .zero,
            blendOperation: .add),
        .sourceAtop: BlendState(
            sourceBlendFactor: .destinationAlpha,
            destinationBlendFactor: .oneMinusSourceAlpha,
            blendOperation: .add),
        .destinationOver: BlendState(
            sourceBlendFactor: .oneMinusDestinationAlpha,
            destinationBlendFactor: .one,
            blendOperation: .add),
        .destinationIn: BlendState(
            sourceBlendFactor: .zero,
            destinationBlendFactor: .sourceAlpha,
            blendOperation: .add),
        .destinationOut: BlendState(
            sourceBlendFactor: .zero,
            destinationBlendFactor: .oneMinusSourceAlpha,
            blendOperation: .add),
        .destinationAtop: BlendState(
            sourceBlendFactor: .oneMinusDestinationAlpha,
            destinationBlendFactor: .sourceAlpha,
            blendOperation: .add),
        .xor: BlendState(
            sourceBlendFactor: .oneMinusDestinationAlpha,
            destinationBlendFactor: .oneMinusSourceAlpha,
            blendOperation: .add),
        .plusLighter: BlendState(
            sourceBlendFactor: .one,
            destinationBlendFactor: .one,
            blendOperation: .add)
    ]
}
