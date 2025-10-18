//
//  File: GraphicsContext+Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct ResolvedText {
        enum Storage {
            case text([TypeFace], String)
            case attachment([TypeFace], ResolvedImage)
        }
        var storage: [Storage]
        var scaleFactor: CGFloat

        var drawMissingGlyphs: Bool = false

        public var shading: Shading = .foreground

        public func measure(in size: CGSize) -> CGSize {
            let width = max(size.width, 0) * self.scaleFactor
            let height = max(size.height, 0) * self.scaleFactor
            let maxWidth: Int = (width > CGFloat(Int.max)) ? .max : Int(width)
            let maxHeight: Int = (height > CGFloat(Int.max)) ? .max : Int(height)

            let scale = 1.0 / self.scaleFactor
            return self.sizeInPixel(maxWidth: maxWidth, maxHeight: maxHeight) * scale
        }
        public func measure(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> CGSize {
            var width: Int = .max
            var height: Int = .max
            if let w = maxWidth {
                width = Int(w * self.scaleFactor)
            }
            if let h = maxHeight {
                height = Int(h * self.scaleFactor)
            }
            let scale = 1.0 / self.scaleFactor
            return self.sizeInPixel(maxWidth: width, maxHeight: height) * scale
        }
        public func firstBaseline(in size: CGSize) -> CGFloat {
            let width = max(size.width, 0) * self.scaleFactor
            let height = max(size.height, 0) * self.scaleFactor
            let maxWidth: Int = (width > CGFloat(Int.max)) ? .max : Int(width)
            let maxHeight: Int = (height > CGFloat(Int.max)) ? .max : Int(height)

            let scale = 1.0 / self.scaleFactor
            let glyphs = makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
            if let first = glyphs.first {
                return first.ascender * scale
            }
            return .zero
        }
        public func lastBaseline(in size: CGSize) -> CGFloat {
            let width = max(size.width, 0)
            let height = max(size.height, 0)
            let maxWidth: Int = (width > CGFloat(Int.max)) ? .max : Int(width)
            let maxHeight: Int = (height > CGFloat(Int.max)) ? .max : Int(height)

            let scale = 1.0 / self.scaleFactor
            let glyphs = makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
            let lastDescender = glyphs.last?.descender ?? 0
            return glyphs.reduce(.zero) { $0 + $1.height * scale } - lastDescender
        }

        struct Glyph {  // glyph that baseline aligned. (baseline is 0)
            var scalar: UnicodeScalar
            var face: TypeFace
            var texture: Texture?
            var frame: CGRect = .zero       // texture uv-coords
            var advance: CGSize = .zero     // distance to next glyph
            var offset: CGPoint = .zero     // texture origin position from baseline
            var ascender: CGFloat = .zero   // distance from the baseline to the highest or upper grid coordinate
            var descender: CGFloat = .zero  // distance from the baseline to the lowest
            var kerning: CGPoint = .zero    // kern advance from previous glyph.
        }

        struct LineGlyphs {
            var glyphs: [Glyph]
            var ascender: CGFloat
            var descender: CGFloat
            var width: CGFloat
            var height: CGFloat { ascender - descender }
        }

        private func sizeInPixel(maxWidth: Int = .max, maxHeight: Int = .max) -> CGSize {
            return makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
                .reduce(CGSize.zero) { result, line in
                    CGSize(width: max(result.width, line.width),
                           height: result.height + line.height)
                }
        }

        struct TextGlyphs {
            let glyphs: [Glyph]
            let width: CGFloat
            var height: CGFloat { ascender - descender }
            let ascender: CGFloat
            let descender: CGFloat
            let lastFace: TypeFace?
            let lastCharacter: UnicodeScalar
            static func from(unicodeScalars: String.UnicodeScalarView,
                             with faces: [TypeFace],
                             drawMissingGlyphs: Bool,
                             prevFace: TypeFace?,
                             prevChar: UnicodeScalar) -> Self {
                assert(faces.isEmpty == false)
                var glyphs: [Glyph] = []
                var ascender: CGFloat = .zero
                var descender: CGFloat = .zero
                var width: CGFloat = .zero
                var face1 = prevFace
                var char1 = prevChar
                for char2 in unicodeScalars {
                    let face2 = faces.first { $0.hasGlyph(for: char2) } ?? faces[0]

                    let makeGlyph = drawMissingGlyphs || face2.hasGlyph(for: char2) == true

                    var glyph = Glyph(scalar: char2, face: face2)
                    if makeGlyph, let data = face2.glyphData(for: char2) {
                        glyph.texture = data.texture
                        glyph.frame = data.frame
                        glyph.offset = data.offset
                        glyph.advance = data.advance
                        glyph.ascender = data.ascender
                        glyph.descender = data.descender
                        if let face1, face1.isEqual(to: face2) {
                            glyph.kerning = face1.kernAdvance(left: char1, right: char2)
                        } else {
                            glyph.kerning = .zero
                        }
                    } else {    // no glyph
                        glyph.ascender = face2.ascender
                        glyph.descender = face2.descender
                    }
                    glyphs.append(glyph)
                    ascender = max(ascender, glyph.ascender)
                    descender = min(descender, glyph.descender)
                    width += glyph.advance.width + glyph.kerning.x
                    char1 = char2
                    face1 = face2
                }

                if glyphs.isEmpty {
                    let face = faces[0]
                    ascender = face.ascender
                    descender = face.descender
                }
                assert((ascender - descender) > 0)
                return .init(glyphs: glyphs,
                             width: width,
                             ascender: ascender,
                             descender: descender,
                             lastFace: face1, lastCharacter: char1)
            }
        }

        func makeGlyphs(maxWidth: Int = .max, maxHeight: Int = .max) -> [LineGlyphs] {
            let lineGlyphs = _makeGlyphs()

            //return lineGlyphs
            return _lineWrap(lineGlyphs, maxWidth: maxWidth, maxHeight: maxHeight)
        }

        private func _lineWrap(_ lines: [LineGlyphs], maxWidth: Int, maxHeight: Int) -> [LineGlyphs] {
            var result: [LineGlyphs] = []
            let breakables = CharacterSet.whitespaces.union(.init(charactersIn: "-/?!}|"))
            let decimalNumbers = CharacterSet.decimalDigits
            // No wrap if character is followed by a decimal number
            let breakableNotBeforeDN = CharacterSet(charactersIn: "-")
            // No wrap if character is between decimal numbers
            let breakableNotBetweenDN = CharacterSet(charactersIn: "/")

            let getGlyphsWidth = { (glyphs: Array<Glyph>.SubSequence) -> CGFloat in
                glyphs.reduce(CGFloat.zero) { result, glyph in
                    result + glyph.advance.width + glyph.kerning.x
                } - (glyphs.first?.kerning.x ?? 0) // ignore first kerning
            }
            // Returns the index of the character that matches the wrapable character condition.
            let getBreakableIndex = { (glyphs: Array<Glyph>.SubSequence) -> Array<Glyph>.Index? in
                if glyphs.isEmpty { return nil }
                var index = glyphs.endIndex
                while index != glyphs.startIndex {
                    let index2 = glyphs.index(before: index)
                    let scalar = glyphs[index2].scalar
                    if breakables.contains(scalar) {
                        var beforeNumber = false
                        var afterNumber = false
                        if index != glyphs.endIndex {
                            beforeNumber = decimalNumbers.contains(glyphs[index].scalar)
                        }
                        if index2 != glyphs.startIndex {
                            let index3 = glyphs.index(before: index2)
                            afterNumber = decimalNumbers.contains(glyphs[index3].scalar)
                        }
                        if breakableNotBeforeDN.contains(scalar) && beforeNumber {
                            index = index2
                            continue
                        }
                        if breakableNotBetweenDN.contains(scalar) && beforeNumber && afterNumber {
                            index = index2
                            continue
                        }
                        return index2
                    }
                    index = index2
                }
                return nil
            }
            // Wrap long lines to satisfy line break conditions.
            let splitLineGlyphs = {
                (glyphs: [Glyph], maxWidth: Int) -> (first: Array<Glyph>.SubSequence, second: Array<Glyph>.SubSequence) in
                var first = glyphs[...]
                var second: [Glyph] = []
                while first.count > 1 && Int(ceil(getGlyphsWidth(first))) > maxWidth {
                    if let index = getBreakableIndex(first),
                       first.index(after:index) != first.endIndex {
                        let index2 = first.index(after: index)
                        let s1 = first[...index]
                        let s2 = first[index2...]
                        second.insert(contentsOf: s2, at: second.startIndex)
                        first = s1
                    } else {
                        if let s2 = first.popLast() {
                            second.insert(s2, at: second.startIndex)
                        }
                    }
                }
                return (first: first, second: second[...])
            }

            var offset: CGPoint = .zero
            var lines = lines
            while lines.isEmpty == false {
                var line = lines.removeFirst()
                if result.isEmpty == false && Int(ceil(offset.y + line.height)) > maxHeight {
                    break
                }

                if Int(ceil(line.width)) > maxWidth {
                    assert(line.glyphs.isEmpty == false)
                    // Do not wrap if there is not enough space to display the next line.
                    let nextLineHeight = lines.first?.height ?? line.height
                    if Int(ceil(offset.y + line.height + nextLineHeight)) <= maxHeight {
                        // The line can be wrapped because there is enough space for the next line.
                        let (first, second) = splitLineGlyphs(line.glyphs, maxWidth)
                        if second.isEmpty == false {
                            var glyphs: [Glyph] = .init(second)
                            glyphs[0].kerning = .zero
                            lines.insert(LineGlyphs(glyphs: glyphs,
                                                    ascender: second.reduce(0) { max($0, $1.ascender) },
                                                    descender: second.reduce(0) { min($0, $1.descender) },
                                                    width: getGlyphsWidth(second)),
                                         at: 0)
                            line.glyphs = .init(first)
                        }
                        assert(line.glyphs.isEmpty == false)

                        line.glyphs[0].kerning = .zero
                        line.ascender = line.glyphs.reduce(.zero) {
                            max($0, $1.ascender)
                        }
                        line.descender = line.glyphs.reduce(.zero) {
                            min($0, $1.descender)
                        }
                        line.width = getGlyphsWidth(line.glyphs[...])
                    }
                }

                // Check if there is not enough space to display the next line,
                // or if a line wrap failed because there was not enough space.
                let nextLineHeight = lines.first?.height ?? 0
                if Int(ceil(offset.y + line.height + nextLineHeight)) > maxHeight || Int(ceil(line.width)) > maxWidth {
                    // this is the last line, should ends with '...'
                    var glyphs = line.glyphs[...]
                    // Since a valid TypeFace is required, at least one glyph must exist.
                    if var face = glyphs.last?.face {
                        while true {
                            let prevFace = glyphs.last?.face
                            let prevChar: UnicodeScalar = glyphs.last?.scalar ?? UnicodeScalar(0)
                            let ellipsis = TextGlyphs.from(unicodeScalars: "...".unicodeScalars,
                                                           with: [face],
                                                           drawMissingGlyphs: false, prevFace: prevFace, prevChar: prevChar)

                            let width = getGlyphsWidth(glyphs)
                            if Int(ceil(width + ellipsis.width)) <= maxWidth {
                                glyphs.append(contentsOf: ellipsis.glyphs)
                                line.glyphs = .init(glyphs)
                                line.glyphs[0].kerning = .zero
                                line.ascender = line.glyphs.reduce(.zero) {
                                    max($0, $1.ascender)
                                }
                                line.descender = line.glyphs.reduce(.zero) {
                                    min($0, $1.descender)
                                }
                                line.width = getGlyphsWidth(line.glyphs[...])
                                break
                            }
                            // Use the TypeFace of the last removed glyph to generate the ellipsis glyphs.
                            if let last = glyphs.last {
                                face = last.face
                            } else {
                                // Stop here because there are no more glyphs to remove.
                                break
                            }
                            glyphs = glyphs.dropLast(1)
                        }
                    }
                }


                result.append(line)
                offset.y += line.height
            }
            return result
        }

        private func _makeGlyphs() -> [LineGlyphs] {
            var lines: [LineGlyphs] = []
            var glyphs: [Glyph] = []

            let newlines = CharacterSet.newlines

            var offset: CGPoint = .zero
            var ascender: CGFloat = .zero
            var descender: CGFloat = .zero
            var char1: UnicodeScalar = UnicodeScalar(0) // previous char
            var face1: TypeFace? = nil   // previous face

            let addLine = {
                lines.append(LineGlyphs(glyphs: glyphs,
                                        ascender: ascender,
                                        descender: descender,
                                        width: offset.x))
                glyphs.removeAll(keepingCapacity: true)
                let lineHeight = ascender - descender
                assert(lineHeight > 0)
                offset.x = 0
                offset.y += lineHeight
                ascender = 0
                descender = 0
            }

        storageLoop:
            for s in self.storage {
                if case let .text(faces, text) = s {
                    if faces.isEmpty || text.isEmpty { continue }

                    var components = text.components(separatedBy: newlines).map {
                        $0.unicodeScalars
                    }
                    while components.isEmpty == false {
                        let scalars = components.removeFirst()
                        let textGlyphs = TextGlyphs.from(unicodeScalars: scalars,
                                                         with: faces,
                                                         drawMissingGlyphs: self.drawMissingGlyphs,
                                                         prevFace: face1,
                                                         prevChar: char1)
                        face1 = textGlyphs.lastFace
                        char1 = textGlyphs.lastCharacter

                        glyphs.append(contentsOf: textGlyphs.glyphs)
                        ascender = max(ascender, textGlyphs.ascender)
                        descender = min(descender, textGlyphs.descender)
                        offset.x += textGlyphs.width

                        if components.isEmpty {
                            // The last line can be combined with other text.
                            // Don't complete the line.
                            break
                        }

                        addLine()
                    }
                }
                if case let .attachment(faces, image) = s {
                    let face = faces.first { $0.hasGlyph(for: ".") } ?? faces[0]
                    let size = image.size
                    let baseline = image.baseline * self.scaleFactor
                    let height = size.height * self.scaleFactor
                    let width = size.width * self.scaleFactor

                    var glyph = Glyph(scalar: UnicodeScalar(0), face: face)
                    glyph.texture = image.texture
                    glyph.offset = CGPoint(x: 0, y: baseline)
                    if let texture = image.texture {
                        glyph.frame = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
                    }
                    glyph.ascender = baseline
                    glyph.descender = min(0, baseline - height)
                    glyph.advance.width = width
                    glyph.advance.height = height
                    glyphs.append(glyph)

                    offset.x += glyph.advance.width
                    ascender = max(ascender, glyph.ascender)

                    face1 = nil
                    char1 = UnicodeScalar(0)
                }
            }
            if glyphs.isEmpty == false {
                let lineHeight = ascender - descender
                assert(lineHeight > 0)
                assert(offset.x > 0)

                lines.append(LineGlyphs(glyphs: glyphs,
                                        ascender: ascender,
                                        descender: descender,
                                        width: offset.x))
            }
            return lines
        }
    }

    public func draw(_ text: ResolvedText, in rect: CGRect) {
        draw(text, in: rect, shading: text.shading)
    }

    func draw(_ text: ResolvedText, in rect: CGRect, shading: Shading) {
        let rect = rect.standardized
        if rect.isEmpty { return }

        let x = Int(rect.origin.x * self.contentScaleFactor)
        let y = Int(rect.origin.y * self.contentScaleFactor)
        let width = Int(rect.width * self.contentScaleFactor)
        let height = Int(rect.height * self.contentScaleFactor)

        if x >= Int(self.viewport.maxX) || y >= Int(self.viewport.maxY) {
            return
        }

        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }

        let scale = 1.0 / text.scaleFactor
        let pixelAlignedX = ceil(rect.minX * text.scaleFactor) * scale
        let pixelAlignedY = ceil(rect.minY * text.scaleFactor) * scale
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: pixelAlignedX,
                                             y: pixelAlignedY))

        //let measure = text.measure(in: rect.size)

        let x1 = max(x, Int(self.viewport.minX))
        let x2 = min(x + width, Int(self.viewport.maxX))
        let y1 = max(y, Int(self.viewport.minY))
        let y2 = min(y + height, Int(self.viewport.maxY))
        if x1 >= x2 || y1 >= y2 { return }

        let lineGlyphs = text.makeGlyphs(maxWidth: width, maxHeight: height)
        if lineGlyphs.isEmpty { return }

        let clipBounds = true
        if let renderPass = self.beginRenderPass(enableStencil: false) {
            if clipBounds {
                renderPass.encoder.setScissorRect(ScissorRect(x: x1,
                                                              y: y1,
                                                              width: x2 - x1,
                                                              height: y2 - y1))
            }
            // drawing text glyphs in the alpha channel of a RenderTarget
            self.encodeDrawTextCommand(renderPass: renderPass,
                                       lineGlyphs: lineGlyphs,
                                       transform: transform,
                                       color: .white,
                                       blendState: .opaque)
            // applies shading to the RGB channels of the RenderTarget
            self.encodeShadingBoxCommand(renderPass: renderPass,
                                         shading: shading,
                                         stencil: .ignore,
                                         blendState: .multiply)
            // draw attachments (scalar = 0)
            forEachGlyph(in: lineGlyphs) { glyph, baseline in
                if glyph.scalar == UnicodeScalar(0), let texture = glyph.texture {
                    let frame = CGRect(x: baseline.x,
                                       y: baseline.y - glyph.offset.y,
                                       width: glyph.advance.width,
                                       height: glyph.advance.height)
                    self.encodeDrawTextureCommand(renderPass: renderPass,
                                                  texture: texture,
                                                  frame: frame,
                                                  transform: transform,
                                                  textureFrame: glyph.frame,
                                                  textureTransform: .identity,
                                                  blendState: .opaque,
                                                  color: .white)
                }
            }
            renderPass.end()
            self.drawSource()
        }
    }

    public func resolve(_ text: Text) -> ResolvedText {
        text._resolve(context: self)
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
    func forEachGlyph(in lineGlyphs: [ResolvedText.LineGlyphs],
                      callback: (_: ResolvedText.Glyph, _:CGPoint)->Void) {
        if lineGlyphs.isEmpty { return }

        var offset: CGPoint = .zero
        for line in lineGlyphs {
            offset.x = 0
            for glyph in line.glyphs {
                let baseline = CGPoint(x: glyph.offset.x + offset.x,
                                       y: line.ascender + offset.y)
                callback(glyph, baseline)

                // No kerning for line leads
                let kerning: CGPoint = offset.x > 0 ? glyph.kerning : .zero
                offset.x += glyph.advance.width
                offset += kerning
            }
            offset.y += line.height
        }
    }

    func encodeDrawTextCommand(renderPass: RenderPass,
                               lineGlyphs: [ResolvedText.LineGlyphs],
                               transform: CGAffineTransform,
                               color: VVD.Color,
                               blendState: BlendState) {
        if lineGlyphs.isEmpty { return }

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
        var quads: [Quad] = []

        forEachGlyph(in: lineGlyphs) { glyph, baseline in
            if glyph.scalar != UnicodeScalar(0), let texture = glyph.texture {
                let invW = 1.0 / Float(texture.width)
                let invH = 1.0 / Float(texture.height)

                let uvMinX = Float(glyph.frame.minX) * invW
                let uvMinY = Float(glyph.frame.minY) * invH
                let uvMaxX = Float(glyph.frame.maxX) * invW
                let uvMaxY = Float(glyph.frame.maxY) * invH

                let frame = CGRect(x: baseline.x,
                                   y: baseline.y - glyph.offset.y,
                                   width: glyph.frame.width,
                                   height: glyph.frame.height)

                let q = Quad(
                    lt: GlyphVertex(pos: Vector2(frame.minX, frame.minY),
                                    tex: (uvMinX, uvMinY)),
                    rt: GlyphVertex(pos: Vector2(frame.maxX, frame.minY),
                                    tex: (uvMaxX, uvMinY)),
                    lb: GlyphVertex(pos: Vector2(frame.minX, frame.maxY),
                                    tex: (uvMinX, uvMaxY)),
                    rb: GlyphVertex(pos: Vector2(frame.maxX, frame.maxY),
                                    tex: (uvMaxX, uvMaxY)),
                    texture: texture)
                quads.append(q)
            }
        }

        quads.sort {
            ObjectIdentifier($0.texture) > ObjectIdentifier($1.texture)
        }

        let c = color.float4
        let transform = transform
            .concatenating(self.transform)
            .concatenating(self.viewTransform)

        var texture: Texture? = nil
        var vertices: [_Vertex] = []
        let draw = {
            if vertices.isEmpty == false {
                self.encodeDrawCommand(renderPass: renderPass,
                                       shader: .rcImage,
                                       stencil: .ignore,
                                       vertices: vertices,
                                       texture: texture,
                                       blendState: .alphaBlend)
                vertices.removeAll(keepingCapacity: true)
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
