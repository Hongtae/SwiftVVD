//
//  File: GraphicsContext+Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct ResolvedImage {
        final class Storage: AppLifetimeResource, @unchecked Sendable {
            enum Contents {
                case texture(Texture)
                case symbol(ResolvedVectorSymbol)
                case svg(SVG)
            }

            var contents: Contents?
            let width: Int
            let height: Int

            init(contents: Contents?) {
                self.contents = contents
                switch contents {
                case let .texture(texture):
                    self.width = texture.width
                    self.height = texture.height
                case let .symbol(symbol):
                    self.width = Int(ceil(symbol.viewport.width))
                    self.height = Int(ceil(symbol.viewport.height))
                case let .svg(svg):
                    let size = svg.intrinsicSize ?? svg.viewBox.size
                    self.width = Int(ceil(size.width))
                    self.height = Int(ceil(size.height))
                case nil:
                    self.width = 0
                    self.height = 0
                }
            }

            override func purgeResources(reason: ResourcePurgeReason) {
                if reason == .appTermination,
                   case .texture = contents {
                    contents = nil
                }
            }
        }

        public var size: CGSize {
            CGSize(width: CGFloat(storage.width) * scaleFactor,
                   height: CGFloat(storage.height) * scaleFactor)
        }
        public let baseline: CGFloat
        public var shading: Shading?
        var symbolLayerOpacities: [Double]?
        var symbolReplacementLayerOpacities: [Double]?
        var symbolVariableColorOpacities: [Double]?
        var symbolDrawProgresses: [Double]?
        var symbolDrawFallbackOpacity: Double?
        var symbolDrawsReversed: Bool

        private let storage: Storage
        let textureTransform: CGAffineTransform
        let scaleFactor: CGFloat

        var texture: Texture? {
            guard case let .texture(texture) = storage.contents else {
                return nil
            }
            return texture
        }

        var symbol: ResolvedVectorSymbol? {
            guard case let .symbol(symbol) = storage.contents else {
                return nil
            }
            return symbol
        }

        var svg: SVG? {
            guard case let .svg(svg) = storage.contents else {
                return nil
            }
            return svg
        }

        var vectorID: ObjectIdentifier? {
            guard case .svg = storage.contents else { return nil }
            return ObjectIdentifier(storage)
        }

        init(baseline: CGFloat, shading: Shading?, texture: Texture?, textureTransform: CGAffineTransform, scaleFactor: CGFloat) {
            self.baseline = baseline
            self.shading = shading
            self.symbolLayerOpacities = nil
            self.symbolReplacementLayerOpacities = nil
            self.symbolVariableColorOpacities = nil
            self.symbolDrawProgresses = nil
            self.symbolDrawFallbackOpacity = nil
            self.symbolDrawsReversed = false
            self.storage = Storage(contents: texture.map(Storage.Contents.texture))
            self.textureTransform = textureTransform
            self.scaleFactor = scaleFactor
        }

        init(symbol: ResolvedVectorSymbol, shading: Shading? = nil) {
            self.baseline = symbol.viewport.height
            self.shading = shading
            self.symbolLayerOpacities = nil
            self.symbolReplacementLayerOpacities = nil
            self.symbolVariableColorOpacities = nil
            self.symbolDrawProgresses = nil
            self.symbolDrawFallbackOpacity = nil
            self.symbolDrawsReversed = false
            self.storage = Storage(contents: .symbol(symbol))
            self.textureTransform = .identity
            self.scaleFactor = 1
        }

        init(svg: SVG, shading: Shading? = nil) {
            self.baseline = svg.intrinsicSize?.height ?? svg.viewBox.height
            self.shading = shading
            self.symbolLayerOpacities = nil
            self.symbolReplacementLayerOpacities = nil
            self.symbolVariableColorOpacities = nil
            self.symbolDrawProgresses = nil
            self.symbolDrawFallbackOpacity = nil
            self.symbolDrawsReversed = false
            self.storage = Storage(contents: .svg(svg))
            self.textureTransform = .identity
            self.scaleFactor = 1
        }
    }

    public func resolve(_ image: Image) -> ResolvedImage {
        if let symbol = image.provider.makeVectorSymbol() {
            return ResolvedImage(symbol: symbol)
        }
        if let svg = image.provider.makeSVG() {
            return ResolvedImage(svg: svg)
        }
        let texture = image.provider.makeTexture(self)
        let displayScale = self.sceneResources.contentScaleFactor
        let scaleFactor = image.provider.scaleFactor / displayScale
        let baseline = CGFloat(texture?.height ?? 0) * scaleFactor
        return ResolvedImage(baseline: baseline, shading: nil, texture: texture, textureTransform: .identity, scaleFactor: scaleFactor)
    }
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        if let symbol = image.symbol, rect.width > 0, rect.height > 0 {
            draw(symbol, image: image, in: rect, style: style)
            return
        }
        if let svg = image.svg, rect.width > 0, rect.height > 0 {
            draw(svg, shading: image.shading, in: rect)
            return
        }
        if let texture = image.texture, (rect.width > 0 && rect.height > 0) {
            let textureFrame = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
            let textureTransform = image.textureTransform

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: rect,
                                              transform: .identity,
                                              textureFrame: textureFrame,
                                              textureTransform: textureTransform,
                                              blendState: .opaque,
                                              color: image.premultipliedTintColor(in: self.environment))
                renderPass.end()
                self.drawSource()
                self.recordContentBounds(rect)
            }
        }
    }

    private func draw(
        _ symbol: ResolvedVectorSymbol,
        image: ResolvedImage,
        in rect: CGRect,
        style: FillStyle
    ) {
        let viewport = symbol.viewport
        guard viewport.width > 0, viewport.height > 0 else { return }
        let scale = min(rect.width / viewport.width, rect.height / viewport.height)
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - viewport.midX * scale,
            ty: rect.midY - viewport.midY * scale
        )
        for layer in symbol.layers where layer.opacity > 0 {
            let effectOpacity = image.symbolLayerOpacities.flatMap { opacities in
                opacities.indices.contains(layer.effectLevel)
                    ? opacities[layer.effectLevel]
                    : nil
            } ?? 1
            let replacementOpacity = image.symbolReplacementLayerOpacities.flatMap {
                opacities in
                opacities.indices.contains(layer.replacementLevel)
                    ? opacities[layer.replacementLevel]
                    : nil
            } ?? 1
            let variableColorOpacity = layer.variableColorLevel.flatMap { level in
                image.symbolVariableColorOpacities.flatMap { opacities in
                    opacities.indices.contains(level) ? opacities[level] : nil
                }
            } ?? 1
            let presentationOpacity = effectOpacity * replacementOpacity *
                variableColorOpacity *
                (image.symbolDrawFallbackOpacity ?? 1)
            guard presentationOpacity > 0 else { continue }
            let layerOpacity = layer.opacity * presentationOpacity
            let layerPath = layer.path.applying(transform)
            let shading = image.shading ?? symbolShading(for: layer.semanticLevel)
            let fillStyle = FillStyle(
                eoFill: layer.isEOFilled || style.isEOFilled,
                antialiased: style.isAntialiased
            )
            if let draw = layer.draw,
               let progresses = image.symbolDrawProgresses,
               progresses.indices.contains(draw.motionGroup) {
                let progress = min(max(progresses[draw.motionGroup], 0), 1)
                guard progress > 0 else { continue }
                if progress < 1 {
                    let revealPath = draw.clipPath(
                        progress: progress,
                        reversed: image.symbolDrawsReversed
                    ).applying(transform)
                    guard !revealPath.isEmpty else { continue }
                    let boundaryOpacities = draw.clipBoundaryOpacities(
                        progress: progress,
                        reversed: image.symbolDrawsReversed
                    )
                    if boundaryOpacities.completion > 0 {
                        var completionContext = self
                        completionContext.opacity *= layerOpacity *
                            boundaryOpacities.completion
                        completionContext.clip(
                            to: revealPath,
                            options: .inverse
                        )
                        completionContext.fill(
                            layerPath,
                            with: shading,
                            style: fillStyle
                        )
                    }
                    guard boundaryOpacities.reveal > 0 else { continue }
                    var revealContext = self
                    revealContext.opacity *= layerOpacity *
                        boundaryOpacities.reveal
                    revealContext.clip(to: revealPath)
                    revealContext.fill(
                        layerPath,
                        with: shading,
                        style: fillStyle
                    )
                    continue
                }
            }
            var context = self
            context.opacity *= layerOpacity
            context.fill(
                layerPath,
                with: shading,
                style: fillStyle
            )
        }
    }

    private func symbolShading(for semanticLevel: Int) -> Shading {
        guard let levels = environment.foregroundStyleLevels else {
            return .style(ForegroundStyle())
        }
        let style: AnyShapeStyle
        switch semanticLevel {
        case 1:
            style = levels.secondary ?? levels.primary
        case 2...:
            style = levels.tertiary ?? levels.secondary ?? levels.primary
        default:
            style = levels.primary
        }
        var shape = _ShapeStyle_Shape()
        style._apply(to: &shape)
        return shape.shading ?? .style(ForegroundStyle())
    }

    public func draw(_ svg: SVG, in rect: CGRect) {
        draw(svg, shading: nil, in: rect)
    }

    public func draw(_ layer: SVG.Layer) {
        draw(layer, applying: .identity, shading: nil)
    }

    private func draw(
        _ svg: SVG,
        shading: Shading?,
        in rect: CGRect
    ) {
        guard svg.viewBox.width > 0, svg.viewBox.height > 0,
              rect.width > 0, rect.height > 0 else {
            return
        }
        let scale = min(
            rect.width / svg.viewBox.width,
            rect.height / svg.viewBox.height
        )
        let viewportTransform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - svg.viewBox.midX * scale,
            ty: rect.midY - svg.viewBox.midY * scale
        )
        for layer in svg.layers {
            draw(layer, applying: viewportTransform, shading: shading)
        }
    }

    private func draw(
        _ layer: SVG.Layer,
        applying outerTransform: CGAffineTransform,
        shading override: Shading?
    ) {
        guard layer.opacity > 0 else { return }
        let transform = layer.transform.concatenating(outerTransform)
        var layerContext = self
        layerContext.opacity *= layer.opacity

        for style in layer.styles {
            switch style {
            case let .fill(paint, fillStyle, opacity):
                guard opacity > 0 else { continue }
                var context = layerContext
                context.opacity *= opacity
                context.fill(
                    layer.path.applying(transform),
                    with: override ?? svgShading(for: paint),
                    style: fillStyle
                )

            case let .stroke(paint, strokeStyle, opacity):
                guard opacity > 0, strokeStyle.lineWidth > 0 else { continue }
                var context = layerContext
                context.opacity *= opacity
                let outline = layer.path
                    .strokedPath(strokeStyle)
                    .applying(transform)
                context.fill(
                    outline,
                    with: override ?? svgShading(for: paint)
                )
            }
        }
    }

    private func svgShading(for paint: SVG.Paint) -> Shading {
        switch paint {
        case let .color(color):
            return .color(color)
        case .currentColor, .foregroundStyle:
            return symbolShading(for: 0)
        case .backgroundStyle:
            guard let style = environment.backgroundStyle else {
                return .style(BackgroundStyle())
            }
            var shape = _ShapeStyle_Shape()
            style._apply(to: &shape)
            return shape.shading ?? .style(BackgroundStyle())
        }
    }
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = image.size
        let x = point.x - anchor.x * size.width
        let y = point.y - anchor.y * size.height
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        return draw(image, in: rect, style: FillStyle())
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        draw(resolve(image), in: rect, style: style)
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    func encodeDrawTextureCommand(renderPass: RenderPass,
                                  texture: Texture,
                                  frame: CGRect,
                                  transform: CGAffineTransform = .identity,
                                  textureFrame: CGRect,
                                  textureTransform: CGAffineTransform = .identity,
                                  blendState: BlendState,
                                  color: BackendColor) {
        let trans = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(position: Vector2(x, y).applying(trans).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)

        let uvMinX = textureFrame.minX * invW
        let uvMaxX = textureFrame.maxX * invW
        let uvMinY = textureFrame.minY * invH
        let uvMaxY = textureFrame.maxY * invH

        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY), // left bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY), // right top
        ]

        self.encodeDrawCommand(renderPass: renderPass,
                               shader: .image,
                               stencil: .ignore,
                               vertices: vertices,
                               texture: texture,
                               blendState: blendState)
    }
}

private extension GraphicsContext.ResolvedImage {
    func premultipliedTintColor(in environment: EnvironmentValues) -> BackendColor {
        guard let shading,
              shading.properties.count == 1,
              case let .color(color) = shading.properties[0] else {
            return .white
        }
        let backendColor = color.backendColor(in: environment)
        return BackendColor(
            backendColor.r * backendColor.a,
            backendColor.g * backendColor.a,
            backendColor.b * backendColor.a,
            backendColor.a
        )
    }
}

extension GraphicsContext.ResolvedImage: InterpolatableContent {
    static var defaultTransition: ContentTransition {
        _SemanticFeature<Semantics_v4>.isEnabled ? .interpolate : .identity
    }

    func requiresTransition(to target: Self) -> Bool {
        if baseline != target.baseline { return true }
        if scaleFactor != target.scaleFactor { return true }
        if !textureIdentityEquals(texture, target.texture) { return true }
        if symbol?.identity != target.symbol?.identity { return true }
        if vectorID != target.vectorID { return true }
        if !textureTransform.isTransitionEqual(to: target.textureTransform) { return true }
        if shading != nil || target.shading != nil { return true }
        return false
    }

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        guard !state.options.contains(.animatesDifferentContent) else { return }
        guard requiresTransition(to: target) else { return }
        state.transition = .opacity
    }
}

private func textureIdentityEquals(_ lhs: Texture?, _ rhs: Texture?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        true
    case let (.some(lhs), .some(rhs)):
        lhs === rhs
    default:
        false
    }
}

private extension CGAffineTransform {
    func isTransitionEqual(to other: CGAffineTransform) -> Bool {
        a == other.a
            && b == other.b
            && c == other.c
            && d == other.d
            && tx == other.tx
            && ty == other.ty
    }
}
