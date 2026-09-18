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
        let drawing = prepared.source.makeDrawing(lineGlyphs: prepared.lines, layout: prepared.layout)
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
        let rect = rect.standardized
        if rect.isEmpty && clipBounds { return }
        if rect.isNull { return }

        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }
        if drawing.isEmpty { return }
        if let layout = drawing.layout {
            let layout = layout.placed(at: CGPoint(x: rect.minX + drawing.origin.x,
                                                  y: rect.minY + drawing.origin.y), shading: shading)
            var context = self
            if clipBounds { context.clip(to: Path(rect)) }
            for line in layout { context.draw(line) }
            return
        }
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

        func drawComponent(_ contents: TextDrawing.Contents, shading: Shading) {
            self.draw(TextDrawing(contents: contents, origin: drawing.origin,
                scale: 1 / drawing.source.scaleFactor, frame: rect,
                snapOrigin: snapOrigin, snappingOrigin: snappingOrigin,
                clipBounds: clipBounds), shading: shading)
        }
        for background in drawing.backgrounds {
            drawComponent(.background(background.frame), shading: .color(background.color))
        }
        for batch in drawing.vectorBatches {
            drawComponent(.vectorGlyphs(batch.path), shading: runShading(batch.foregroundColor))
        }
        var foregroundColors: [Color?] = []
        for batch in drawing.batches where !batch.colorGlyphs {
            if !foregroundColors.contains(batch.foregroundColor) {
                foregroundColors.append(batch.foregroundColor)
            }
        }
        for color in foregroundColors {
            let batches = drawing.batches.filter { !$0.colorGlyphs && $0.foregroundColor == color }
            drawComponent(.glyphs(batches), shading: runShading(color))
        }
        let colorGlyphs = drawing.batches.filter { $0.colorGlyphs }
        if !colorGlyphs.isEmpty || !drawing.attachments.isEmpty {
            drawComponent(.images(colorGlyphs, drawing.attachments), shading: .color(.white))
        }
        if !drawing.customAttachments.isEmpty,
           let placement = textDrawingPlacement(frame: rect, origin: drawing.origin,
               snapOrigin: snapOrigin, snappingOrigin: snappingOrigin,
               clipBounds: clipBounds && recording == nil) {
            // Recorded commands can later be replayed into a different viewport.
            for item in drawing.customAttachments {
                var context = self
                if clipBounds { context.clip(to: Path(placement.rect)) }
                var bounds = item.bounds
                bounds.origin += placement.rect.origin + drawing.origin
                item.attachment.draw(with: bounds, in: &context)
            }
        }
        for decoration in drawing.decorations {
            drawComponent(.decoration(decoration), shading: runShading(decoration.foregroundColor))
        }
        self.recordContentBounds(rect)
    }

    // A component owns only the geometry/resources needed for its draw command.
    struct TextDrawing {
        enum Contents {
            case background(CGRect)
            case vectorGlyphs(Path)
            case glyphs([ResolvedTextSource.Drawing.Batch])
            case images([ResolvedTextSource.Drawing.Batch], [ResolvedTextSource.Drawing.Attachment])
            case decoration(ResolvedTextSource.Drawing.Decoration)
        }
        let contents: Contents
        let origin: CGPoint
        let scale: CGFloat
        let frame: CGRect
        let snapOrigin: Bool
        let snappingOrigin: CGPoint?
        let clipBounds: Bool

        var shadingBounds: CGRect {
            guard case let .decoration(decoration) = contents else { return frame }
            let transform = CGAffineTransform(translationX: frame.minX + origin.x,
                y: frame.minY + origin.y).scaledBy(x: scale, y: scale)
            let start = decoration.start.applying(transform)
            let end = decoration.end.applying(transform)
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(start.x - end.x), height: abs(start.y - end.y))
        }

        var bounds: CGRect {
            var bounds = CGRect.null
            var clipped = true
            func include(_ batches: [ResolvedTextSource.Drawing.Batch]) {
                for batch in batches {
                    for vertex in batch.vertices {
                        let point = vertex.position
                        bounds = bounds.union(CGRect(origin: point, size: .zero))
                    }
                }
            }
            switch contents {
            case let .background(rect):
                bounds = rect
                clipped = false
            case let .vectorGlyphs(path):
                bounds = path.boundingBoxOfPath
            case let .glyphs(batches):
                include(batches)
            case let .images(batches, attachments):
                include(batches)
                for attachment in attachments { bounds = bounds.union(attachment.frame) }
            case let .decoration(decoration):
                let start = decoration.start
                let end = decoration.end
                bounds = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(start.x - end.x), height: abs(start.y - end.y))
                    .insetBy(dx: -decoration.lineWidth / 2, dy: -decoration.lineWidth / 2)
                clipped = false
            }
            bounds = bounds.applying(CGAffineTransform(translationX: frame.minX + origin.x,
                y: frame.minY + origin.y).scaledBy(x: scale, y: scale))
            return clipped && clipBounds ? bounds.intersection(frame) : bounds
        }
    }

    private func textDrawingPlacement(frame: CGRect, origin: CGPoint,
        snapOrigin: Bool, snappingOrigin: CGPoint?, clipBounds: Bool
    ) -> (rect: CGRect, scissor: ScissorRect?)? {
        var rect = frame
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
                let anchor = snappingOrigin ?? (rect.origin + origin)
                let relativeOffset = rect.origin + origin - anchor
                var pixelOrigin = anchor.applying(transform)
                pixelOrigin.x.round()
                pixelOrigin.y.round()
                rect.origin = pixelOrigin.applying(transform.inverted()) + relativeOffset - origin
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
                
                if minX >= self.viewport.maxX { return nil }
                if minY >= self.viewport.maxY { return nil }
                if maxX <= self.viewport.minX { return nil }
                if maxY <= self.viewport.minY { return nil }
                
                let x1 = max(Int(floor(minX)), Int(self.viewport.minX))
                let y1 = max(Int(floor(minY)), Int(self.viewport.minY))
                let x2 = min(Int(ceil(maxX)), Int(self.viewport.maxX))
                let y2 = min(Int(ceil(maxY)), Int(self.viewport.maxY))
                if x1 >= x2 || y1 >= y2 { return nil }
                
                scissorRect = ScissorRect(x: x1, y: y1,
                                          width: x2 - x1, height: y2 - y1)
            }
        }

        return (rect, scissorRect)
    }

    func draw(_ drawing: TextDrawing, shading: Shading) {
        if recording != nil, record(bounds: drawing.bounds, .text(drawing, shading)) { return }
        guard let placement = textDrawingPlacement(frame: drawing.frame, origin: drawing.origin,
            snapOrigin: drawing.snapOrigin, snappingOrigin: drawing.snappingOrigin,
            clipBounds: drawing.clipBounds) else { return }
        let rect = placement.rect
        let scale = drawing.scale
        let offset = rect.origin + drawing.origin
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
        switch drawing.contents {
        case let .background(frame):
            fill(Path(frame.applying(transform)), with: shading)
        case let .vectorGlyphs(path):
            guard let pass = beginRenderPass(enableStencil: true,
                enableMSAA: !environment.disableMSAA) else { return }
            if let scissor = placement.scissor { pass.encoder.setScissorRect(scissor) }
            if encodeStencilPathFillCommand(renderPass: pass, path: path, pathTransform: transform) {
                encodeShadingBoxCommand(renderPass: pass, shading: shading,
                    stencil: .testNonZero, blendState: .opaque, bounds: rect)
                pass.end()
                drawSource()
            } else {
                pass.end()
            }
        case let .glyphs(batches):
            guard let pass = beginRenderPass(enableStencil: false) else { return }
            if let scissor = placement.scissor { pass.encoder.setScissorRect(scissor) }
            encodeDrawTextCommand(renderPass: pass, batches: batches, transform: transform,
                color: .white, colorGlyphs: false)
            encodeShadingBoxCommand(renderPass: pass, shading: shading,
                stencil: .ignore, blendState: .multiply, bounds: rect)
            pass.end()
            drawSource()
        case let .images(batches, attachments):
            guard let pass = beginRenderPass(enableStencil: false) else { return }
            if let scissor = placement.scissor { pass.encoder.setScissorRect(scissor) }
            encodeDrawTextCommand(renderPass: pass, batches: batches, transform: transform,
                color: .white, colorGlyphs: true)
            for attachment in attachments {
                encodeDrawTextureCommand(renderPass: pass, texture: attachment.texture,
                    frame: attachment.frame, transform: transform, textureFrame: attachment.textureFrame,
                    textureTransform: .identity, blendState: .opaque, color: .white)
            }
            pass.end()
            drawSource()
        case let .decoration(decoration):
            var path = Path()
            path.move(to: decoration.start.applying(transform))
            path.addLine(to: decoration.end.applying(transform))
            let width = decoration.lineWidth * scale
            stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .butt,
                dash: decoration.dashPattern(lineWidth: width)))
        }
        recordContentBounds(rect)
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
                               batches: [ResolvedTextSource.Drawing.Batch],
                               transform: CGAffineTransform,
                               color: BackendColor,
                               colorGlyphs: Bool) {
        let c = color.float4
        let transform = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)

        for batch in batches {
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
