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

            func applying(foregroundColor: Color?) -> Run {
                guard let foregroundColor else { return self }
                switch self {
                case let .text(faces, text):
                    return .styledText(
                        faces,
                        text,
                        _TextAttributeValues(),
                        _ResolvedTextRunAttributes(foregroundColor: foregroundColor)
                    )
                case let .attributedText(faces, text, attributes):
                    return .styledText(
                        faces,
                        text,
                        attributes,
                        _ResolvedTextRunAttributes(foregroundColor: foregroundColor)
                    )
                case let .styledText(faces, text, attributes, existing):
                    guard existing.foregroundColor == nil else { return self }
                    var style = existing
                    style.foregroundColor = foregroundColor
                    return .styledText(faces, text, attributes, style)
                case .attachment, .attributedAttachment:
                    return self
                }
            }

            func applying(textModifiers: [Text.Modifier]) -> Run {
                let faces: [Typeface]
                let text: String
                let attributes: _TextAttributeValues
                var style: _ResolvedTextRunAttributes
                let hadStyle: Bool

                switch self {
                case let .text(runFaces, runText):
                    faces = runFaces
                    text = runText
                    attributes = _TextAttributeValues()
                    style = _ResolvedTextRunAttributes()
                    hadStyle = false
                case let .attributedText(runFaces, runText, runAttributes):
                    faces = runFaces
                    text = runText
                    attributes = runAttributes
                    style = _ResolvedTextRunAttributes()
                    hadStyle = false
                case let .styledText(
                    runFaces,
                    runText,
                    runAttributes,
                    runStyle
                ):
                    faces = runFaces
                    text = runText
                    attributes = runAttributes
                    style = runStyle
                    hadStyle = true
                case .attachment, .attributedAttachment:
                    return self
                }

                if style.tracking == nil {
                    for modifier in textModifiers {
                        if case let .tracking(value) = modifier {
                            style.tracking = value
                            break
                        }
                    }
                }
                if style.tracking == nil, style.kern == nil {
                    for modifier in textModifiers {
                        if case let .kerning(value) = modifier {
                            style.kern = value
                            break
                        }
                    }
                }
                var resolvedBaseline = style.baselineOffset != nil
                var resolvedUnderline = style.underlineStyle != nil
                var resolvedStrikethrough = style.strikethroughStyle != nil

                for modifier in textModifiers {
                    switch modifier {
                    case let .baseline(value) where !resolvedBaseline:
                        style.baselineOffset = value
                        resolvedBaseline = true
                    case let .anyTextModifier(value):
                        if !resolvedUnderline,
                           let value = value as? UnderlineTextModifier {
                            resolvedUnderline = true
                            if let lineStyle = value.lineStyle {
                                style.underlineStyle = lineStyle
                            }
                        } else if !resolvedStrikethrough,
                                  let value =
                                    value as? StrikethroughTextModifier {
                            resolvedStrikethrough = true
                            if let lineStyle = value.lineStyle {
                                style.strikethroughStyle = lineStyle
                            }
                        }
                    default:
                        break
                    }
                }

                guard hadStyle || !style.isEmpty else {
                    return self
                }
                return .styledText(faces, text, attributes, style)
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
            let displayScale: CGFloat
            let drawMissingGlyphs: Bool

            init(
                runs: [Run],
                scaleFactor: CGFloat,
                displayScale: CGFloat,
                drawMissingGlyphs: Bool
            ) {
                self.state = Mutex(State(runs: runs))
                self.scaleFactor = scaleFactor
                self.displayScale = displayScale
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

        init(
            runs: [Run],
            scaleFactor: CGFloat,
            displayScale: CGFloat? = nil,
            drawMissingGlyphs: Bool = false
        ) {
            let displayScale = displayScale ?? scaleFactor
            precondition(
                scaleFactor.isFinite && scaleFactor > 0 &&
                    displayScale.isFinite && displayScale > 0,
                "Resolved text scales must be positive and finite."
            )
            self.storage = Storage(
                runs: runs,
                scaleFactor: scaleFactor,
                displayScale: displayScale,
                drawMissingGlyphs: drawMissingGlyphs
            )
        }

        var runs: [Run] { storage.runs }
        var scaleFactor: CGFloat { storage.scaleFactor }
        var displayScale: CGFloat { storage.displayScale }
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

        struct LayoutMetrics: Equatable, Sendable {
            var size: CGSize
            var firstBaseline: CGFloat
            var lastBaseline: CGFloat
        }

        private static func pixelLimit(_ value: CGFloat) -> Int {
            if value > CGFloat(Int.max) {
                return .max
            }
            return Int(ceil(max(value, 0)))
        }

        private func alignedWidth(_ width: CGFloat) -> CGFloat {
            ceil(max(width, 0) * displayScale) / displayScale
        }

        func layoutMetrics(
            in size: CGSize,
            layoutProperties: TextLayoutProperties? = nil
        ) -> LayoutMetrics {
            let width = max(size.width, 0) * scaleFactor
            let height = max(size.height, 0) * scaleFactor
            let maxWidth = Self.pixelLimit(width)
            let maxHeight = height > CGFloat(Int.max) ? Int.max : Int(height)
            let lineGlyphs = makeGlyphs(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                lineLimit: layoutProperties?.lineLimit,
                truncationMode: layoutProperties?.truncationMode ?? .tail
            )
            let pixelSize = lineGlyphs.reduce(CGSize.zero) { result, line in
                CGSize(
                    width: max(result.width, line.width),
                    height: result.height + line.height
                )
            }
            let firstBaseline = lineGlyphs.first?.ascender ?? .zero
            let lastBaseline: CGFloat
            if let last = lineGlyphs.last {
                lastBaseline = lineGlyphs.dropLast().reduce(CGFloat.zero) {
                    $0 + $1.height
                } + last.ascender
            } else {
                lastBaseline = .zero
            }
            let inverseScale = 1 / scaleFactor
            var logicalSize = pixelSize * inverseScale
            logicalSize.width = alignedWidth(logicalSize.width)
            return LayoutMetrics(
                size: logicalSize,
                firstBaseline: firstBaseline * inverseScale,
                lastBaseline: lastBaseline * inverseScale
            )
        }

        public var shading: Shading = .foreground

        public func measure(in size: CGSize) -> CGSize {
            layoutMetrics(in: size).size
        }

        public func measure(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> CGSize {
            var width: Int = .max
            var height: Int = .max
            if let w = maxWidth, w < CGFloat(width) {
                width = Self.pixelLimit(w * self.scaleFactor)
            }
            if let h = maxHeight, h < CGFloat(height) {
                height = Int(h * self.scaleFactor)
            }
            let scale = 1.0 / self.scaleFactor
            var size = self.sizeInPixel(
                maxWidth: width,
                maxHeight: height
            ) * scale
            size.width = alignedWidth(size.width)
            return size
        }

        public func firstBaseline(in size: CGSize) -> CGFloat {
            layoutMetrics(in: size).firstBaseline
        }

        public func lastBaseline(in size: CGSize) -> CGFloat {
            layoutMetrics(in: size).lastBaseline
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
                case unresolved
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
            var style = _ResolvedTextRunAttributes()
            var baselineOffset: CGFloat = .zero
            var foregroundColor: Color?
            var characterIndex: Int = 0
            var isTruncationToken: Bool = false

            var lineAscender: CGFloat {
                ascender + max(baselineOffset, 0)
            }

            var lineDescender: CGFloat {
                descender + min(baselineOffset, 0)
            }

            var contentOffset: CGPoint {
                switch content {
                case .texture(let data):
                    return data.offset
                case .attachment(let data):
                    return data.offset
                case .unresolved, .vector, .missing:
                    return .zero
                }
            }
        }

        struct LineGlyphs {
            var glyphs: [Glyph]
            var ascender: CGFloat
            var descender: CGFloat
            var width: CGFloat
            var trailingBoundary: Glyph? = nil
            var paragraphIndex: Int = 0
            var isTruncated: Bool = false
            var height: CGFloat { ascender - descender }
        }

        struct GlyphAtom {
            var scalar: UnicodeScalar
            var bounds: CGRect
        }

        func glyphAtoms(
            in size: CGSize,
            layoutProperties: TextLayoutProperties? = nil
        ) -> [GlyphAtom] {
            let width = max(size.width, 0) * scaleFactor
            let height = max(size.height, 0) * scaleFactor
            let maxWidth = Self.pixelLimit(width)
            let maxHeight = height > CGFloat(Int.max) ? Int.max : Int(height)
            let lines = makeGlyphs(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                lineLimit: layoutProperties?.lineLimit,
                truncationMode: layoutProperties?.truncationMode ?? .tail
            )
            let scale = 1 / scaleFactor
            var atoms: [GlyphAtom] = []
            var lineOriginY: CGFloat = 0

            for line in lines {
                let fallbackAdvance = line.width > 0 || line.glyphs.isEmpty
                    ? CGFloat.zero
                    : width / CGFloat(line.glyphs.count)
                var glyphOriginX: CGFloat = 0
                for (index, glyph) in line.glyphs.enumerated() {
                    let advance = glyph.advance.width > 0
                        ? glyph.advance.width
                        : fallbackAdvance
                    if index != 0 {
                        glyphOriginX += glyph.kerning.x
                    }
                    atoms.append(GlyphAtom(
                        scalar: glyph.scalar,
                        bounds: CGRect(
                            x: glyphOriginX * scale,
                            y: lineOriginY * scale,
                            width: advance * scale,
                            height: line.height * scale
                        )
                    ))
                    glyphOriginX += advance
                }
                lineOriginY += line.height
            }
            return atoms
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

            struct Background {
                var frame: CGRect
                var color: Color
            }

            struct Decoration {
                var start: CGPoint
                var end: CGPoint
                var lineWidth: CGFloat
                var lineStyle: Text.LineStyle
                var foregroundColor: Color?

                func dashPattern(lineWidth: CGFloat) -> [CGFloat] {
                    switch lineStyle.pattern {
                    case .dot:
                        [lineWidth * 3, lineWidth * 3]
                    case .dash:
                        [lineWidth * 10, lineWidth * 5]
                    case .dashDot:
                        [
                            lineWidth * 10,
                            lineWidth * 3,
                            lineWidth * 3,
                            lineWidth * 3,
                        ]
                    case .dashDotDot:
                        [
                            lineWidth * 10,
                            lineWidth * 3,
                            lineWidth * 3,
                            lineWidth * 3,
                            lineWidth * 3,
                            lineWidth * 3,
                        ]
                    default:
                        []
                    }
                }
            }

            fileprivate var source: ResolvedText
            fileprivate var lineGlyphs: [LineGlyphs]
            fileprivate var batches: [Batch]
            fileprivate var attachments: [Attachment]
            var backgrounds: [Background]
            var decorations: [Decoration]

            fileprivate init(
                source: ResolvedText,
                lineGlyphs: [LineGlyphs],
                batches: [Batch],
                attachments: [Attachment],
                backgrounds: [Background],
                decorations: [Decoration]
            ) {
                self.source = source
                self.lineGlyphs = lineGlyphs
                self.batches = batches
                self.attachments = attachments
                self.backgrounds = backgrounds
                self.decorations = decorations
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

                for char2 in unicodeScalars {
                    let supportedFace = faces.first {
                        $0.hasGlyph(for: char2)
                    }
                    let makeMissingGlyph = drawMissingGlyphs &&
                        !char2.properties.isDefaultIgnorableCodePoint
                    let face2 = supportedFace ?? (
                        makeMissingGlyph ? faces[faces.count - 1] : faces[0]
                    )
                    let makeGlyph = supportedFace != nil || makeMissingGlyph

                    var glyph = Glyph(scalar: char2, face: face2)
                    if makeGlyph, let metrics = face2.glyphMetrics(for: char2) {
                        glyph.content = .unresolved
                        glyph.advance = metrics.advance
                        glyph.ascender = metrics.ascender
                        glyph.descender = metrics.descender
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

        func makeGlyphs(
            maxWidth: Int = .max,
            maxHeight: Int = .max,
            lineLimit: Int? = nil,
            truncationMode: Text.TruncationMode = .tail
        ) -> [LineGlyphs] {
            let lineGlyphs = storage.lineGlyphs { runs in
                Self._makeGlyphs(
                    runs: runs,
                    scaleFactor: self.scaleFactor,
                    drawMissingGlyphs: self.drawMissingGlyphs
                )
            }

            return _lineWrap(
                lineGlyphs,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                lineLimit: lineLimit,
                truncationMode: truncationMode
            )
        }

        func prepareResources() {
            for line in makeGlyphs() {
                for glyph in line.glyphs {
                    guard case .unresolved = glyph.content else { continue }
                    _ = glyph.face.glyph(for: glyph.scalar)
                }
            }
        }

        func makeDrawing(
            in size: CGSize,
            layoutProperties: TextLayoutProperties? = nil
        ) -> Drawing {
            let width = max(size.width, 0) * scaleFactor
            let height = max(size.height, 0) * scaleFactor
            let maxWidth = Self.pixelLimit(width)
            let maxHeight = height > CGFloat(Int.max) ? Int.max : Int(height)
            let lineGlyphs = makeGlyphs(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                lineLimit: layoutProperties?.lineLimit,
                truncationMode: layoutProperties?.truncationMode ?? .tail
            )
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
            var backgrounds: [Drawing.Background] = []
            var decorations: [Drawing.Decoration] = []

            func appendTexture(
                texture: Texture?,
                frame textureBounds: CGRect,
                offset: CGPoint,
                baseline: CGPoint,
                foregroundColor: Color?
            ) {
                guard let texture else { return }
                let colorGlyphs: Bool
                switch texture.pixelFormat {
                case .r8Unorm:
                    colorGlyphs = false
                case .bgra8Unorm, .bgra8Unorm_srgb:
                    colorGlyphs = true
                default:
                    assertionFailure(
                        "Unsupported glyph texture format: \(texture.pixelFormat)"
                    )
                    return
                }

                let invW = 1.0 / Float(texture.width)
                let invH = 1.0 / Float(texture.height)
                let pad: CGFloat = 1
                let textureFrame = textureBounds.insetBy(dx: -pad, dy: -pad)
                let frame = CGRect(
                    x: baseline.x,
                    y: baseline.y - offset.y,
                    width: textureBounds.width,
                    height: textureBounds.height
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
                    foregroundColor: foregroundColor
                ))
            }

            Self.forEachGlyph(in: lineGlyphs) { glyph, baseline in
                switch glyph.content {
                case .unresolved:
                    guard glyph.scalar != UnicodeScalar(0),
                          case let .texture(data) = glyph.face.glyph(
                            for: glyph.scalar
                          ) else {
                        return
                    }
                    appendTexture(
                        texture: data.texture,
                        frame: data.frame,
                        offset: data.offset,
                        baseline: CGPoint(
                            x: baseline.x + data.offset.x,
                            y: baseline.y
                        ),
                        foregroundColor: glyph.foregroundColor
                    )

                case let .texture(data):
                    guard glyph.scalar != UnicodeScalar(0) else { return }
                    appendTexture(
                        texture: data.texture,
                        frame: data.frame,
                        offset: data.offset,
                        baseline: baseline,
                        foregroundColor: glyph.foregroundColor
                    )

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

            func appendBackground(_ frame: CGRect, color: Color) {
                if let index = backgrounds.indices.last,
                   backgrounds[index].color == color,
                   abs(backgrounds[index].frame.maxX - frame.minX) <
                    .ulpOfOne,
                   abs(backgrounds[index].frame.minY - frame.minY) <
                    .ulpOfOne,
                   abs(backgrounds[index].frame.height - frame.height) <
                    .ulpOfOne {
                    backgrounds[index].frame.size.width =
                        frame.maxX - backgrounds[index].frame.minX
                } else {
                    backgrounds.append(Drawing.Background(
                        frame: frame,
                        color: color
                    ))
                }
            }

            func appendDecoration(
                start: CGPoint,
                end: CGPoint,
                lineWidth: CGFloat,
                lineStyle: Text.LineStyle,
                foregroundColor: Color?
            ) {
                if let index = decorations.lastIndex(where: {
                    $0.lineStyle == lineStyle &&
                        $0.foregroundColor == foregroundColor &&
                        abs($0.lineWidth - lineWidth) < .ulpOfOne &&
                        abs($0.end.x - start.x) < .ulpOfOne &&
                        abs($0.end.y - start.y) < .ulpOfOne
                }) {
                    decorations[index].end = end
                } else {
                    decorations.append(Drawing.Decoration(
                        start: start,
                        end: end,
                        lineWidth: lineWidth,
                        lineStyle: lineStyle,
                        foregroundColor: foregroundColor
                    ))
                }
            }

            var lineOriginY: CGFloat = 0
            for line in lineGlyphs {
                var cellOriginX: CGFloat = 0
                for (index, glyph) in line.glyphs.enumerated() {
                    let kerning = index == 0 ? 0 : glyph.kerning.x
                    let cellWidth = kerning + glyph.advance.width
                    let baseline = CGPoint(
                        x: cellOriginX + kerning,
                        y: lineOriginY + line.ascender -
                            glyph.baselineOffset
                    )

                    if let color = glyph.style.backgroundColor {
                        appendBackground(
                            CGRect(
                                x: cellOriginX,
                                y: baseline.y - glyph.ascender,
                                width: cellWidth,
                                height: glyph.ascender - glyph.descender
                            ),
                            color: color
                        )
                    }

                    if let metrics = glyph.face.decorationMetrics {
                        let rawLogicalWidth =
                            metrics.underlineThickness / scaleFactor
                        let logicalWidth = ceil(
                            rawLogicalWidth * displayScale
                        ) / displayScale
                        let lineWidth = logicalWidth * scaleFactor
                        let endX = cellOriginX + cellWidth
                        if let lineStyle = glyph.style.underlineStyle {
                            let y = baseline.y -
                                metrics.underlinePosition
                            appendDecoration(
                                start: CGPoint(x: cellOriginX, y: y),
                                end: CGPoint(x: endX, y: y),
                                lineWidth: lineWidth,
                                lineStyle: lineStyle,
                                foregroundColor:
                                    lineStyle.color ??
                                    glyph.foregroundColor
                            )
                        }
                        if let lineStyle =
                            glyph.style.strikethroughStyle,
                           let xHeight = metrics.xHeight {
                            let y = baseline.y - xHeight * 0.5
                            appendDecoration(
                                start: CGPoint(x: cellOriginX, y: y),
                                end: CGPoint(x: endX, y: y),
                                lineWidth: lineWidth,
                                lineStyle: lineStyle,
                                foregroundColor:
                                    lineStyle.color ??
                                    glyph.foregroundColor
                            )
                        }
                    }
                    cellOriginX += cellWidth
                }
                lineOriginY += line.height
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
                attachments: attachments,
                backgrounds: backgrounds,
                decorations: decorations
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
                    let kerning: CGPoint = offset.x > 0
                        ? glyph.kerning
                        : .zero
                    offset += kerning
                    let baseline = CGPoint(
                        x: glyph.contentOffset.x + offset.x,
                        y: line.ascender + offset.y - glyph.baselineOffset
                    )
                    callback(glyph, baseline)
                    offset.x += glyph.advance.width
                }
                offset.y += line.height
            }
        }

        private func _lineWrap(
            _ lines: [LineGlyphs],
            maxWidth: Int,
            maxHeight: Int,
            lineLimit: Int?,
            truncationMode: Text.TruncationMode
        ) -> [LineGlyphs] {
            let breakables = CharacterSet.whitespaces.union(.init(charactersIn: "-/?!}|"))
            let decimalNumbers = CharacterSet.decimalDigits
            // No wrap if character is followed by a decimal number
            let breakableNotBeforeDN = CharacterSet(charactersIn: "-")
            // No wrap if character is between decimal numbers
            let breakableNotBetweenDN = CharacterSet(charactersIn: "/")

            let getGlyphsWidth = { (glyphs: [Glyph]) -> CGFloat in
                glyphs.reduce(CGFloat.zero) { result, glyph in
                    result + glyph.advance.width + glyph.kerning.x
                } - (glyphs.first?.kerning.x ?? 0) // ignore first kerning
            }
            // Returns the index of the character that matches the wrapable character condition.
            let getBreakableIndex = { (glyphs: [Glyph]) -> Int? in
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
                (glyphs: [Glyph], maxWidth: Int) -> (first: [Glyph], second: [Glyph]) in
                var first = glyphs
                var second: [Glyph] = []
                while first.count > 1 && Int(ceil(getGlyphsWidth(first))) > maxWidth {
                    if let index = getBreakableIndex(first),
                       first.index(after: index) != first.endIndex {
                        let index2 = first.index(after: index)
                        second.insert(
                            contentsOf: first[index2...],
                            at: second.startIndex
                        )
                        first.removeSubrange(index2...)
                    } else {
                        if let s2 = first.popLast() {
                            second.insert(s2, at: second.startIndex)
                        }
                    }
                }
                return (first: first, second: second)
            }

            func updateMetrics(_ line: inout LineGlyphs) {
                guard !line.glyphs.isEmpty else { return }
                line.glyphs[0].kerning = .zero
                line.ascender = line.glyphs.reduce(.zero) {
                    max($0, $1.lineAscender)
                }
                line.descender = line.glyphs.reduce(.zero) {
                    min($0, $1.lineDescender)
                }
                line.width = getGlyphsWidth(line.glyphs)
            }

            var wrappedLines: [LineGlyphs] = []
            for sourceLine in lines {
                var line = sourceLine
                while line.glyphs.count > 1,
                      Int(ceil(line.width)) > maxWidth {
                    let split = splitLineGlyphs(line.glyphs, maxWidth)
                    guard !split.second.isEmpty else { break }

                    var first = line
                    first.glyphs = split.first
                    first.trailingBoundary = nil
                    updateMetrics(&first)
                    wrappedLines.append(first)

                    line.glyphs = split.second
                    updateMetrics(&line)
                }
                wrappedLines.append(line)
            }

            var visibleLines: [LineGlyphs] = []
            var visibleHeight: CGFloat = 0
            let maximumLineCount = lineLimit.map { max($0, 1) }
            var nextLineIndex = 0
            while nextLineIndex < wrappedLines.count {
                if let maximumLineCount,
                   visibleLines.count >= maximumLineCount {
                    break
                }
                let line = wrappedLines[nextLineIndex]
                if !visibleLines.isEmpty,
                   Int(ceil(visibleHeight + line.height)) > maxHeight {
                    break
                }
                visibleLines.append(line)
                visibleHeight += line.height
                nextLineIndex += 1
            }

            guard let lastVisibleIndex = visibleLines.indices.last else {
                return []
            }

            let lastParagraph = visibleLines[lastVisibleIndex].paragraphIndex
            var paragraphGlyphs = visibleLines[lastVisibleIndex].glyphs
            var continuationIndex = nextLineIndex
            while continuationIndex < wrappedLines.count,
                  wrappedLines[continuationIndex].paragraphIndex ==
                    lastParagraph {
                paragraphGlyphs.append(
                    contentsOf: wrappedLines[continuationIndex].glyphs
                )
                continuationIndex += 1
            }

            let hasParagraphOverflow =
                paragraphGlyphs.count >
                    visibleLines[lastVisibleIndex].glyphs.count ||
                Int(ceil(visibleLines[lastVisibleIndex].width)) > maxWidth
            let hasExplicitLineOverflow =
                !hasParagraphOverflow &&
                nextLineIndex < wrappedLines.count &&
                visibleLines[lastVisibleIndex].trailingBoundary != nil

            guard hasParagraphOverflow || hasExplicitLineOverflow else {
                return visibleLines
            }

            func adjacencyKerning(
                from lhs: Glyph?,
                to rhs: Glyph
            ) -> CGPoint {
                guard let lhs, lhs.face.isEqual(to: rhs.face) else {
                    return .zero
                }
                return lhs.face.kernAdvance(
                    left: lhs.scalar,
                    right: rhs.scalar
                )
            }

            func makeEllipsis(
                inheriting source: Glyph,
                characterIndex: Int,
                after previous: Glyph?
            ) -> Glyph? {
                let generated = TextGlyphs.from(
                    unicodeScalars: "…".unicodeScalars,
                    with: [source.face],
                    drawMissingGlyphs: false,
                    prevFace: previous?.face,
                    prevChar: previous?.scalar ?? UnicodeScalar(UInt8(0))
                )
                guard var glyph = generated.glyphs.first else {
                    return nil
                }
                glyph.attributes = source.attributes
                glyph.style = source.style
                glyph.baselineOffset = source.baselineOffset
                glyph.foregroundColor = source.foregroundColor
                glyph.characterIndex = characterIndex
                glyph.isTruncationToken = true
                glyph.advance.width += (
                    source.style.tracking ??
                    source.style.kern ??
                    0
                ) * scaleFactor
                if previous == nil {
                    glyph.kerning = .zero
                }
                return glyph
            }

            func tailTruncation(
                _ glyphs: [Glyph],
                explicitBoundary: Glyph?
            ) -> [Glyph]? {
                if let explicitBoundary,
                   let source = glyphs.last {
                    var prefix = glyphs
                    while true {
                        guard let ellipsis = makeEllipsis(
                            inheriting: source,
                            characterIndex: explicitBoundary.characterIndex,
                            after: prefix.last
                        ) else {
                            return nil
                        }
                        var candidate = prefix + [ellipsis]
                        if !candidate.isEmpty {
                            candidate[0].kerning = .zero
                        }
                        if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                            return candidate
                        }
                        guard !prefix.isEmpty else { return nil }
                        prefix.removeLast()
                    }
                }

                guard glyphs.count > 1 else { return nil }
                for prefixCount in stride(
                    from: glyphs.count - 1,
                    through: 0,
                    by: -1
                ) {
                    let source = glyphs[prefixCount]
                    var prefix = Array(glyphs[..<prefixCount])
                    let previous = prefix.last
                    guard let ellipsis = makeEllipsis(
                        inheriting: source,
                        characterIndex: source.characterIndex,
                        after: previous
                    ) else {
                        return nil
                    }
                    prefix.append(ellipsis)
                    prefix[0].kerning = .zero
                    if Int(ceil(getGlyphsWidth(prefix))) <= maxWidth {
                        return prefix
                    }
                }
                return nil
            }

            func headTruncation(_ glyphs: [Glyph]) -> [Glyph]? {
                guard glyphs.count > 1,
                      let source = glyphs.first,
                      let ellipsis = makeEllipsis(
                        inheriting: source,
                        characterIndex: source.characterIndex,
                        after: nil
                      ) else {
                    return nil
                }
                for suffixCount in stride(
                    from: glyphs.count - 1,
                    through: 0,
                    by: -1
                ) {
                    var suffix = Array(glyphs.suffix(suffixCount))
                    if !suffix.isEmpty {
                        suffix[0].kerning = adjacencyKerning(
                            from: ellipsis,
                            to: suffix[0]
                        )
                    }
                    let candidate = [ellipsis] + suffix
                    if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                        return candidate
                    }
                }
                return nil
            }

            func middleTruncation(_ glyphs: [Glyph]) -> [Glyph]? {
                guard glyphs.count > 1 else { return nil }

                var selectedPrefixCount = 0
                var selectedEllipsis: Glyph?
                for prefixCount in 0..<glyphs.count {
                    let source = glyphs[prefixCount]
                    let prefix = Array(glyphs[..<prefixCount])
                    guard let ellipsis = makeEllipsis(
                        inheriting: source,
                        characterIndex: source.characterIndex,
                        after: prefix.last
                    ) else {
                        return nil
                    }
                    let retainedWidth = CGFloat(maxWidth) -
                        getGlyphsWidth([ellipsis])
                    guard retainedWidth >= 0 else { return nil }
                    if getGlyphsWidth(prefix) <= retainedWidth * 0.5 {
                        selectedPrefixCount = prefixCount
                        selectedEllipsis = ellipsis
                    } else {
                        break
                    }
                }

                guard selectedPrefixCount > 0,
                      let ellipsis = selectedEllipsis else {
                    guard let source = glyphs.first,
                          let ellipsis = makeEllipsis(
                            inheriting: source,
                            characterIndex: source.characterIndex,
                            after: nil
                          ),
                          Int(ceil(getGlyphsWidth([ellipsis]))) <= maxWidth else {
                        return nil
                    }
                    return [ellipsis]
                }

                let maximumSuffixCount =
                    glyphs.count - selectedPrefixCount - 1
                let prefix = Array(glyphs[..<selectedPrefixCount])
                for suffixCount in stride(
                    from: maximumSuffixCount,
                    through: 0,
                    by: -1
                ) {
                    var suffix = Array(glyphs.suffix(suffixCount))
                    if !suffix.isEmpty {
                        suffix[0].kerning = adjacencyKerning(
                            from: ellipsis,
                            to: suffix[0]
                        )
                    }
                    var candidate = prefix + [ellipsis] + suffix
                    candidate[0].kerning = .zero
                    if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                        return candidate
                    }
                }
                return nil
            }

            let explicitBoundary = hasExplicitLineOverflow
                ? visibleLines[lastVisibleIndex].trailingBoundary
                : nil
            let truncatedGlyphs: [Glyph]?
            if explicitBoundary != nil, truncationMode != .tail {
                return visibleLines
            } else if explicitBoundary != nil {
                truncatedGlyphs = tailTruncation(
                    visibleLines[lastVisibleIndex].glyphs,
                    explicitBoundary: explicitBoundary
                )
            } else {
                switch truncationMode {
                case .head:
                    truncatedGlyphs = headTruncation(paragraphGlyphs)
                case .middle:
                    truncatedGlyphs = middleTruncation(paragraphGlyphs)
                case .tail:
                    truncatedGlyphs = tailTruncation(
                        paragraphGlyphs,
                        explicitBoundary: nil
                    )
                }
            }

            guard let truncatedGlyphs else {
                if hasParagraphOverflow {
                    visibleLines[lastVisibleIndex].glyphs = paragraphGlyphs
                    updateMetrics(&visibleLines[lastVisibleIndex])
                    if maxWidth != .max {
                        visibleLines[lastVisibleIndex].width =
                            CGFloat(maxWidth)
                    }
                }
                return visibleLines
            }
            visibleLines[lastVisibleIndex].glyphs = truncatedGlyphs
            visibleLines[lastVisibleIndex].trailingBoundary = nil
            visibleLines[lastVisibleIndex].isTruncated = hasParagraphOverflow
            updateMetrics(&visibleLines[lastVisibleIndex])
            return visibleLines
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
            var characterIndex = 0
            var paragraphIndex = 0

            let addLine = { (trailingBoundary: Glyph?) in
                lines.append(LineGlyphs(glyphs: glyphs,
                                        ascender: ascender,
                                        descender: descender,
                                        width: offset.x,
                                        trailingBoundary: trailingBoundary,
                                        paragraphIndex: paragraphIndex))
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

                        let resolvedStyle = style ??
                            _ResolvedTextRunAttributes()
                        let spacing = (
                            resolvedStyle.tracking ??
                            resolvedStyle.kern ??
                            0
                        ) * scaleFactor
                        let baselineOffset =
                            (resolvedStyle.baselineOffset ?? 0) * scaleFactor
                        let runGlyphs = textGlyphs.glyphs.map { glyph in
                            var glyph = glyph
                            glyph.attributes = attributes
                            glyph.style = resolvedStyle
                            glyph.baselineOffset = baselineOffset
                            glyph.foregroundColor =
                                resolvedStyle.foregroundColor
                            glyph.advance.width += spacing
                            return glyph
                        }
                        let runStartIndex = characterIndex
                        characterIndex += scalars.count
                        if runGlyphs.isEmpty {
                            ascender = max(
                                ascender,
                                textGlyphs.ascender + max(baselineOffset, 0)
                            )
                            descender = min(
                                descender,
                                textGlyphs.descender + min(baselineOffset, 0)
                            )
                        } else {
                            for (index, var glyph) in runGlyphs.enumerated() {
                                glyph.characterIndex = runStartIndex + index
                                if glyphs.isEmpty {
                                    glyph.kerning = .zero
                                }
                                let kerning = glyphs.isEmpty
                                    ? CGFloat.zero
                                    : glyph.kerning.x
                                glyphs.append(glyph)
                                offset.x += kerning + glyph.advance.width
                                ascender = max(
                                    ascender,
                                    glyph.lineAscender
                                )
                                descender = min(
                                    descender,
                                    glyph.lineDescender
                                )
                            }
                        }

                        if components.isEmpty {
                            // The last line can be combined with other text.
                            // Don't complete the line.
                            break
                        }

                        var boundary = glyphs.last ?? {
                            var glyph = Glyph(
                                scalar: UnicodeScalar("\n"),
                                face: faces[0]
                            )
                            glyph.ascender = textGlyphs.ascender
                            glyph.descender = textGlyphs.descender
                            glyph.attributes = attributes
                            glyph.style = resolvedStyle
                            glyph.baselineOffset = baselineOffset
                            glyph.foregroundColor =
                                resolvedStyle.foregroundColor
                            return glyph
                        }()
                        boundary.scalar = UnicodeScalar("\n")
                        boundary.content = .missing
                        boundary.advance = .zero
                        boundary.kerning = .zero
                        boundary.characterIndex = characterIndex
                        boundary.isTruncationToken = false
                        addLine(boundary)
                        characterIndex += 1
                        paragraphIndex += 1
                        face1 = nil
                        char1 = UnicodeScalar(0)
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
                    glyph.characterIndex = characterIndex
                    glyphs.append(glyph)
                    characterIndex += 1

                    offset.x += glyph.advance.width
                    ascender = max(ascender, glyph.lineAscender)
                    descender = min(descender, glyph.lineDescender)

                    face1 = nil
                    char1 = UnicodeScalar(0)
                }
            }
            if glyphs.isEmpty == false {
                let lineHeight = ascender - descender
                assert(lineHeight > 0)

                // Zero-advance scalars and suppressed missing glyphs still
                // form a line with valid vertical metrics.

                lines.append(LineGlyphs(glyphs: glyphs,
                                        ascender: ascender,
                                        descender: descender,
                                        width: offset.x,
                                        paragraphIndex: paragraphIndex))
            }
            return lines
        }
    }

    public func draw(_ text: ResolvedText, in rect: CGRect) {
        draw(text, in: rect, shading: text.shading)
    }

    func draw(
        _ text: ResolvedText,
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

        for background in drawing.backgrounds {
            self.fill(
                Path(background.frame.applying(transform)),
                with: .color(background.color)
            )
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
            let runShading = foregroundColor.map(Shading.color) ?? shading
            self.encodeShadingBoxCommand(renderPass: renderPass,
                                         shading: runShading,
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

        for decoration in drawing.decorations {
            let start = decoration.start.applying(transform)
            let end = decoration.end.applying(transform)
            let lineWidth = decoration.lineWidth * scale
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            self.stroke(
                path,
                with: decoration.foregroundColor.map(Shading.color) ??
                    shading,
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
