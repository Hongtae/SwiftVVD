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

    // https://developer.apple.com/documentation/coregraphics/cgblendmode/
    //   R is the premultiplied result
    //   S is the source color, and includes alpha
    //   D is the destination color, and includes alpha
    //   Ra, Sa, and Da are the alpha components of R, S, and D
    //
    //  formula: https://www.w3.org/TR/compositing/
    //  for GLSL: https://github.com/jamieowen/glsl-blend
    //
    // simple composition color, alpha(opacity):
    //  R = S * Sa + D * (1-Sa)
    //  Ra = Sa + Da * (1-Sa)
    //
    // normal:      
    // multiply:    S * D
    // screen:      1-(1-S)(1-D)
    // overlay:     if (S < 0.5) { 2SD } else { 1-2(1-S)(1-D) }
    // darken:      MIN(S, D)
    // lighten:     MAX(S, D)
    // colorDodge:  B/(1-A)
    // colorBurn:   1-(1-B)/A
    // softLight:
    // hardLight:
    // difference:      abs(S-A)
    // exclusion:       S*(1-D) + D*(1-S) => S+D-2*S*D
    // hue:
    // saturation:
    // color:
    // luminosity:
    // clear:           R = 0
    // copy:            R = S
    // sourceIn:        R = S*Da
    // sourceOut:       R = S*(1 - Da)
    // sourceAtop:      R = S*Da + D*(1 - Sa)
    // destinationOver: R = S*(1 - Da) + D
    // destinationIn:   R = D*Sa
    // destinationOut:  R = D*(1 - Sa)
    // destinationAtop: R = S*(1 - Da) + D*Sa
    // xor:             R = S*(1 - Da) + D*(1 - Sa)
    // plusDarker:      R = MAX(0, 1 - ((1 - D) + (1 - S)))
    // plusLighter:     R = MIN(1, S + D)

    var isSinglePassBlending: Bool {
        BlendMode.singlePassBlendModeStates[self.blendMode] != nil
    }

    var blendState: BlendState {
        BlendMode.singlePassBlendModeStates[self.blendMode, default: .opaque]
    }

    func applyBlendModeAndMask() {
        if isSinglePassBlending == false {

            let blendSrc = self.renderTargets.source
            let blendDst = self.renderTargets.backdrop
            let blendResult = self.renderTargets.composited

            if self.renderTargets.initialized {
                if let encoder = self.makeEncoder(renderTarget: blendResult,
                                                  enableStencil: false,
                                                  clear: true) {
                    let shader: _Shader
                    switch self.blendMode {
                    case .normal:   shader = .blendNormal
                    case .multiply: shader = .blendMultiply
                    default:
                        shader = .blendNormal
                    }

                    let color = DKGame.Color(1, 1, 1, self.opacity).float4
                    let makeVertex = { x, y, u, v in
                        _Vertex(position: Vector2(x, y).float2,
                                texcoord: Vector2(u, v).float2,
                                color: color)
                    }
                    let vertices = [
                        makeVertex(-1, -1, 0, 1), makeVertex(-1, 1, 0, 0), makeVertex(1, -1, 1, 1),
                        makeVertex(1, -1, 1, 1), makeVertex(-1, 1, 0, 0), makeVertex(1, 1, 1, 0)
                    ]

                    self.encodeDrawCommand(shader: shader,
                                           stencil: .ignore,
                                           vertices: vertices,
                                           indices: nil,
                                           texture: blendSrc,
                                           texture2: blendDst,
                                           blendState: .opaque,
                                           encoder: encoder)
                    encoder.endEncoding()
                    self.renderTargets.backdrop = blendResult
                    self.renderTargets.composited = blendDst
                } else {
                    Log.error("makeEncoder failed!")
                    self.renderTargets.backdrop = blendSrc
                    self.renderTargets.source = blendDst
                    self.renderTargets.initialized = true
                }
            } else {
                self.renderTargets.backdrop = blendSrc
                self.renderTargets.source = blendDst
                self.renderTargets.initialized = true
            }
        }
//        else {    // single pass blending
//            self.renderTargets.initialized = true
//        }
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
