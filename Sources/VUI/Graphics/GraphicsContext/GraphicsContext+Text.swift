//
//  File: GraphicsContext+Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct ResolvedText {
        let resolved: ResolvedStyledText
        let shared: Storage.Shared
        public var shading: Shading = .foreground

        public func measure(in size: CGSize) -> CGSize {
            resolved.size(in: size)
        }

        public func measure(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> CGSize {
            measure(in: CGSize(width: maxWidth ?? .infinity, height: maxHeight ?? .infinity))
        }

        public func firstBaseline(in size: CGSize) -> CGFloat {
            resolved.firstBaseline(in: size)
        }

        public func lastBaseline(in size: CGSize) -> CGFloat {
            resolved.lastBaseline(in: size)
        }
    }

    public func draw(_ text: ResolvedText, in rect: CGRect) {
        guard !rect.isNull,
              let prepared = text.resolved.prepareDrawing(in: rect, with: rect.size,
                                                           applyingMarginOffsets: false) else { return }
        let drawing = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
        draw(drawing, in: prepared.bounds, shading: text.shading, clipBounds: false)
    }

    func draw(_ text: ResolvedTextSource, in rect: CGRect) {
        draw(text, in: rect, shading: text.shading)
    }

    func draw(
        _ text: ResolvedTextSource,
        in rect: CGRect,
        shading: Shading,
        layoutProperties: TextLayoutProperties? = nil
    ) {
        let rect = rect.standardized
        if rect.isEmpty || rect.isNull { return }
        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }
        let drawing = text.makeDrawing(
            in: rect.size,
            layoutProperties: layoutProperties
        )
        draw(drawing, in: rect, shading: shading, clipBounds: false)
    }

    func draw(
        _ drawing: ResolvedTextSource.Drawing,
        in rect: CGRect,
        shading: Shading,
        snapOrigin: Bool = true,
        snappingOrigin: CGPoint? = nil,
        clipBounds: Bool = true
    ) {
        var rect = rect.standardized
        if rect.isEmpty && clipBounds { return }
        if rect.isNull { return }

        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }
        if drawing.isEmpty { return }
        if recording != nil, record(bounds: rect, {
            $0.draw(drawing, in: rect, shading: shading, snapOrigin: snapOrigin,
                    snappingOrigin: snappingOrigin, clipBounds: clipBounds)
        }) { return }

        func runShading(_ color: Color?) -> Shading {
            guard let color else { return shading }
            let resolved = color.resolve(in: environment)
            // Foreground placeholders select the caller's shading without
            // changing explicit run colors or decoration colors.
            if resolved.linearRed == -1 && resolved.linearGreen == -1 && resolved.linearBlue == -1 {
                return shading
            }
            return .color(color)
        }

        var scissorRect: ScissorRect? = nil
        if snapOrigin || clipBounds {
            let transform = self.transform
                .concatenating(CGAffineTransform(
                    translationX: self.contentOffset.x,
                    y: self.contentOffset.y))
                .concatenating(CGAffineTransform(
                    scaleX: self.contentScaleFactor,
                    y: self.contentScaleFactor))

            if snapOrigin {
                let anchor = snappingOrigin ?? (rect.origin + drawing.origin)
                let relativeOffset = rect.origin + drawing.origin - anchor
                var origin = anchor.applying(transform)
                origin.x.round()
                origin.y.round()
                rect.origin = origin.applying(transform.inverted()) + relativeOffset - drawing.origin
            }
            if clipBounds {
                let tl = CGPoint(x: rect.minX, y: rect.minY).applying(transform)
                let tr = CGPoint(x: rect.maxX, y: rect.minY).applying(transform)
                let bl = CGPoint(x: rect.minX, y: rect.maxY).applying(transform)
                let br = CGPoint(x: rect.maxX, y: rect.maxY).applying(transform)
                let minX = min(tl.x, tr.x, bl.x, br.x)
                let maxX = max(tl.x, tr.x, bl.x, br.x)
                let minY = min(tl.y, tr.y, bl.y, br.y)
                let maxY = max(tl.y, tr.y, bl.y, br.y)
                
                if minX >= self.viewport.maxX { return }
                if minY >= self.viewport.maxY { return }
                if maxX <= self.viewport.minX { return }
                if maxY <= self.viewport.minY { return }
                
                let x1 = max(Int(floor(minX)), Int(self.viewport.minX))
                let y1 = max(Int(floor(minY)), Int(self.viewport.minY))
                let x2 = min(Int(ceil(maxX)), Int(self.viewport.maxX))
                let y2 = min(Int(ceil(maxY)), Int(self.viewport.maxY))
                if x1 >= x2 || y1 >= y2 { return }
                
                scissorRect = ScissorRect(x: x1, y: y1,
                                          width: x2 - x1, height: y2 - y1)
            }
        }

        let scale = 1.0 / drawing.source.scaleFactor
        let offset = rect.origin + drawing.origin
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)

        for background in drawing.backgrounds {
            self.fill(
                Path(background.frame.applying(transform)),
                with: .color(background.color)
            )
        }

        for batch in drawing.vectorBatches {
            let isAntialiased = self.environment.disableMSAA == false
            guard let renderPass = self.beginRenderPass(
                enableStencil: true,
                enableMSAA: isAntialiased
            ) else {
                continue
            }
            if let scissorRect {
                renderPass.encoder.setScissorRect(scissorRect)
            }
            if self.encodeStencilPathFillCommand(
                renderPass: renderPass,
                path: batch.path,
                pathTransform: transform
            ) {
                self.encodeShadingBoxCommand(
                    renderPass: renderPass,
                    shading: runShading(batch.foregroundColor),
                    stencil: .testNonZero,
                    blendState: .opaque,
                    bounds: rect
                )
                renderPass.end()
                self.drawSource()
            } else {
                renderPass.end()
            }
        }

        var foregroundColors: [Color?] = []
        for batch in drawing.batches where !batch.colorGlyphs {
            if !foregroundColors.contains(batch.foregroundColor) {
                foregroundColors.append(batch.foregroundColor)
            }
        }
        for foregroundColor in foregroundColors {
            guard let renderPass = self.beginRenderPass(enableStencil: false) else {
                continue
            }
            if let scissorRect {
                renderPass.encoder.setScissorRect(scissorRect)
            }
            self.encodeDrawTextCommand(renderPass: renderPass,
                                       drawing: drawing,
                                       transform: transform,
                                       color: .white,
                                       colorGlyphs: false,
                                       foregroundColor: foregroundColor,
                                       filtersForegroundColor: true)
            let shading = runShading(foregroundColor)
            self.encodeShadingBoxCommand(renderPass: renderPass,
                                         shading: shading,
                                         stencil: .ignore,
                                         blendState: .multiply,
                                         bounds: rect)
            renderPass.end()
            self.drawSource()
        }

        let hasColorGlyphs = drawing.batches.contains { $0.colorGlyphs }
        if hasColorGlyphs || !drawing.attachments.isEmpty,
           let renderPass = self.beginRenderPass(enableStencil: false) {
            if let scissorRect {
                renderPass.encoder.setScissorRect(scissorRect)
            }
            self.encodeDrawTextCommand(renderPass: renderPass,
                                       drawing: drawing,
                                       transform: transform,
                                       color: .white,
                                       colorGlyphs: true)
            for attachment in drawing.attachments {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: attachment.texture,
                                              frame: attachment.frame,
                                              transform: transform,
                                              textureFrame: attachment.textureFrame,
                                              textureTransform: .identity,
                                              blendState: .opaque,
                                              color: .white)
            }
            renderPass.end()
            self.drawSource()
        }

        for item in drawing.customAttachments {
            var context = self
            if clipBounds { context.clip(to: Path(rect)) }
            var bounds = item.bounds
            bounds.origin += offset
            item.attachment.draw(with: bounds, in: &context)
        }

        for decoration in drawing.decorations {
            let start = decoration.start.applying(transform)
            let end = decoration.end.applying(transform)
            let lineWidth = decoration.lineWidth * scale
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            self.stroke(
                path,
                with: runShading(decoration.foregroundColor),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .butt,
                    dash: decoration.dashPattern(lineWidth: lineWidth)
                )
            )
        }
        self.recordContentBounds(rect)
    }

    public func resolve(_ text: Text) -> ResolvedText {
        guard let resolved = text._resolveStyledText(
            context: self, referenceDate: Date(), archiveOptions: .init(),
            features: [], sizeFitting: false, options: .foregroundKeyColor
        ) else {
            fatalError("A graphics text context must resolve every attachment.")
        }
        resolved.layoutProperties.sizeFitting = false
        if let alignment = resolved.resolvedText?.resolvedProperties?.multilineTextAlignment {
            resolved.layoutProperties.multilineTextAlignment = alignment
        }
        return ResolvedText(resolved: resolved, shared: storage.shared)
    }

    public func draw(_ text: ResolvedText,
                     at point: CGPoint,
                     anchor: UnitPoint = .center) {
        let size = text.measure()
        if size.width > 0 && size.height > 0 {
            let origin = CGPoint(x: point.x - size.width * anchor.x,
                                 y: point.y - size.height * anchor.y)
            draw(text, in: CGRect(origin: origin, size: size))
        }
    }

    public func draw(_ text: Text, in rect: CGRect) {
        draw(resolve(text), in: rect)
    }
    
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(text), at: point, anchor: anchor)
    }

    // This method takes a glyph and frame in the pixel space coordinate system
    // as parameters to the closure.
    func forEachGlyph(in lineGlyphs: [ResolvedTextSource.LineGlyphs],
                      callback: (_: ResolvedTextSource.Glyph, _:CGPoint)->Void) {
        ResolvedTextSource.forEachGlyph(in: lineGlyphs, callback: callback)
    }

    func encodeDrawTextCommand(renderPass: RenderPass,
                               drawing: ResolvedTextSource.Drawing,
                               transform: CGAffineTransform,
                               color: BackendColor,
                               colorGlyphs: Bool,
                               foregroundColor: Color? = nil,
                               filtersForegroundColor: Bool = false) {
        if drawing.isEmpty { return }
        let c = color.float4
        let transform = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)

        for batch in drawing.batches where
            batch.colorGlyphs == colorGlyphs &&
            (!filtersForegroundColor || batch.foregroundColor == foregroundColor) {
            let vertices = batch.vertices.map { vertex in
                _Vertex(
                    position: Vector2(vertex.position).applying(transform).float2,
                    texcoord: vertex.texcoord,
                    color: c
                )
            }
            let shader: _Shader = colorGlyphs ? .image : .rcImage
            let blendState: BlendState = colorGlyphs
                ? .premultipliedAlphaBlend
                : .alphaBlend
            self.encodeDrawCommand(
                renderPass: renderPass,
                shader: shader,
                stencil: .ignore,
                vertices: vertices,
                texture: batch.texture,
                blendState: blendState
            )
        }
    }
}
