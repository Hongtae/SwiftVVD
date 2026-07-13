//
//  File: GraphicsContext+Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

extension GraphicsContext {
    public struct ResolvedText {
        enum Run {
            case text([Typeface], String)
            case attachment([Typeface], ResolvedImage)
            case attributedText([Typeface], String, _TextAttributeValues)
            case attributedAttachment([Typeface], ResolvedImage, _TextAttributeValues)
            case styledText(
                [Typeface],
                String,
                _TextAttributeValues,
                _ResolvedTextRunAttributes
            )

            func applying(_ attributes: _TextAttributeValues) -> Run {
                guard !attributes.isEmpty else { return self }
                switch self {
                case let .text(faces, text):
                    return .attributedText(faces, text, attributes)
                case let .attributedText(faces, text, existing):
                    var merged = existing
                    merged.merge(attributes)
                    return .attributedText(faces, text, merged)
                case let .attachment(faces, image):
                    return .attributedAttachment(faces, image, attributes)
                case let .attributedAttachment(faces, image, existing):
                    var merged = existing
                    merged.merge(attributes)
                    return .attributedAttachment(faces, image, merged)
                case let .styledText(faces, text, existing, style):
                    var merged = existing
                    merged.merge(attributes)
                    return .styledText(faces, text, merged, style)
                }
            }
        }

        final class Storage: AppLifetimeResource, @unchecked Sendable {
            private struct State: @unchecked Sendable {
                var runs: [Run]
                var cachedLines: [LineGlyphs]?
                var terminated: Bool = false
            }

            private let state: Mutex<State>
            let scaleFactor: CGFloat
            let drawMissingGlyphs: Bool

            init(runs: [Run], scaleFactor: CGFloat, drawMissingGlyphs: Bool) {
                self.state = Mutex(State(runs: runs))
                self.scaleFactor = scaleFactor
                self.drawMissingGlyphs = drawMissingGlyphs
            }

            var runs: [Run] {
                var runs: [Run] = []
                state.withLock { state in
                    runs = state.runs
                }
                return runs
            }

            func lineGlyphs(make: ([Run]) -> [LineGlyphs]) -> [LineGlyphs] {
                var cachedLines: [LineGlyphs]?
                var runs: [Run]?
                var terminated = false
                state.withLock { state in
                    if state.terminated {
                        terminated = true
                    } else if let lines = state.cachedLines {
                        cachedLines = lines
                    } else {
                        runs = state.runs
                    }
                }

                if terminated {
                    return []
                }
                if let cachedLines {
                    return cachedLines
                }
                guard let runs else {
                    return []
                }

                let made = make(runs)
                var lineGlyphs = made

                state.withLock { state in
                    if state.terminated {
                        lineGlyphs = []
                    } else if let cachedLines = state.cachedLines {
                        lineGlyphs = cachedLines
                    } else {
                        state.cachedLines = made
                    }
                }
                return lineGlyphs
            }

            override func purgeResources(reason: ResourcePurgeReason) {
                state.withLock { state in
                    state.cachedLines = nil
                    if reason == .appTermination {
                        state.runs.removeAll()
                        state.terminated = true
                    }
                }
            }
        }

        private let storage: Storage

        init(runs: [Run], scaleFactor: CGFloat, drawMissingGlyphs: Bool = false) {
            self.storage = Storage(
                runs: runs,
                scaleFactor: scaleFactor,
                drawMissingGlyphs: drawMissingGlyphs
            )
        }

        var runs: [Run] { storage.runs }
        var scaleFactor: CGFloat { storage.scaleFactor }
        fileprivate var drawMissingGlyphs: Bool { storage.drawMissingGlyphs }

        var attributedStorage: NSAttributedString {
            let result = NSMutableAttributedString(string: "")
            for run in runs {
                switch run {
                case let .text(_, text),
                     let .attributedText(_, text, _):
                    result.append(NSAttributedString(string: text))
                case let .styledText(_, text, _, style):
                    result.append(NSAttributedString(
                        string: text,
                        attributes: style.nsAttributes
                    ))
                case .attachment, .attributedAttachment:
                    result.append(NSAttributedString(
                        string: "\u{fffc}",
                        attributes: [.resolvedTextAttachment: true]
                    ))
                }
            }
            return result
        }

        var hasAttachments: Bool {
            runs.contains { run in
                switch run {
                case .attachment, .attributedAttachment: true
                case .text, .attributedText, .styledText: false
                }
            }
        }

        var resolvedFeatures: Text.ResolvedProperties.Features {
            hasAttachments ? .attachments : []
        }

        var maximumFontMetrics: ResolvedFontMetrics? {
            var result: ResolvedFontMetrics?
            for run in runs {
                let faces: [Typeface]
                switch run {
                case let .text(runFaces, _),
                     let .attachment(runFaces, _),
                     let .attributedText(runFaces, _, _),
                     let .attributedAttachment(runFaces, _, _),
                     let .styledText(runFaces, _, _, _):
                    faces = runFaces
                }
                guard let face = faces.first else { continue }
                let metrics = face.resolvedMetrics.scaled(by: scaleFactor)
                if result == nil {
                    result = metrics
                } else {
                    result?.formUnion(metrics)
                }
            }
            return result
        }

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
            if let w = maxWidth, w < CGFloat(width) {
                width = Int(w * self.scaleFactor)
            }
            if let h = maxHeight, h < CGFloat(height) {
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
            let width = max(size.width, 0) * self.scaleFactor
            let height = max(size.height, 0) * self.scaleFactor
            let maxWidth: Int = (width > CGFloat(Int.max)) ? .max : Int(width)
            let maxHeight: Int = (height > CGFloat(Int.max)) ? .max : Int(height)

            let scale = 1.0 / self.scaleFactor
            let glyphs = makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
            guard let last = glyphs.last else { return .zero }
            let baseline = glyphs.dropLast().reduce(CGFloat.zero) { $0 + $1.height } + last.ascender
            return baseline * scale
        }

        struct Glyph {  // glyph that baseline aligned. (baseline is 0)
            struct TextureContent {
                var texture: Texture?
                var frame: CGRect       // texture uv-coords
                var offset: CGPoint     // texture origin position from baseline
            }

            struct VectorContent {
                var path: Path
            }

            struct AttachmentContent {
                var texture: Texture?
                var frame: CGRect       // texture uv-coords
                var offset: CGPoint     // texture origin position from baseline
            }

            enum Content {
                case texture(TextureContent)
                case vector(VectorContent)
                case attachment(AttachmentContent)
                case missing
            }

            var scalar: UnicodeScalar
            var face: Typeface
            var content: Content = .missing
            var advance: CGSize = .zero     // distance to next glyph
            var ascender: CGFloat = .zero   // distance from the baseline to the highest or upper grid coordinate
            var descender: CGFloat = .zero  // distance from the baseline to the lowest
            var kerning: CGPoint = .zero    // kern advance from previous glyph.
            var attributes = _TextAttributeValues()
            var foregroundColor: Color?

            var contentOffset: CGPoint {
                switch content {
                case .texture(let data):
                    return data.offset
                case .attachment(let data):
                    return data.offset
                case .vector, .missing:
                    return .zero
                }
            }
        }

        struct LineGlyphs {
            var glyphs: [Glyph]
            var ascender: CGFloat
            var descender: CGFloat
            var width: CGFloat
            var height: CGFloat { ascender - descender }
        }

        final class Drawing {
            fileprivate struct Vertex {
                var position: CGPoint
                var texcoord: Float2
            }

            fileprivate struct Batch {
                var texture: Texture
                var vertices: [Vertex]
                var colorGlyphs: Bool
                var foregroundColor: Color?
            }

            fileprivate struct Attachment {
                var texture: Texture
                var frame: CGRect
                var textureFrame: CGRect
            }

            fileprivate var source: ResolvedText
            fileprivate var lineGlyphs: [LineGlyphs]
            fileprivate var batches: [Batch]
            fileprivate var attachments: [Attachment]

            fileprivate init(
                source: ResolvedText,
                lineGlyphs: [LineGlyphs],
                batches: [Batch],
                attachments: [Attachment]
            ) {
                self.source = source
                self.lineGlyphs = lineGlyphs
                self.batches = batches
                self.attachments = attachments
            }

            var isEmpty: Bool {
                lineGlyphs.isEmpty
            }
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
            let lastFace: Typeface?
            let lastCharacter: UnicodeScalar
            static func from(unicodeScalars: String.UnicodeScalarView,
                             with faces: [Typeface],
                             drawMissingGlyphs: Bool,
                             prevFace: Typeface?,
                             prevChar: UnicodeScalar) -> Self {
                assert(faces.isEmpty == false)
                var glyphs: [Glyph] = []
                var ascender: CGFloat = .zero
                var descender: CGFloat = .zero
                var width: CGFloat = .zero
                var face1 = prevFace
                var char1 = prevChar

                // Text rendering currently supports texture glyphs only.
                func textureGlyph(_ face: any Typeface, _ c: UnicodeScalar) -> TextureTypeface.GlyphData? {
                    if case let .texture(data) = face.glyph(for: c) {
                        return data
                    }
                    return nil
                }

                for char2 in unicodeScalars {
                    let face2 = faces.first { $0.hasGlyph(for: char2) } ?? faces[0]

                    let makeGlyph = drawMissingGlyphs || face2.hasGlyph(for: char2) == true

                    var glyph = Glyph(scalar: char2, face: face2)
                    if makeGlyph, let data = textureGlyph(face2, char2) {
                        glyph.content = .texture(.init(texture: data.texture,
                                                       frame: data.frame,
                                                       offset: data.offset))
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
            let lineGlyphs = storage.lineGlyphs { runs in
                Self._makeGlyphs(
                    runs: runs,
                    scaleFactor: self.scaleFactor,
                    drawMissingGlyphs: self.drawMissingGlyphs
                )
            }

            return _lineWrap(lineGlyphs, maxWidth: maxWidth, maxHeight: maxHeight)
        }

        func makeDrawing(in size: CGSize) -> Drawing {
            let width = max(size.width, 0) * scaleFactor
            let height = max(size.height, 0) * scaleFactor
            let maxWidth = width > CGFloat(Int.max) ? Int.max : Int(width)
            let maxHeight = height > CGFloat(Int.max) ? Int.max : Int(height)
            let lineGlyphs = makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
            return makeDrawing(lineGlyphs: lineGlyphs)
        }

        func makeDrawing(lineGlyphs: [LineGlyphs]) -> Drawing {

            struct Quad {
                var vertices: [Drawing.Vertex]
                var texture: Texture
                var colorGlyphs: Bool
                var foregroundColor: Color?
            }

            var quads: [Quad] = []
            var attachments: [Drawing.Attachment] = []
            Self.forEachGlyph(in: lineGlyphs) { glyph, baseline in
                switch glyph.content {
                case let .texture(data):
                    guard glyph.scalar != UnicodeScalar(0),
                          let texture = data.texture else {
                        return
                    }
                    let colorGlyphs: Bool
                    switch texture.pixelFormat {
                    case .r8Unorm:
                        colorGlyphs = false
                    case .bgra8Unorm, .bgra8Unorm_srgb:
                        colorGlyphs = true
                    default:
                        assertionFailure("Unsupported glyph texture format: \(texture.pixelFormat)")
                        return
                    }

                    let invW = 1.0 / Float(texture.width)
                    let invH = 1.0 / Float(texture.height)
                    let pad: CGFloat = 1
                    let textureFrame = data.frame.insetBy(dx: -pad, dy: -pad)
                    let frame = CGRect(
                        x: baseline.x,
                        y: baseline.y - data.offset.y,
                        width: data.frame.width,
                        height: data.frame.height
                    ).insetBy(dx: -pad, dy: -pad)
                    let uvMinX = Float(textureFrame.minX) * invW
                    let uvMinY = Float(textureFrame.minY) * invH
                    let uvMaxX = Float(textureFrame.maxX) * invW
                    let uvMaxY = Float(textureFrame.maxY) * invH
                    let lt = Drawing.Vertex(
                        position: CGPoint(x: frame.minX, y: frame.minY),
                        texcoord: (uvMinX, uvMinY)
                    )
                    let rt = Drawing.Vertex(
                        position: CGPoint(x: frame.maxX, y: frame.minY),
                        texcoord: (uvMaxX, uvMinY)
                    )
                    let lb = Drawing.Vertex(
                        position: CGPoint(x: frame.minX, y: frame.maxY),
                        texcoord: (uvMinX, uvMaxY)
                    )
                    let rb = Drawing.Vertex(
                        position: CGPoint(x: frame.maxX, y: frame.maxY),
                        texcoord: (uvMaxX, uvMaxY)
                    )
                    quads.append(Quad(
                        vertices: [lb, lt, rb, rb, lt, rt],
                        texture: texture,
                        colorGlyphs: colorGlyphs,
                        foregroundColor: glyph.foregroundColor
                    ))

                case let .attachment(data):
                    guard glyph.scalar == UnicodeScalar(0),
                          let texture = data.texture else {
                        return
                    }
                    attachments.append(Drawing.Attachment(
                        texture: texture,
                        frame: CGRect(
                            x: baseline.x,
                            y: baseline.y - data.offset.y,
                            width: glyph.advance.width,
                            height: glyph.advance.height
                        ),
                        textureFrame: data.frame
                    ))

                case .vector, .missing:
                    break
                }
            }

            quads.sort { lhs, rhs in
                if lhs.colorGlyphs != rhs.colorGlyphs {
                    return !lhs.colorGlyphs
                }
                return ObjectIdentifier(lhs.texture) > ObjectIdentifier(rhs.texture)
            }

            var batches: [Drawing.Batch] = []
            for quad in quads {
                if let last = batches.indices.last,
                   batches[last].texture === quad.texture,
                   batches[last].colorGlyphs == quad.colorGlyphs,
                   batches[last].foregroundColor == quad.foregroundColor {
                    batches[last].vertices.append(contentsOf: quad.vertices)
                } else {
                    batches.append(Drawing.Batch(
                        texture: quad.texture,
                        vertices: quad.vertices,
                        colorGlyphs: quad.colorGlyphs,
                        foregroundColor: quad.foregroundColor
                    ))
                }
            }

            return Drawing(
                source: self,
                lineGlyphs: lineGlyphs,
                batches: batches,
                attachments: attachments
            )
        }

        fileprivate static func forEachGlyph(
            in lineGlyphs: [LineGlyphs],
            callback: (_ glyph: Glyph, _ baseline: CGPoint) -> Void
        ) {
            var offset: CGPoint = .zero
            for line in lineGlyphs {
                offset.x = 0
                for glyph in line.glyphs {
                    let baseline = CGPoint(
                        x: glyph.contentOffset.x + offset.x,
                        y: line.ascender + offset.y
                    )
                    callback(glyph, baseline)
                    let kerning: CGPoint = offset.x > 0 ? glyph.kerning : .zero
                    offset.x += glyph.advance.width
                    offset += kerning
                }
                offset.y += line.height
            }
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
                    // Since a valid Typeface is required, at least one glyph must exist.
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
                            // Use the Typeface of the last removed glyph to generate the ellipsis glyphs.
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

        private static func _makeGlyphs(
            runs: [Run],
            scaleFactor: CGFloat,
            drawMissingGlyphs: Bool) -> [LineGlyphs] {
            var lines: [LineGlyphs] = []
            var glyphs: [Glyph] = []

            let newlines = CharacterSet.newlines

            var offset: CGPoint = .zero
            var ascender: CGFloat = .zero
            var descender: CGFloat = .zero
            var char1: UnicodeScalar = UnicodeScalar(0) // previous char
            var face1: Typeface? = nil   // previous face

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

            for s in runs {
                let textRun: (
                    [Typeface],
                    String,
                    _TextAttributeValues,
                    _ResolvedTextRunAttributes?
                )?
                switch s {
                case let .text(faces, text):
                    textRun = (faces, text, _TextAttributeValues(), nil)
                case let .attributedText(faces, text, attributes):
                    textRun = (faces, text, attributes, nil)
                case let .styledText(faces, text, attributes, style):
                    textRun = (faces, text, attributes, style)
                case .attachment, .attributedAttachment:
                    textRun = nil
                }
                if let (faces, text, attributes, style) = textRun {
                    if faces.isEmpty || text.isEmpty { continue }

                    var components = text.components(separatedBy: newlines).map {
                        $0.unicodeScalars
                    }
                    while components.isEmpty == false {
                        let scalars = components.removeFirst()
                        let textGlyphs = TextGlyphs.from(unicodeScalars: scalars,
                                                         with: faces,
                                                         drawMissingGlyphs: drawMissingGlyphs,
                                                         prevFace: face1,
                                                         prevChar: char1)
                        face1 = textGlyphs.lastFace
                        char1 = textGlyphs.lastCharacter

                        glyphs.append(contentsOf: textGlyphs.glyphs.map { glyph in
                            var glyph = glyph
                            glyph.attributes = attributes
                            glyph.foregroundColor = style?.foregroundColor
                            return glyph
                        })
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
                let attachmentRun: ([Typeface], ResolvedImage, _TextAttributeValues)?
                switch s {
                case let .attachment(faces, image):
                    attachmentRun = (faces, image, _TextAttributeValues())
                case let .attributedAttachment(faces, image, attributes):
                    attachmentRun = (faces, image, attributes)
                case .text, .attributedText, .styledText:
                    attachmentRun = nil
                }
                if let (faces, image, attributes) = attachmentRun {
                    guard !faces.isEmpty else { continue }
                    let face = faces.first { $0.hasGlyph(for: ".") } ?? faces[0]
                    let size = image.size
                    let baseline = image.baseline * scaleFactor
                    let height = size.height * scaleFactor
                    let width = size.width * scaleFactor

                    var glyph = Glyph(scalar: UnicodeScalar(0), face: face)
                    var frame: CGRect = .zero
                    if let texture = image.texture {
                        frame = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
                    }
                    glyph.content = .attachment(.init(texture: image.texture,
                                                       frame: frame,
                                                       offset: CGPoint(x: 0, y: baseline)))
                    glyph.ascender = baseline
                    glyph.descender = min(0, baseline - height)
                    glyph.advance.width = width
                    glyph.advance.height = height
                    glyph.attributes = attributes
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
        if rect.isEmpty || rect.isNull { return }
        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }
        let drawing = text.makeDrawing(in: rect.size)
        draw(drawing, in: rect, shading: shading)
    }

    func draw(
        _ drawing: ResolvedText.Drawing,
        in rect: CGRect,
        shading: Shading,
        snapOrigin: Bool = true
    ) {
        var rect = rect.standardized
        if rect.isEmpty { return }
        if rect.isNull { return }

        if shading.properties.isEmpty {
            fatalError("Invalid shading property!")
        }
        if drawing.isEmpty { return }

        var scissorRect: ScissorRect? = nil
        let clipBounds = true
        if snapOrigin || clipBounds {
            let transform = self.transform
                .concatenating(CGAffineTransform(
                    translationX: self.contentOffset.x,
                    y: self.contentOffset.y))
                .concatenating(CGAffineTransform(
                    scaleX: self.contentScaleFactor,
                    y: self.contentScaleFactor))

            if snapOrigin {
                var origin = rect.origin.applying(transform)
                origin.x.round()
                origin.y.round()
                rect.origin = origin.applying(transform.inverted())
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
        let offset = rect.origin
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)

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
            let runShading = foregroundColor.map(Shading.color) ?? shading
            self.encodeShadingBoxCommand(renderPass: renderPass,
                                         shading: runShading,
                                         stencil: .ignore,
                                         blendState: .multiply)
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
        self.recordContentBounds(rect)
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
        ResolvedText.forEachGlyph(in: lineGlyphs, callback: callback)
    }

    func encodeDrawTextCommand(renderPass: RenderPass,
                               drawing: ResolvedText.Drawing,
                               transform: CGAffineTransform,
                               color: VVD.Color,
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
