//
//  File: GraphicsContext+Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
    public struct ResolvedText {
        public func measure(in size: CGSize) -> CGSize {
            var width: CGFloat = .zero
            var height: CGFloat = .zero
            var y: CGFloat = .zero
            rearrangeLineGlyphs(toFit: size).forEach {
                let w = Glyph.width($0.glyphs)
                let h = y + $0.lineHeight
                width = max(width, w)
                height = max(height, h)
                y = height
            }
            return CGSize(width: width, height: height)
        }
        public func firstBaseline(in size: CGSize) -> CGFloat {
            rearrangeLineGlyphs(toFit: size).first?.baseline ?? 0
        }
        public func lastBaseline(in size: CGSize) -> CGFloat {
            rearrangeLineGlyphs(toFit: size).last?.baseline ?? 0
        }
        public var shading: Shading

        func rearrangeLineGlyphs(toFit size: CGSize) -> [Line] {
            let whitespaces = CharacterSet.whitespaces
            let breakables = CharacterSet.whitespaces
                .union(.init(charactersIn: "-/?!}|"))

            var lines: [Line] = []
            self.lines.forEach { line in
                if line.glyphs.isEmpty {    // empty line.
                    lines.append(line)
                } else {
                    var glyphs = line.glyphs[...]
                    var remains: [Glyph] = []
                    remains.reserveCapacity(glyphs.count)

                    while glyphs.isEmpty == false {
                        if glyphs.count > 1 &&
                            Glyph.width(glyphs) > size.width { // split!
                            if let index = glyphs.lastIndex(where: {
                                breakables.contains($0.scalar)
                            }), index < glyphs.count - 1 {
                                remains.insert(contentsOf: glyphs[(index+1)...],
                                               at: remains.startIndex)
                                glyphs = glyphs[...index]
                            } else { // no whitespace, break characters.
                                remains.insert(glyphs.removeLast(),
                                               at: remains.startIndex)
                            }
                        } else {
                            // remove tailing whitespaces
                            while let last = glyphs.last,
                                  whitespaces.contains(last.scalar) {
                                glyphs.removeLast()
                            }
                            lines.append(Line(glyphs: Array(glyphs),
                                              bounds: Glyph.bounds(glyphs),
                                              baseline: line.baseline,
                                              lineWidth: Glyph.width(glyphs),
                                              lineHeight: line.lineHeight))
                            glyphs = remains[...]
                            // remove leading whitespaces
                            while let first = glyphs.first,
                                  whitespaces.contains(first.scalar) {
                                glyphs.removeFirst()
                            }
                            remains.removeAll(keepingCapacity: true)
                        }
                    }
                    assert(remains.isEmpty)
                }
            }
            let numVisibleLines = {
                var n = 0
                var offset = CGFloat.zero
                for line in lines {
                    offset += line.lineHeight
                    if offset > size.height { break }
                    n += 1
                }
                return n
            }()
            if lines.isEmpty == false, numVisibleLines < lines.count {
                let index = max(numVisibleLines-1, 0)
                var line = lines[index]
                let offset = line.baseline - self.ellipsisBaseline
                let ellipsisWidth = Glyph.width(self.ellipsis)
                while line.glyphs.isEmpty == false,
                    Glyph.width(line.glyphs) + ellipsisWidth > size.width {
                    line.glyphs.removeLast()
                }
                line.glyphs.append(contentsOf: self.ellipsis.map {
                    var glyph = $0
                    glyph.position.y += offset
                    return glyph
                })
                lines[index] = line
                lines = Array(lines[...index])
            }
            return lines
        }

        struct Glyph {
            var scalar: UnicodeScalar
            var texture: Texture?
            var position: CGPoint
            var size: CGSize
            var advance: CGSize
            var frame: CGRect
            var kerning: CGPoint

            static func width(_ glyphs: any Sequence<Glyph>) -> CGFloat {
                glyphs.reduce(CGFloat.zero) {
                    if $0 > 0 { return $0 + $1.advance.width + $1.kerning.x }
                    return $0 + $1.advance.width
                }
            }
            static func bounds(_ glyphs: any Sequence<Glyph>) -> CGRect {
                var bounds: CGRect = .null
                var offset: CGFloat = .zero
                glyphs.forEach { glyph in
                    let frame = CGRect(origin: glyph.position, size: glyph.size)
                        .offsetBy(dx: offset, dy: 0)
                    bounds = bounds.union(frame)
                    if offset > .zero { offset += glyph.kerning.x }
                    offset += glyph.advance.width
                }
                return bounds
            }
        }
        struct Line {
            var glyphs: [Glyph]
            var bounds: CGRect
            var baseline: CGFloat
            var lineWidth: CGFloat
            var lineHeight: CGFloat
        }
        let lines: [Line]
        let ellipsis: [Glyph]  // '...'
        let ellipsisBaseline: CGFloat

        var frame: CGRect {
            var frame: CGRect = .null
            var y: CGFloat = .zero
            lines.forEach {
                let width = max(Glyph.width($0.glyphs), $0.lineWidth)
                let height = $0.lineHeight
                let rect = CGRect(x: 0, y: y, width: width, height: height)
                frame = frame.union(rect)
                y += height
            }
            return frame
        }
    }

    public func resolve(_ text: Text) -> ResolvedText {
        var lines: [ResolvedText.Line] = []
        var ellipsis: [ResolvedText.Glyph] = []
        var ellipsisBaseline: CGFloat = 0
        let displayScale = self.environment.displayScale
        assert(displayScale > .ulpOfOne)
        let font = (text.font ?? self.environment.font)?
            .displayScale(displayScale)
        if let typeFace = font?.typeFace(forContext: self.sharedContext) {
            let fallbackFaces = font!.fallbackTypeFaces

            let newlines = CharacterSet.newlines

            var bounds: CGRect = .null
            var offset: CGFloat = .zero
            var glyphs: [ResolvedText.Glyph] = []
            let lineHeight: CGFloat = typeFace.lineHeight / displayScale

            var c1: UnicodeScalar = UnicodeScalar(0)
            var face1 = typeFace

            let makeGlyphLine = {
                let baseline = 0 - bounds.minY
                let line = ResolvedText.Line(
                    // adjusts the glyph position relative to the baseline.
                    glyphs: glyphs.map {
                        var glyph = $0
                        glyph.position.y += baseline
                        return glyph
                    },
                    bounds: bounds.offsetBy(dx: 0, dy: baseline),
                    baseline: baseline,
                    lineWidth: offset,
                    lineHeight: lineHeight)

                bounds = .null
                offset = .zero
                glyphs = []
                c1 = UnicodeScalar(0)
                face1 = typeFace
                return line
            }

            let str = text.storage.unicodeScalars
            for char in str {
                let c2 = char as! UnicodeScalar

                if newlines.contains(c2) {
                    lines.append(makeGlyphLine())
                } else {
                    var face2 = typeFace
                    if face2.hasGlyph(for: c2) == false {
                        for face in fallbackFaces {
                            if face.hasGlyph(for: c2) {
                                face2 = face
                                break
                            }
                        }
                    }
                    if let glyph = face2.glyphData(for: c2) {
                        // Adjust the font scale of the fallback font.
                        let scale = typeFace.ascender / (face2.ascender *
                                                         displayScale)
                        let position = CGPoint(
                            x: glyph.position.x,
                            y: glyph.position.y - glyph.ascender) * scale
                        let advance = glyph.advance * scale
                        let size = glyph.frame.size * scale

                        let frame = CGRect(origin: position, size: size)
                        bounds = bounds.union(frame.offsetBy(dx: offset, dy: 0))

                        var kerning: CGPoint = .zero
                        if face2.isEqual(to: face1) {
                            kerning = face2.kernAdvance(left: c1, right: c2)
                        }
                        kerning = kerning * scale

                        let resolvedGlyph = ResolvedText.Glyph(
                            scalar: c2,
                            texture: glyph.texture,
                            position: position,
                            size: size,
                            advance: advance,
                            frame: glyph.frame,
                            kerning: kerning)
                        glyphs.append(resolvedGlyph)

                        offset += advance.width + kerning.x
                    }
                    c1 = c2
                    face1 = face2
                }
            }
            // last line
            if glyphs.isEmpty == false {
                lines.append(makeGlyphLine())
            }

            // generate ellipsis glyphs...
            let scale = 1.0 / displayScale
            ellipsisBaseline = typeFace.ascender * scale
            c1 = UnicodeScalar(0)
            for c2 in text.ellipsis.unicodeScalars {
                if let glyph = typeFace.glyphData(for: c2) {
                    let position = glyph.position * scale
                    let size = glyph.frame.size * scale
                    let advance = glyph.advance * scale
                    let kerning = typeFace.kernAdvance(left: c1,
                                                       right: c2) * scale
                    ellipsis.append(ResolvedText.Glyph(scalar: c2,
                                                       texture: glyph.texture,
                                                       position: position,
                                                       size: size,
                                                       advance: advance,
                                                       frame: glyph.frame,
                                                       kerning: kerning))
                }
                c1 = c2
            }
        }
        return ResolvedText(shading: .foreground,
                            lines: lines,
                            ellipsis: ellipsis,
                            ellipsisBaseline: ellipsisBaseline)
    }

    public func draw(_ text: ResolvedText, in rect: CGRect) {
        let rect = rect.standardized
        if rect.isEmpty { return }

        var lines = text.lines
        let frame = text.frame
        if rect.size.width < frame.width || rect.size.height < frame.height {
            lines = text.rearrangeLineGlyphs(toFit: rect.size)
        }
        if lines.isEmpty { return }

        guard let shading = text.shading.properties.first else {
            fatalError()
        }

        let transform = CGAffineTransform(translationX: rect.origin.x,
                                          y: rect.origin.y)
        let measure = text.measure(in: rect.size)
 
        let x = Int(rect.origin.x * self.contentScaleFactor)
        let y = Int(rect.origin.y * self.contentScaleFactor)
        let width = Int(rect.width * self.contentScaleFactor)
        let height = Int(rect.height * self.contentScaleFactor)

        if let encoder = self.makeEncoder(enableStencil: false) {
             encoder.setScissorRect(ScissorRect(x: x, y: y,
                                                width: width,
                                                height: height))
            self.encodeDrawTextCommand(lines,
                                       transform: transform,
                                       color: .white,
                                       blendState: .opaque,
                                       encoder: encoder)
            self.encodeShadingBoxCommand(text.shading,
                                         stencil: .ignore,
                                         blendState: .multiply,
                                         encoder: encoder)
            encoder.endEncoding()

            self.applyFilters()
            self.applyBlendModeAndMask()
        }
    }

    public func draw(_ text: ResolvedText,
                     at point: CGPoint,
                     anchor: UnitPoint = .center) {
        if text.lines.isEmpty { return }

        var frame = text.frame
        let origin = CGPoint(x: point.x - frame.width * anchor.x,
                             y: point.y - frame.height * anchor.y)
        frame.origin = origin
        draw(text, in: frame)
    }
    public func draw(_ text: Text, in rect: CGRect) {
        draw(resolve(text), in: rect)
    }
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(text), at: point, anchor: anchor)
    }

    func encodeDrawTextCommand(_ lines: [ResolvedText.Line],
                               transform: CGAffineTransform,
                               color: DKGame.Color,
                               blendState: BlendState,
                               encoder: RenderCommandEncoder) {
        if lines.isEmpty { return }
        
        struct GlyphVertex {
            let pos: Vector2
            let tex: Float2
        }
        struct Quad {
            let lt: GlyphVertex
            let rt: GlyphVertex
            let lb: GlyphVertex
            let rb: GlyphVertex
            let texture: Texture
        }

        let c = color.float4
        let transform = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)

        var quads: [Quad] = []
        var offset: Vector2 = .zero
        for line in lines {
            offset.x = 0
            for glyph in line.glyphs {
                if let texture = glyph.texture {
                    let invW = 1.0 / Float(texture.width)
                    let invH = 1.0 / Float(texture.height)

                    let uvMinX = Float(glyph.frame.minX) * invW
                    let uvMinY = Float(glyph.frame.minY) * invH
                    let uvMaxX = Float(glyph.frame.maxX) * invW
                    let uvMaxY = Float(glyph.frame.maxY) * invH

                    let posMin = Vector2(glyph.position) + offset
                    let posMax = Vector2(glyph.size) + posMin

                    let q = Quad(
                        lt: GlyphVertex(pos: Vector2(posMin.x, posMin.y),
                                        tex: (uvMinX, uvMinY)),
                        rt: GlyphVertex(pos: Vector2(posMax.x, posMin.y),
                                        tex: (uvMaxX, uvMinY)),
                        lb: GlyphVertex(pos: Vector2(posMin.x, posMax.y),
                                        tex: (uvMinX, uvMaxY)),
                        rb: GlyphVertex(pos: Vector2(posMax.x, posMax.y),
                                        tex: (uvMaxX, uvMaxY)),
                        texture: texture)
                    quads.append(q)
                }
                // No kerning for line leads
                let kerning: CGPoint = offset.x > 0 ? glyph.kerning : .zero
                offset.x += glyph.advance.width
                offset += Vector2(kerning)
            }
            offset.y += line.lineHeight
        }
        quads.sort {
            ObjectIdentifier($0.texture) > ObjectIdentifier($1.texture)
        }
        var texture: Texture? = nil
        var vertices: [_Vertex] = []
        let draw = {
            if vertices.isEmpty == false {
                self.encodeDrawCommand(shader: .rcImage,
                                       stencil: .ignore,
                                       vertices: vertices,
                                       texture: texture,
                                       blendState: .alphaBlend,
                                       encoder: encoder)
                vertices = []
            }
        }
        for quad in quads {
            if quad.texture !== texture {
                draw()
                texture = quad.texture
            }
            vertices.append(contentsOf: [quad.lb, quad.lt, quad.rb].map {
                _Vertex(position: $0.pos.applying(transform).float2,
                        texcoord: $0.tex,
                        color: c)
                })
            vertices.append(contentsOf: [quad.rb, quad.lt, quad.rt].map {
                _Vertex(position: $0.pos.applying(transform).float2,
                        texcoord: $0.tex,
                        color: c)
                })
        }
        draw()
    }
}
