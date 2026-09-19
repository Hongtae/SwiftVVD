//
//  File: GraphicsContext+Primitive.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// A filled, solid-color primitive consumed by the analytic shadow encoder.
// Complex paths, unequal corner axes and continuous corners use path drawing.
struct FilledPrimitive {
    var rect: CGRect
    var kind: UInt32
    var cornerRadius: Float
    var blurRadius: Float = 0
    var color: SIMD4<Float>

    init?(path: Path, color: Color.Resolved) {
        switch path.storage {
        case let .rect(rect):
            self.rect = rect.standardized
            kind = 2
            cornerRadius = 0
        case let .ellipse(rect) where rect.width == rect.height:
            self.rect = rect.standardized
            kind = 5
            cornerRadius = Float(self.rect.height) * 0.5
        case let .roundedRect(rounded) where rounded.style == .circular &&
            rounded.cornerSize.width == rounded.cornerSize.height:
            self.rect = rounded.rect.standardized
            kind = 3
            cornerRadius = min(max(0, Float(rounded.cornerSize.width)),
                min(Float(self.rect.width), Float(self.rect.height)) * 0.5)
        default: return nil
        }
        guard !rect.isEmpty, !rect.isInfinite,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ Float($0).isFinite }) else {
            return nil
        }
        let h = Self.half
        let alpha = h(color.opacity)
        self.color = SIMD4(h(h(color.red) * alpha), h(h(color.green) * alpha),
                           h(h(color.blue) * alpha), alpha)
    }

    private static func half(_ value: Float) -> Float { Float(Float16(value)) }

    func shadow(radius: Float, color: Color.Resolved, itemTransform: CGAffineTransform,
                styleTransform: CGAffineTransform, offset: CGPoint) -> (primitive: Self, transform: CGAffineTransform)? {
        guard radius.isFinite, radius >= 0,
              RBDisplayList.Style.isFiniteInvertible(itemTransform),
              RBDisplayList.Style.isFiniteInvertible(styleTransform) else { return nil }
        let relative = styleTransform.concatenating(itemTransform.inverted())
        let scales = RBDisplayList.Style.axisScales(relative)
        let sigma = radius * ((scales.x + scales.y) * 0.5)
        guard sigma.isFinite else { return nil }
        var result = self
        result.blurRadius = sigma
        let minimum = min(Float(rect.width), Float(rect.height))
        if kind != 5 {
            let amount = Float(1.8) * sigma
            result.cornerRadius = min((cornerRadius * cornerRadius + amount * amount).squareRoot(),
                                      minimum * 0.5)
            result.kind = 3
        }
        var alpha = self.color.w
        let diameter = Float(2.8) * sigma
        if minimum < diameter {
            let t = minimum / diameter
            alpha *= t / Float(0.41422712802886963).addingProduct(0.5857728719711304, t)
        }
        let h = Self.half
        alpha = h(alpha)
        let colorAlpha = h(color.opacity)
        result.color = SIMD4(h(h(h(color.red) * colorAlpha) * alpha),
                             h(h(h(color.green) * colorAlpha) * alpha),
                             h(h(h(color.blue) * colorAlpha) * alpha), h(colorAlpha * alpha))
        var transform = itemTransform
        transform.tx += styleTransform.a * offset.x + styleTransform.c * offset.y
        transform.ty += styleTransform.b * offset.x + styleTransform.d * offset.y
        return (result, transform)
    }
}

extension GraphicsContext {
    func analyticShadowPrimitive(_ path: Path, shading: Shading, style: FillStyle) -> FilledPrimitive? {
        guard style.isAntialiased, !style.isEOFilled,
              storage.state.pointee.maskTexture == nil,
              RBDisplayList.Style.isFiniteInvertible(transform),
              let shadow = storage.state.pointee.style?.executionStyles.first as? RBDisplayList.ShadowStyle,
              shadow.supportsColorOperations, shadow.radius > 0,
              [UInt32(0), 2].contains(shadow.options.rawValue),
              shading.properties.count == 1, case let .color(color) = shading.properties[0] else { return nil }
        return FilledPrimitive(path: path, color: color.resolve(in: environment))
    }

    func encodePrimitive(renderPass: RenderPass, primitive: FilledPrimitive,
                         transform: CGAffineTransform) -> Bool {
        let radius = primitive.blurRadius
        let pixelTransform = transform.concatenating(CGAffineTransform(
            scaleX: contentScaleFactor, y: contentScaleFactor))
        // The dominant component bounds the antialiasing mesh in item space.
        let scale = Float(max(max(abs(pixelTransform.a), abs(pixelTransform.b)),
                              max(abs(pixelTransform.c), abs(pixelTransform.d))))
        let aligned = (pixelTransform.b == 0 && pixelTransform.c == 0) ||
                      (pixelTransform.a == 0 && pixelTransform.d == 0)
        let pixelRect = primitive.rect.applying(pixelTransform)
        let plane = primitive.kind == 2 && aligned &&
            [pixelRect.minX, pixelRect.minY, pixelRect.maxX, pixelRect.maxY].allSatisfy {
                abs($0 - $0.rounded()) < 0.005
            }
        let outset: Float = plane ? 0 : radius > 0 ? Float(1).addingProduct(2.8, radius) : 1 / scale
        guard outset.isFinite else { return false }
        let width = Float(primitive.rect.width)
        let height = Float(primitive.rect.height)
        let expandedWidth = width + 2 * outset
        let expandedHeight = height + 2 * outset
        let frame = CGRect(x: CGFloat(Float(primitive.rect.minX) - outset),
                           y: CGFloat(Float(primitive.rect.minY) - outset),
                           width: CGFloat(expandedWidth), height: CGFloat(expandedHeight))
        let corner = primitive.cornerRadius
        let kind = plane ? UInt32(1) : corner < 0.01 && radius == 0 ? UInt32(2) : primitive.kind
        let inset: Float = kind == 3 ? corner : 0
        let coefficient = radius > 0
            ? Float(Float16(Float(Float16(0.1695573329925537 / radius)) * expandedHeight)) : 0
        // Float words keep the uniform layout portable without requiring
        // native 16-bit storage support from the graphics device.
        let constants: (Float, Float, Float, Float, UInt32, UInt32) = (
            (width * 0.5 - inset) / expandedHeight,
            (height * 0.5 - inset) / expandedHeight,
            corner / expandedHeight, coefficient, kind, radius > 0 ? 2 : 0)
        let matrix = transform.concatenating(viewTransform)
        let color = primitive.color
        let origin = Vector2(frame.minX, frame.minY).applying(matrix).float2
        let axisX = (Float(frame.width * matrix.a), Float(frame.width * matrix.b))
        let axisY = (Float(frame.height * matrix.c), Float(frame.height * matrix.d))
        let makeVertex = { (x: Float, y: Float, u: Float, v: Float) in
            _Vertex(position: (origin.0.addingProduct(y, axisY.0).addingProduct(x, axisX.0),
                               origin.1.addingProduct(y, axisY.1).addingProduct(x, axisX.1)),
                texcoord: (u, v), color: (color.x, color.y, color.z, color.w))
        }
        let halfWidth = expandedWidth / expandedHeight * 0.5
        let tl = makeVertex(0, 0, -halfWidth, -0.5)
        let tr = makeVertex(1, 0, halfWidth, -0.5)
        let bl = makeVertex(0, 1, -halfWidth, 0.5)
        let br = makeVertex(1, 1, halfWidth, 0.5)
        let vertices = [bl, tl, br, br, tl, tr]
        guard let pipelineState = pipeline.renderState(shader: .primitiveColor,
                  colorFormat: renderPass.colorFormat, depthFormat: renderPass.depthFormat,
                  blendState: .opaque, sampleCount: renderPass.sampleCount),
              let depth = pipeline.depthStencilState(.ignore),
              let buffer = makeBuffer(vertices) else { return false }
        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depth)
        withUnsafeBytes(of: constants) { encoder.pushConstant(stages: .fragment, offset: 0, data: $0) }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: 0)
        encoder.draw(vertexStart: 0, vertexCount: vertices.count, instanceCount: 1, baseInstance: 0)
        return true
    }
}
