//
//  File: GraphicsContext+Filter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
        public struct Filter {
        enum FilterStyle {
            case projectionTransform(matrix: ProjectionTransform)
            case colorMatrix(matrix: ColorMatrix)
            case blur(radius: CGFloat, options: BlurOptions)
            case shadow(color: Color, radius: CGFloat, offset: CGPoint, blendMode: BlendMode, options: ShadowOptions)
        }
        let style: FilterStyle

        public static func projectionTransform(_ matrix: ProjectionTransform) -> Filter {
            Filter(style: .projectionTransform(matrix: matrix))
        }

        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
                                  radius: CGFloat,
                                  x: CGFloat = 0,
                                  y: CGFloat = 0,
                                  blendMode: BlendMode = .normal,
                                  options: ShadowOptions = ShadowOptions()) -> Filter {
            Filter(style: .shadow(color: color,
                                  radius: radius,
                                  offset: CGPoint(x: x, y: y),
                                  blendMode: blendMode,
                                  options: options))
        }

        public static func colorMultiply(_ color: Color) -> Filter {
            let cc = color.dkColor
            var cm = ColorMatrix.identity
            cm.r1 = Float(cc.r)
            cm.g2 = Float(cc.g)
            cm.b3 = Float(cc.b)
            cm.a4 = Float(cc.a)
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorMatrix(_ matrix: ColorMatrix) -> Filter {
            Filter(style: .colorMatrix(matrix: matrix))
        }

        public static func hueRotation(_ angle: Angle) -> Filter {
            let c = Float(cos(angle.radians))
            let s = Float(sin(angle.radians))
            var cm = ColorMatrix.identity

            cm.r1 = 0.213 + c * 0.787 - s * 0.213
            cm.r2 = 0.715 - c * 0.715 - s * 0.715
            cm.r3 = 0.072 - c * 0.072 + s * 0.928

            cm.g1 = 0.213 - c * 0.213 + s * 0.143
            cm.g2 = 0.715 + c * 0.285 + s * 0.140
            cm.g3 = 0.072 - c * 0.072 - s * 0.283

            cm.b1 = 0.213 - c * 0.213 - s * 0.787
            cm.b2 = 0.715 - c * 0.715 + s * 0.715
            cm.b3 = 0.072 + c * 0.928 + s * 0.072

            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func saturation(_ amount: Double) -> Filter {
            let s = Float(amount)
            let sr = (1 - s) * 0.213
            let sg = (1 - s) * 0.715
            let sb = (1 - s) * 0.072
            var cm = ColorMatrix.identity
            cm.r1 = sr + s
            cm.r2 = sg
            cm.r3 = sb
            cm.g1 = sr
            cm.g2 = sg + s
            cm.g3 = sb
            cm.b1 = sr
            cm.b2 = sg
            cm.b3 = sb + s
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func brightness(_ amount: Double) -> Filter {
            let b = Float(amount)
            var cm = ColorMatrix.identity
            cm.r5 = b
            cm.g5 = b
            cm.b5 = b
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func contrast(_ amount: Double) -> Filter {
            let c = Float(amount)
            let t = (1 - c) * 0.5
            var cm = ColorMatrix.identity
            cm.r1 = c
            cm.g2 = c
            cm.b3 = c
            cm.r5 = t
            cm.g5 = t
            cm.b5 = t
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorInvert(_ amount: Double = 1) -> Filter {
            let c = Float(amount)
            let r = 1.0 - c * 2.0
            var cm = ColorMatrix.identity
            cm.r1 = r
            cm.g2 = r
            cm.b2 = r
            cm.r5 = c
            cm.g5 = c
            cm.b5 = c
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func grayscale(_ amount: Double) -> Filter {
            let a = Float(1 - amount)
            var cm = ColorMatrix.identity
            cm.r1 = 0.213 + 0.787 * a
            cm.r2 = 0.715 - 0.715 * a
            cm.r3 = 0.072 - 0.072 * a
            cm.g1 = 0.213 - 0.213 * a
            cm.g2 = 0.715 + 0.285 * a
            cm.g3 = 0.072 - 0.072 * a
            cm.b1 = 0.213 - 0.213 * a
            cm.b2 = 0.715 - 0.715 * a
            cm.b3 = 0.072 + 0.928 * a
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static var luminanceToAlpha: Filter {
            var cm = ColorMatrix.zero
            cm.a1 = 0.2126
            cm.a2 = 0.7152
            cm.a3 = 0.0722
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func blur(radius: CGFloat,
                                options: BlurOptions = BlurOptions()) -> Filter {
            Filter(style: .blur(radius: radius, options: options))
        }

        public static func alphaThreshold(min: Double,
                                          max: Double = 1,
                                          color: Color = Color.black) -> Filter {
            fatalError()
        }
    }

    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var shadowAbove   = ShadowOptions(rawValue: 1)
        public static var shadowOnly    = ShadowOptions(rawValue: 2)
        public static var invertsAlpha  = ShadowOptions(rawValue: 4)
        public static var disablesGroup = ShadowOptions(rawValue: 8)
    }

    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var opaque        = BlurOptions(rawValue: 1)
        public static var dithersResult = BlurOptions(rawValue: 2)
    }

    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var linearColor = FilterOptions(rawValue: 1)
    }

    public mutating func addFilter(_ filter: Filter,
                                   options: FilterOptions = FilterOptions()) {
        filters.append((filter, options))
    }

    func applyFilters(sourceDiscarded: Bool) {
        self.filters.forEach { (filter, options) in
            if case let .shadow(_, _, _, _, opts) = filter.style,
               opts.contains([.disablesGroup, .shadowAbove]) {
            } else {
                applyFilter(filter: filter,
                            options: options,
                            sourceDiscarded: sourceDiscarded)
            }
        }
    }

    func applyLayeredFilters(sourceDiscarded: Bool) {
        self.filters.forEach { (filter, options) in
            if case let .shadow(_, _, _, _, opts) = filter.style,
               opts.contains([.disablesGroup, .shadowAbove]) {
                applyFilter(filter: filter,
                            options: options,
                            sourceDiscarded: sourceDiscarded)
            }
        }
    }

    func applyFilter(filter: Filter,
                     options filterOptions: FilterOptions,
                     sourceDiscarded: Bool) {
        let maxBlurIteration = 3

        let width = CGFloat(self.renderTargets.width)
        let height = CGFloat(self.renderTargets.height)
        let texFrame = CGRect(x: 0, y: 0, width: width, height: height)
        let frame = CGRect(x: 0, y: 0,
                           width: self.viewport.width / self.contentScaleFactor,
                           height: self.viewport.height / self.contentScaleFactor)

        switch filter.style {
        case let .projectionTransform(matrix):
            if matrix.isIdentity { break }
            if let renderPass = self.beginRenderPassCompositionTarget() {
                if self.encodeProjectionTransformFilter(renderPass: renderPass,
                                                        texture: self.sourceTexture,
                                                        textureFrame: texFrame,
                                                        projectionTransform: matrix,
                                                        blendState: .opaque,
                                                        color: .white) {
                    renderPass.end()
                    self.renderTargets.switchSourceToComposited()
                } else {
                    Log.error("GraphicsContext.encodeProjectionTransformFilter failed.")
                }
            } else {
                Log.error("GraphicsContext.beginRenderPassCompositionTarget failed.")
            }
            break
        case let .colorMatrix(matrix):
            if let renderPass = self.beginRenderPassCompositionTarget() {
                if self.encodeColorMatrixFilter(renderPass: renderPass,
                                                frame: frame,
                                                texture: self.sourceTexture,
                                                textureFrame: texFrame,
                                                colorMatrix: matrix,
                                                blendState: .opaque,
                                                color: .white) {
                    renderPass.end()
                    self.renderTargets.switchSourceToComposited()
                } else {
                    Log.error("GraphicsContext.encodeColorMatrixFilter failed.")
                }
            } else {
                Log.error("GraphicsContext.beginRenderPassCompositionTarget failed.")
            }
        case let .blur(radius, options):
            if radius < .ulpOfOne { break }
            for pass in 0..<(maxBlurIteration*2) {
                if let renderPass = self.beginRenderPassCompositionTarget() {
                    let r = radius * CGFloat(pass/2+1) / CGFloat(maxBlurIteration)
                    if self.encodeBlurFilter(renderPass: renderPass,
                                             texture: self.sourceTexture,
                                             textureFrame: texFrame,
                                             radius: r,
                                             options: options,
                                             blurPass: pass,
                                             blendState: .opaque,
                                             color: .white) {
                        renderPass.end()
                        self.renderTargets.switchSourceToComposited()
                    } else {
                        Log.error("GraphicsContext.encodeBlurFilter failed.")
                        break
                    }
                } else {
                    Log.error("GraphicsContext.beginRenderPassCompositionTarget failed.")
                    break
                }
            }
        case let .shadow(color, radius, offset, blendMode, options):
            var colorMatrix = ColorMatrix.zero
            let color = color.dkColor
            colorMatrix.a4 = Float(color.a) // alpha factor (multiply)
            colorMatrix.r5 = Float(color.r) // constant
            colorMatrix.g5 = Float(color.g) // constant
            colorMatrix.b5 = Float(color.b) // constant
            // make solid color copy
            if let renderPass = self.beginRenderPass(viewport: self.viewport,
                                                     renderTarget: self.renderTargets.temporary,
                                                     stencilBuffer: nil,
                                                     loadAction: .clear,
                                                     clearColor: .clear) {
                if self.encodeColorMatrixFilter(renderPass: renderPass,
                                                frame: frame.offsetBy(dx: offset.x, dy: offset.y),
                                                texture: self.sourceTexture,
                                                textureFrame: texFrame,
                                                colorMatrix: colorMatrix,
                                                blendState: .opaque,
                                                color: .white) {
                    renderPass.end()
                    // backup source for later use
                    self.renderTargets.switchTemporaryToSource()
                    // temporary: original image
                    // source: shadow texture
                } else {
                    Log.error("GraphicsContext.encodeColorMatrixFilter failed.")
                    break
                }
            } else {
                Log.error("GraphicsContext.beginRenderPassCompositionTarget failed.")
                break
            }
            // apply blur (the source texture is solid color image)
            applyFilter(filter: .blur(radius: radius), options: filterOptions,
                        sourceDiscarded: sourceDiscarded)

            var disablesGroup = options.contains(.disablesGroup)
            if sourceDiscarded { disablesGroup = true }

            if disablesGroup {
                self.applyBlendMode(blendMode: blendMode, opacity: self.opacity, applyMask: true)
            } else {
                self.renderTargets.switchTemporaryToBackdrop()
                // source: shadow
                // backdrop: original image
                // temporary: original backdrop

                if options.contains(.shadowAbove) {
                } else {
                    self.renderTargets.switchSourceToBackdrop()
                    // source: original image
                    // backdrop: shadow
                }

                if self.applyBlendMode(blendMode: .normal, opacity: 1, applyMask: false) {
                    // restore render targets
                } else {
                    Log.error("GraphicsContext.applyBlendMode failed.")
                }
                self.renderTargets.switchTemporaryToBackdrop()
            }
            self.renderTargets.switchTemporaryToSource()
        }
    }

    func encodeProjectionTransformFilter(renderPass: RenderPass,
                                         texture: Texture,
                                         textureFrame: CGRect,
                                         projectionTransform: ProjectionTransform,
                                         blendState: BlendState,
                                         color: DKGame.Color) -> Bool {

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)

        let makeVertex = { x, y, u, v in
            _Vertex(position: (x, y), texcoord: (u, v), color: color.float4)
        }
        let vertices: [_Vertex] = [
            makeVertex(-1, -1, uvMinX, uvMaxY), // left bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1,  1, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterProjectionTransform,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState) else {
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

        pipeline.defaultBindingSet1.setTexture(texture, binding: 0)
        pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
        encoder.setResource(pipeline.defaultBindingSet1, index: 0)

        withUnsafeBytes(of: projectionTransform) {
            encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
        }
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(vertexStart: 0,
                     vertexCount: vertices.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }

    func encodeColorMatrixFilter(renderPass: RenderPass,
                                 frame: CGRect,
                                 texture: Texture,
                                 textureFrame: CGRect,
                                 colorMatrix: ColorMatrix,
                                 blendState: BlendState,
                                 color: DKGame.Color) -> Bool {
        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)

        let makeVertex = { (x: Scalar, y: Scalar, u: Float, v: Float) in
            _Vertex(position: Vector2(x, y).applying(self.viewTransform).float2,
                    texcoord: (u, v), color: color.float4)
        }
        let frame = frame.standardized
        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY), // left bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterColorMatrix,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState) else {
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

        pipeline.defaultBindingSet1.setTexture(texture, binding: 0)
        pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
        encoder.setResource(pipeline.defaultBindingSet1, index: 0)

        withUnsafeBytes(of: colorMatrix) {
            encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
        }
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(vertexStart: 0,
                     vertexCount: vertices.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }

    func encodeBlurFilter(renderPass: RenderPass,
                          texture: Texture,
                          textureFrame: CGRect,
                          radius: CGFloat,
                          options: BlurOptions,
                          blurPass: Int,
                          blendState: BlendState,
                          color: DKGame.Color) -> Bool {
        struct PushConstant {
            var resolution: Float2
            var direction: Float2
        }
        let radius = Float(radius)
        let blurDirection = blurPass % 2 == 0 ? (radius, 0) : (0, radius)
        let blurParameters = PushConstant(
                            resolution: (Float(texture.width),
                                         Float(texture.height)),
                            direction: blurDirection)

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)
        let uvMinX = Float(textureFrame.minX * invW)
        let uvMaxX = Float(textureFrame.maxX * invW)
        let uvMinY = Float(textureFrame.minY * invH)
        let uvMaxY = Float(textureFrame.maxY * invH)
        let makeVertex = { x, y, u, v in
            _Vertex(position: (x, y), texcoord: (u, v), color: color.float4)
        }
        let vertices: [_Vertex] = [
            makeVertex(-1, -1, uvMinX, uvMaxY), // left bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex( 1, -1, uvMaxX, uvMaxY), // right bottom
            makeVertex(-1,  1, uvMinX, uvMinY), // left top
            makeVertex( 1,  1, uvMaxX, uvMinY), // right top
        ]

        guard let renderState = pipeline.renderState(
            shader: .filterBlur,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState) else {
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

        pipeline.defaultBindingSet1.setTexture(texture, binding: 0)
        pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
        encoder.setResource(pipeline.defaultBindingSet1, index: 0)

        withUnsafeBytes(of: blurParameters) {
            encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
        }
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
