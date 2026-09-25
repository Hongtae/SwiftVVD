//
//  File: GraphicsContext+Primitive.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// A filled, solid-color primitive consumed by the plane and shadow encoders.
// Complex paths and unequal corner axes use path drawing; circular radii may
// vary independently at each corner.
struct FilledPrimitive {
    var rect: CGRect
    var kind: UInt32
    var cornerRadii: SIMD4<Float>
    var blurRadius: Float = 0
    var color: SIMD4<Float>

    init?(path: Path, color: Color.Resolved, opacity: Float = 1) {
        switch path.storage {
        case let .rect(rect):
            self.rect = rect.standardized
            kind = 2
            cornerRadii = .zero
        case let .ellipse(rect) where rect.width == rect.height:
            self.rect = rect.standardized
            kind = 5
            cornerRadii = SIMD4(repeating: Float(self.rect.height) * 0.5)
        case let .roundedRect(rounded):
            self.rect = rounded.rect.standardized
            let maximum = min(Float(self.rect.width), Float(self.rect.height)) * 0.5
            let multiplier: Float
            switch rounded.style {
            case .circular:
                kind = 3
                multiplier = 1
            case .continuous:
                kind = 4
                multiplier = 1.275
            }
            switch rounded.radii {
            case let .elliptic(width, height) where width == height:
                let radius = min(max(0, Float(width)), maximum) * multiplier
                cornerRadii = SIMD4(repeating: radius)
            case let .uneven(topLeft, topRight, bottomRight, bottomLeft):
                cornerRadii = SIMD4(
                    min(max(0, Float(topLeft)), maximum) * multiplier,
                    min(max(0, Float(topRight)), maximum) * multiplier,
                    min(max(0, Float(bottomRight)), maximum) * multiplier,
                    min(max(0, Float(bottomLeft)), maximum) * multiplier)
            default:
                return nil
            }
        default: return nil
        }
        guard !rect.isEmpty, !rect.isInfinite,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ Float($0).isFinite }) else {
            return nil
        }
        let h = Self.half
        let alpha = h(h(color.opacity) * h(opacity))
        self.color = SIMD4(h(h(color.red) * alpha), h(h(color.green) * alpha),
                           h(h(color.blue) * alpha), alpha)
    }

    private static func half(_ value: Float) -> Float { Float(Float16(value)) }

    // Geometry heights are nonnegative. Preserve zero after conversion and
    // infinity after expansion without changing primitive admission.
    static func reciprocalHeight(_ height: Float) -> Float {
        if height == 0 { return .infinity }
        if height == .infinity { return 0 }
        let bits = height.bitPattern
        var exponent = Int(bits >> 23)
        var fraction = bits & 0x7fffff
        let estimate: Float
        if exponent == 0 && fraction < 0x200000 {
            estimate = .infinity
        } else {
            if exponent == 0 {
                let shift = fraction < 0x400000 ? 2 : 1
                fraction = (fraction << shift) & 0x7fffff
                exponent = 1 - shift
            }
            // Round the reciprocal of the significand bucket's midpoint.
            let bucket = 256 + (fraction >> 15)
            let significand = (262144 + bucket) / (2 * bucket + 1)
            let resultExponent = 253 - exponent
            let result = resultExponent > 0
                ? UInt32(resultExponent) << 23 | (significand - 256) << 15
                : (significand << 15) >> (1 - resultExponent)
            estimate = Float(bitPattern: result)
        }
        // Each correction is fused; the following multiplication rounds
        // separately. A division or an unfused correction changes coverage.
        let first = estimate * Float(2).addingProduct(-height, estimate)
        return first * Float(2).addingProduct(-height, first)
    }

    static func hasIntegralBounds(_ rect: CGRect) -> Bool {
        let x = Float(rect.minX), y = Float(rect.minY)
        // Only the small interval above an integer boundary elides coverage.
        // Keep the bounds and endpoint additions in the shader's Float domain.
        return [x, y, x + Float(rect.width), y + Float(rect.height)].allSatisfy {
            $0.isFinite && abs($0 - floor($0)) <= Float(0.005)
        }
    }

    struct Lowering {
        let frame: CGRect
        let expandedWidth: Float
        let expandedHeight: Float
        let reciprocalHeight: Float
        let edges: SIMD2<Float>
        let cornerRadii: SIMD4<Float>
        let distanceScale: Float
        let kind: UInt32
        let mode: UInt32
        let innerInsets: SIMD4<Float>
        let mainIndices: [UInt16]
        let extraIndices: [UInt16]
    }

    func lowering(pixelTransform: CGAffineTransform) -> Lowering? {
        let radius = blurRadius
        let scale = Float(max(max(abs(pixelTransform.a), abs(pixelTransform.b)),
                              max(abs(pixelTransform.c), abs(pixelTransform.d))))
        let aligned = (pixelTransform.b == 0 && pixelTransform.c == 0) ||
                      (pixelTransform.a == 0 && pixelTransform.d == 0)
        let pixelRect = bounds(transform: pixelTransform)
        let plane = kind == 2 && aligned && Self.hasIntegralBounds(pixelRect)
        let outset: Float = plane ? 0 : radius > 0 ? Float(1).addingProduct(2.8, radius) : 1 / scale
        guard outset.isFinite else { return nil }

        let width = Float(rect.width)
        let height = Float(rect.height)
        let expandedWidth = width + 2 * outset
        let expandedHeight = height + 2 * outset
        let reciprocalHeight = Self.reciprocalHeight(expandedHeight)
        let frame = CGRect(x: CGFloat(Float(rect.minX) - outset),
                           y: CGFloat(Float(rect.minY) - outset),
                           width: CGFloat(expandedWidth), height: CGFloat(expandedHeight))
        let corners = cornerRadii
        let equalCorners = corners.x == corners.y && corners.x == corners.z && corners.x == corners.w
        let hasCorner = corners.x >= 0.01 || corners.y >= 0.01 ||
            corners.z >= 0.01 || corners.w >= 0.01
        var loweredKind = plane ? UInt32(1) : !hasCorner && radius == 0 ? UInt32(2) : kind
        if !equalCorners {
            if loweredKind == 3 { loweredKind = 6 }
            if loweredKind == 4 { loweredKind = 7 }
        }
        var secondRadius: Float = 0
        var weights = SIMD2<Float>(repeating: 0)

        if loweredKind == 4 {
            let corner = corners.x
            secondRadius = corner * 0.7843137383460999
            let denominator = corner * 0.4146391749382019
            let ratios = SIMD2((width * 0.5 - secondRadius) / denominator,
                               (height * 0.5 - secondRadius) / denominator)
            if (ratios.x > -0.0001 && ratios.x < 1) ||
               (ratios.y > -0.0001 && ratios.y < 1) {
                loweredKind = 10
                weights = SIMD2(1 - min(max(ratios.y, 0), 1),
                                1 - min(max(ratios.x, 0), 1))
            }
        }

        let edgeInset: Float = loweredKind == 3 || loweredKind == 4 ? corners.x : 0
        let edges = SIMD2((width * 0.5 - edgeInset) * reciprocalHeight,
                          (height * 0.5 - edgeInset) * reciprocalHeight)
        let normalizedCornerRadii: SIMD4<Float>
        if loweredKind == 10 {
            normalizedCornerRadii = SIMD4(
                corners.x * reciprocalHeight,
                secondRadius * reciprocalHeight,
                weights.x, weights.y)
        } else if loweredKind == 6 || loweredKind == 7 {
            normalizedCornerRadii = corners * SIMD4(repeating: reciprocalHeight)
        } else {
            normalizedCornerRadii = SIMD4(corners.x * reciprocalHeight, 0, 0, 0)
        }
        let distanceScale = radius > 0
            ? Float(Float16(Float(Float16(0.1695573329925537 / radius)) * expandedHeight)) : 0

        let cornerInsets = SIMD4(
            max(corners.x * 0.2928932309150696, 0),
            max(corners.y * 0.2928932309150696, 0),
            max(corners.z * 0.2928932309150696, 0),
            max(corners.w * 0.2928932309150696, 0))
        let cornerLimit = min(width, height) * 0.5
        let supportsInnerMesh = loweredKind == 6 || loweredKind == 7 || loweredKind == 10
        let usesInnerMesh = supportsInnerMesh && scale * width * height > 4096 &&
            cornerLimit > cornerInsets.x + outset &&
            cornerLimit > cornerInsets.y + outset &&
            cornerLimit > cornerInsets.z + outset &&
            cornerLimit > cornerInsets.w + outset
        // Inner vertices use a separately divided reciprocal and two rounded
        // outset additions; the normalized corner fields use reciprocalHeight.
        let innerReciprocal = 1 / expandedHeight
        let innerInsets = usesInnerMesh
            ? SIMD4(
                ((cornerInsets.x + outset) + outset) * innerReciprocal,
                ((cornerInsets.y + outset) + outset) * innerReciprocal,
                ((cornerInsets.z + outset) + outset) * innerReciprocal,
                ((cornerInsets.w + outset) + outset) * innerReciprocal)
            : .zero
        let mainIndices: [UInt16] = usesInnerMesh
            ? [4, 0, 5, 1, 6, 2, 7, 3, 4, 0] : [1, 0, 2, 3]
        let extraIndices: [UInt16] = usesInnerMesh ? [5, 4, 6, 7] : []
        return Lowering(frame: frame, expandedWidth: expandedWidth, expandedHeight: expandedHeight,
            reciprocalHeight: reciprocalHeight, edges: edges, cornerRadii: normalizedCornerRadii,
            distanceScale: distanceScale, kind: loweredKind, mode: radius > 0 ? 2 : 0,
            innerInsets: innerInsets, mainIndices: mainIndices, extraIndices: extraIndices)
    }

    func bounds(transform: CGAffineTransform) -> CGRect {
        let amount = max(0, blurRadius * 2.8)
        let x = Float(rect.minX) - amount, y = Float(rect.minY) - amount
        let width = Float(rect.width).addingProduct(2, amount)
        let height = Float(rect.height).addingProduct(2, amount)
        if transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 {
            return CGRect(x: CGFloat(x + Float(transform.tx)), y: CGFloat(y + Float(transform.ty)),
                          width: CGFloat(width), height: CGFloat(height))
        }
        let corners = [(x, y), (x + width, y), (x + width, y + height), (x, y + height)].map { x, y in
            SIMD2(Float(transform.tx.addingProduct(transform.a, CGFloat(x)).addingProduct(transform.c, CGFloat(y))),
                  Float(transform.ty.addingProduct(transform.b, CGFloat(x)).addingProduct(transform.d, CGFloat(y))))
        }
        let lo = corners.reduce(corners[0]) { SIMD2(min($0.x, $1.x), min($0.y, $1.y)) }
        let hi = corners.reduce(corners[0]) { SIMD2(max($0.x, $1.x), max($0.y, $1.y)) }
        return CGRect(x: CGFloat(lo.x), y: CGFloat(lo.y),
                      width: CGFloat(hi.x - lo.x), height: CGFloat(hi.y - lo.y))
    }

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
        let amount = Float(1.8) * sigma
        let amountSquared = amount * amount
        let expandedCorner = { (corner: Float, reciprocal: Float, multiplier: Float) in
            let radius = corner * reciprocal
            let combined = radius > 0
                ? amountSquared.addingProduct(radius, radius).squareRoot()
                : amount
            return min(combined, minimum * 0.5) * multiplier
        }
        if kind == 4 {
            // The coverage owner uses the vector reciprocal estimate followed
            // by two Newton refinements. Its result is one ULP above 1/1.275.
            let reciprocal = Float(bitPattern: 0x3f48c8ca)
            result.cornerRadii = SIMD4(
                expandedCorner(cornerRadii.x, reciprocal, 1.275),
                expandedCorner(cornerRadii.y, reciprocal, 1.275),
                expandedCorner(cornerRadii.z, reciprocal, 1.275),
                expandedCorner(cornerRadii.w, reciprocal, 1.275))
        } else if kind != 5 {
            result.cornerRadii = SIMD4(
                expandedCorner(cornerRadii.x, 1, 1), expandedCorner(cornerRadii.y, 1, 1),
                expandedCorner(cornerRadii.z, 1, 1), expandedCorner(cornerRadii.w, 1, 1))
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
    // An unfiltered rectangle whose coverage can be discarded. Admission also
    // requires a solid paint and a blend that needs no backdrop sampling.
    struct SolidColorPlane {
        let primitive: FilledPrimitive

        init?(path: Path, shading: Shading, style: FillStyle, context: GraphicsContext) {
            guard !style.isEOFilled, case .rect = path.storage,
                  context.storage.state.pointee.style == nil,
                  context.storage.state.pointee.maskTexture == nil,
                  RBDrawingStateGetDefaultColorSpace(context.storage.state) == .sRGB,
                  context.blendMode == .normal,
                  context.opacity.isFinite, (0...1).contains(context.opacity),
                  RBDisplayList.Style.isFiniteInvertible(context.transform),
                  shading.properties.count == 1,
                  case let .color(color) = shading.properties[0] else { return nil }
            let resolved = color.resolve(in: context.environment)
            guard [resolved.red, resolved.green, resolved.blue, resolved.opacity].allSatisfy({
                $0.isFinite && (0...1).contains($0)
            }), let primitive = FilledPrimitive(path: path, color: resolved,
                                                opacity: Float(context.opacity)) else { return nil }

            let pixels = context.transform
                .concatenating(CGAffineTransform(translationX: context.contentOffset.x, y: context.contentOffset.y))
                .concatenating(CGAffineTransform(scaleX: context.contentScaleFactor, y: context.contentScaleFactor))
                .concatenating(CGAffineTransform(translationX: context.viewport.minX, y: context.viewport.minY))
            let bounds = primitive.bounds(transform: pixels)
            guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ Float($0).isFinite }) else {
                return nil
            }
            let aligned = (pixels.b == 0 && pixels.c == 0) || (pixels.a == 0 && pixels.d == 0)
            let scissor = CGRect(x: Int(context.viewport.minX), y: Int(context.viewport.minY),
                                 width: Int(context.viewport.width), height: Int(context.viewport.height))
                .intersection(CGRect(origin: .zero, size: context.resolution))
            guard !style.isAntialiased || aligned &&
                (FilledPrimitive.hasIntegralBounds(bounds) || bounds.contains(scissor)) else { return nil }
            self.primitive = primitive
        }

        func draw(in context: GraphicsContext) {
            guard let pass = context.beginRenderPassBackdropTarget() else {
                Log.error("GraphicsContext solid color pass creation failed.")
                return
            }
            let matrix = context.transform.concatenating(context.viewTransform)
            let rect = primitive.rect
            let x = CGFloat(Float(rect.minX)), y = CGFloat(Float(rect.minY))
            let width = CGFloat(Float(rect.width)), height = CGFloat(Float(rect.height))
            let origin = Vector2(x, y).applying(matrix).float2
            let axisX = (Float(width * matrix.a), Float(width * matrix.b))
            let axisY = (Float(height * matrix.c), Float(height * matrix.d))
            let color = primitive.color
            let vertex = { (x: Float, y: Float) in
                _Vertex(position: (origin.0.addingProduct(y, axisY.0).addingProduct(x, axisX.0),
                                   origin.1.addingProduct(y, axisY.1).addingProduct(x, axisX.1)),
                        texcoord: (0, 0), color: (color.x, color.y, color.z, color.w))
            }
            context.encodeDrawCommand(renderPass: pass, shader: .planeColor, stencil: .ignore,
                vertices: [vertex(0, 1), vertex(0, 0), vertex(1, 1), vertex(1, 1), vertex(0, 0), vertex(1, 0)],
                texture: nil, blendState: color.w == 1 ? .opaque : .premultipliedAlphaBlend)
            pass.end()
        }
    }

    // A scoped execution plan for one shadow and its solid source. The scratch
    // target belongs to this draw until it has been composited and reset.
    struct PrimitiveShadowGroup {
        let source: FilledPrimitive
        let sourceTransform: CGAffineTransform
        let shadow: FilledPrimitive
        let shadowTransform: CGAffineTransform
        let opacity: Float
        let scissor: ScissorRect?

        init?(source: FilledPrimitive, context: GraphicsContext) {
            let styles = context.storage.state.pointee.style?.executionStyles ?? []
            guard styles.count == 1, let style = styles[0] as? RBDisplayList.ShadowStyle,
                  style.supportsColorOperations, style.options.isEmpty,
                  context.blendMode == .normal, context.storage.state.pointee.maskTexture == nil,
                  context.opacity.isFinite, context.opacity > 0, context.opacity <= 1,
                  let shadow = source.shadow(radius: style.radius, color: style.color.resolved,
                      itemTransform: context.transform, styleTransform: style.transform, offset: style.offset) else {
                return nil
            }
            let opacity = Float(Float16(Float(context.opacity)))
            guard opacity > 0 else { return nil }
            self.source = source
            self.sourceTransform = context.transform
            self.shadow = shadow.primitive
            self.shadowTransform = shadow.transform
            self.opacity = opacity
            if opacity == 1 {
                scissor = nil
            } else {
                let pixels = CGAffineTransform(translationX: context.contentOffset.x, y: context.contentOffset.y)
                    .concatenating(CGAffineTransform(scaleX: context.contentScaleFactor, y: context.contentScaleFactor))
                    .concatenating(CGAffineTransform(translationX: context.viewport.minX, y: context.viewport.minY))
                let a = source.bounds(transform: sourceTransform.concatenating(pixels))
                let b = shadow.primitive.bounds(transform: shadow.transform.concatenating(pixels))
                let x = min(Float(a.minX), Float(b.minX)), y = min(Float(a.minY), Float(b.minY))
                let width = max(Float(a.minX) + Float(a.width), Float(b.minX) + Float(b.width)) - x
                let height = max(Float(a.minY) + Float(a.height), Float(b.minY) + Float(b.height)) - y
                guard [x, y, width, height, x + width, y + height].allSatisfy(\.isFinite) else { return nil }
                let parent = CGRect(x: Int(context.viewport.minX), y: Int(context.viewport.minY),
                                    width: Int(context.viewport.width), height: Int(context.viewport.height))
                let bounds = CGRect(x: CGFloat(floor(x)), y: CGFloat(floor(y)),
                    width: CGFloat(ceil(x + width) - floor(x)), height: CGFloat(ceil(y + height) - floor(y)))
                    .intersection(parent).intersection(CGRect(origin: .zero, size: context.resolution))
                scissor = bounds.isNull || bounds.isEmpty ? ScissorRect(x: 0, y: 0, width: 0, height: 0)
                    : ScissorRect(x: Int(bounds.minX), y: Int(bounds.minY),
                                  width: Int(bounds.width), height: Int(bounds.height))
            }
        }

        func draw(in context: GraphicsContext) {
            if let scissor, scissor.width == 0 || scissor.height == 0 { return }
            let grouped = scissor != nil
            guard let pass = context.beginRenderPass(viewport: context.viewport,
                renderTarget: grouped ? context.sourceTexture : context.backdrop,
                loadAction: grouped ? .clear : .load, clearColor: .clear,
                useStencil: false, useMSAA: false) else {
                Log.error("GraphicsContext primitive group pass creation failed.")
                return
            }
            if let scissor { pass.encoder.setScissorRect(scissor) }
            let encoded = context.encodePrimitive(renderPass: pass, primitive: shadow,
                transform: shadowTransform, blendState: .premultipliedAlphaBlend) &&
                context.encodePrimitive(renderPass: pass, primitive: source,
                    transform: sourceTransform, blendState: .premultipliedAlphaBlend)
            pass.end()
            guard encoded else {
                Log.error("GraphicsContext primitive group encoding failed.")
                return
            }
            guard let scissor else { return }
            if let output = context.beginRenderPassBackdropTarget() {
                output.encoder.setScissorRect(scissor)
                context.encodePrimitiveGroup(renderPass: output, opacity: opacity)
                output.end()
            } else {
                Log.error("GraphicsContext primitive group output pass creation failed.")
            }
            // The sampled target cannot also be an output of the composite pass.
            // End its lifetime with a clear before another draw can reuse it.
            if let reset = context.beginRenderPass(enableStencil: false) {
                reset.end()
            } else {
                Log.error("GraphicsContext primitive group reset failed.")
            }
        }
    }

    func encodePrimitiveGroup(renderPass: RenderPass, opacity: Float) {
        let color: Float4 = (opacity, opacity, opacity, opacity)
        let tl = _Vertex(position: (-1, 1), texcoord: (0, 0), color: color)
        let tr = _Vertex(position: (1, 1), texcoord: (0, 0), color: color)
        let bl = _Vertex(position: (-1, -1), texcoord: (0, 0), color: color)
        let br = _Vertex(position: (1, -1), texcoord: (0, 0), color: color)
        encodeDrawCommand(renderPass: renderPass, shader: .primitiveGroup, stencil: .ignore,
            vertices: [bl, tl, br, br, tl, tr], texture: sourceTexture, blendState: .premultipliedAlphaBlend)
    }

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
                         transform: CGAffineTransform, blendState: BlendState? = nil) -> Bool {
        let pixelTransform = transform.concatenating(CGAffineTransform(
            scaleX: contentScaleFactor, y: contentScaleFactor))
        guard let lowering = primitive.lowering(pixelTransform: pixelTransform) else { return false }
        // Float words keep the uniform layout portable without requiring
        // native 16-bit storage support from the graphics device.
        let constants: (Float, Float, Float, Float, Float, Float, Float, UInt32, UInt32) = (
            lowering.edges.x, lowering.edges.y,
            lowering.cornerRadii.x, lowering.cornerRadii.y,
            lowering.cornerRadii.z, lowering.cornerRadii.w,
            lowering.distanceScale, lowering.kind, lowering.mode)
        let matrix = transform.concatenating(viewTransform)
        let color = primitive.color
        let origin = Vector2(lowering.frame.minX, lowering.frame.minY).applying(matrix).float2
        let axisX = (Float(lowering.frame.width * matrix.a), Float(lowering.frame.width * matrix.b))
        let axisY = (Float(lowering.frame.height * matrix.c), Float(lowering.frame.height * matrix.d))
        let makeVertex = { (x: Float, y: Float, u: Float, v: Float) in
            _Vertex(position: (origin.0.addingProduct(y, axisY.0).addingProduct(x, axisX.0),
                               origin.1.addingProduct(y, axisY.1).addingProduct(x, axisX.1)),
                texcoord: (u, v), color: (color.x, color.y, color.z, color.w))
        }
        let unitWidth = lowering.expandedWidth * lowering.reciprocalHeight
        let halfWidth = unitWidth * 0.5
        let tl = makeVertex(0, 0, -halfWidth, -0.5)
        let tr = makeVertex(1, 0, halfWidth, -0.5)
        let bl = makeVertex(0, 1, -halfWidth, 0.5)
        let br = makeVertex(1, 1, halfWidth, 0.5)
        var vertices = [tl, tr, br, bl]
        if lowering.innerInsets != .zero {
            let topLeft = lowering.innerInsets.x
            let topRight = lowering.innerInsets.y
            let bottomRight = lowering.innerInsets.z
            let bottomLeft = lowering.innerInsets.w
            vertices += [
                makeVertex(topLeft / unitWidth, topLeft,
                           -halfWidth + topLeft, -0.5 + topLeft),
                makeVertex(1 - topRight / unitWidth, topRight,
                           halfWidth - topRight, -0.5 + topRight),
                makeVertex(1 - bottomRight / unitWidth, 1 - bottomRight,
                           halfWidth - bottomRight, 0.5 - bottomRight),
                makeVertex(bottomLeft / unitWidth, 1 - bottomLeft,
                           -halfWidth + bottomLeft, 0.5 - bottomLeft),
            ]
        }
        // Typed half output and source-over form one precision path. Keep the
        // float output path's existing replacement blend on other devices.
        let blendState = blendState ?? (pipeline.primitiveOutputUsesFloat16
            ? .premultipliedAlphaBlend : .opaque)
        guard let pipelineState = pipeline.renderState(shader: .primitiveColor,
                  colorFormat: renderPass.colorFormat, depthFormat: renderPass.depthFormat,
                  blendState: blendState, sampleCount: renderPass.sampleCount),
              let depth = pipeline.depthStencilState(.ignore),
              let vertexBuffer = makeBuffer(vertices),
              let indexBuffer = makeBuffer(lowering.mainIndices + lowering.extraIndices) else { return false }
        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depth)
        withUnsafeBytes(of: constants) { encoder.pushConstant(stages: .fragment, offset: 0, data: $0) }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
        encoder.drawIndexed(indexCount: lowering.mainIndices.count, indexType: .uint16,
            indexBuffer: indexBuffer.buffer, indexBufferOffset: indexBuffer.offset,
            instanceCount: 1, baseVertex: 0, baseInstance: 0)
        if !lowering.extraIndices.isEmpty {
            encoder.drawIndexed(indexCount: lowering.extraIndices.count, indexType: .uint16,
                indexBuffer: indexBuffer.buffer,
                indexBufferOffset: indexBuffer.offset + lowering.mainIndices.count * MemoryLayout<UInt16>.stride,
                instanceCount: 1, baseVertex: 0, baseInstance: 0)
        }
        return true
    }
}
