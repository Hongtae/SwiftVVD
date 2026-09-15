//
//  File: ResolvedTextSource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

struct ResolvedTextSource {
    var resolvedProperties: Text.ResolvedProperties?
    // Default metrics affect placement, not the cached source glyphs.
    var defaultLineMetrics: FontLineMetrics?
    // Backend font requests reuse the resolved cascade environment without
    // retaining a graph dependency tracker during measurement or replay.
    var fontResolutionContext: GraphTextResolutionContext?
    enum Run {
        case text([Typeface], String)
        case attachment([Typeface], ImageDrawing)
        case attributedText([Typeface], String, _TextAttributeValues)
        case attributedAttachment([Typeface], ImageDrawing, _TextAttributeValues)
        case styledText(
            [Typeface],
            String,
            _TextAttributeValues,
            _ResolvedTextRunAttributes
        )

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
        let outsetData: FontOutsetData?
        let outsetLanguageGroup: Int
        let hasOversizedScalars: Bool
        let preferredLanguages: [String]

        init(
            runs: [Run],
            scaleFactor: CGFloat,
            displayScale: CGFloat,
            drawMissingGlyphs: Bool,
            outsetData: FontOutsetData?,
            preferredLanguages: [String]
        ) {
            self.state = Mutex(State(runs: runs))
            self.scaleFactor = scaleFactor
            self.displayScale = displayScale
            self.drawMissingGlyphs = drawMissingGlyphs
            self.outsetData = outsetData
            self.preferredLanguages = preferredLanguages
            self.outsetLanguageGroup = outsetData?.preferredGroup(for: preferredLanguages) ?? 0
            self.hasOversizedScalars = outsetData.map { data in
                runs.contains { run in
                    switch run {
                    case let .text(_, text), let .attributedText(_, text, _), let .styledText(_, text, _, _):
                        text.unicodeScalars.contains(where: data.contains)
                    case .attachment, .attributedAttachment:
                        data.contains("\u{fffc}")
                    }
                }
            } ?? false
        }

        var runs: [Run] {
            var runs: [Run] = []
            state.withLock { state in
                runs = state.runs
            }
            return runs
        }

        var hasEmptyContent: Bool {
            state.withLock { !$0.terminated && $0.runs.isEmpty }
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
        drawMissingGlyphs: Bool = false,
        outsetData: FontOutsetData? = BundledFontCatalog.shared.outsetData,
        preferredLanguages: [String] = Locale.preferredLanguages
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
            drawMissingGlyphs: drawMissingGlyphs,
            outsetData: outsetData,
            preferredLanguages: preferredLanguages
        )
    }

    var runs: [Run] { storage.runs }
    var scaleFactor: CGFloat { storage.scaleFactor }
    var displayScale: CGFloat { storage.displayScale }
    var drawMissingGlyphs: Bool { storage.drawMissingGlyphs }

    var uniformFont: FontResource? {
        guard runs.count == 1,
              case let .styledText(_, text, _, attributes) = runs[0],
              !text.isEmpty,
              (attributes.baselineOffset ?? 0) == 0,
              (attributes.paragraphStyle?.firstLineHeadIndent ?? 0) == 0,
              (attributes.paragraphStyle?.lineSpacing ?? 0) == 0,
              attributes.paragraphStyle?.allowsTightening != true,
              let resource = attributes.fontResource,
              resource.requestedPointSize != nil else { return nil }
        return resource
    }

    var uniformString: String? {
        guard uniformFont != nil, case let .styledText(_, text, _, _) = runs[0] else { return nil }
        return text
    }

    func resizingUniformFont(to pointSize: CGFloat) -> Self? {
        guard let original = uniformFont, let context = fontResolutionContext,
              case let .styledText(_, text, custom, originalAttributes) = runs[0],
              let resized = original.fontWithSize(pointSize) else { return nil }
        if resized === original { return self }
        var attributes = originalAttributes
        attributes.fontResource = resized
        let font = Font(provider: FontBox(Font.PlatformFontProvider(font: resized)))
        attributes.font = font
        let faces = font.typefaceCascade(in: context.environment, forContext: context.sceneResources,
            contentScaleFactor: scaleFactor, applyEnvironmentModifiers: false).runFaces
        guard !faces.isEmpty else { return nil }
        var result = Self(runs: [.styledText(faces, text, custom, attributes)],
            scaleFactor: scaleFactor, displayScale: displayScale, drawMissingGlyphs: drawMissingGlyphs,
            outsetData: storage.outsetData, preferredLanguages: storage.preferredLanguages)
        result.defaultLineMetrics = defaultLineMetrics
        result.resolvedProperties = resolvedProperties
        result.fontResolutionContext = context
        result.shading = shading
        return result
    }

    /// Rebuilds font attributes from the original requests. Spacing,
    /// baseline offsets, attachments and custom attributes keep their units.
    func scalingFonts(by scale: CGFloat) -> Self {
        guard scale != 1 else { return self }
        let scaledRuns = runs.map { run -> Run in
            guard case let .styledText(_, text, custom, originalAttributes) = run,
                  let original = originalAttributes.fontResource else { return run }
            guard let resized = original.fontWithSize((original.pointSize * scale * 4).rounded() * 0.25) else {
                return run
            }
            guard let context = fontResolutionContext else {
                preconditionFailure("Scaling resolved font attributes requires their resolution context")
            }
            var attributes = originalAttributes
            attributes.fontResource = resized
            let font = Font(provider: FontBox(Font.PlatformFontProvider(font: resized)))
            attributes.font = font
            let faces = font.typefaceCascade(in: context.environment, forContext: context.sceneResources,
                contentScaleFactor: scaleFactor, applyEnvironmentModifiers: false).runFaces
            return .styledText(faces, text, custom, attributes)
        }
        var result = Self(runs: scaledRuns, scaleFactor: scaleFactor, displayScale: displayScale,
            drawMissingGlyphs: drawMissingGlyphs, outsetData: storage.outsetData,
            preferredLanguages: storage.preferredLanguages)
        result.defaultLineMetrics = defaultLineMetrics
        result.resolvedProperties = resolvedProperties
        result.fontResolutionContext = fontResolutionContext
        result.shading = shading
        return result
    }

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
        var features = resolvedProperties?.features ?? []
        if hasAttachments { features.insert(.attachments) }
        return features
    }

    var maximumFontMetrics: ResolvedFontMetrics? {
        var result: ResolvedFontMetrics?
        for run in runs {
            let faces: [Typeface]
            let resource: FontResource?
            switch run {
            case let .text(runFaces, _),
                 let .attachment(runFaces, _),
                 let .attributedText(runFaces, _, _),
                 let .attributedAttachment(runFaces, _, _):
                faces = runFaces
                resource = nil
            case let .styledText(runFaces, _, _, style):
                faces = runFaces
                resource = style.fontResource
            }
            guard let face = faces.first else { continue }
            var metrics = resource?.resolvedMetrics(for: face, scaleFactor: scaleFactor)
                ?? face.resolvedMetrics.scaled(by: scaleFactor)
            var outsetAttributes = face.outsetAttributes
            // A selected catalog trait can differ from the physical variation coordinate.
            if let weight = resource?.selectedWeight {
                outsetAttributes?.weight = weight
            }
            // One scalar decision applies to every attribute font in the complete text.
            if let attributes = outsetAttributes,
               storage.hasOversizedScalars || attributes.needsOutsets,
               let outsets = storage.outsetData?.outsets(
                   for: attributes,
                   pointSize: resource?.requestedPointSize ?? attributes.pointSize / scaleFactor,
                   preferredGroup: storage.outsetLanguageGroup) {
                // A successful tuple replaces clipping, including a zero tuple.
                metrics.outsets = resource?.adjustedOutsets(outsets) ?? outsets
            }
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

    private func alignedLength(_ value: CGFloat) -> CGFloat {
        ceil(max(value, 0) * displayScale) / displayScale
    }

    func layoutMetrics(
        in size: CGSize,
        layoutProperties: TextLayoutProperties? = nil
    ) -> LayoutMetrics {
        var metrics = unroundedLayoutMetrics(in: size, layoutProperties: layoutProperties)
        metrics.size.width = alignedLength(metrics.size.width)
        metrics.size.height = alignedLength(metrics.size.height)
        return metrics
    }

    func layoutMetrics(lineGlyphs: [LineGlyphs]) -> LayoutMetrics {
        var metrics = unroundedLayoutMetrics(lineGlyphs: lineGlyphs)
        metrics.size.width = alignedLength(metrics.size.width)
        metrics.size.height = alignedLength(metrics.size.height)
        return metrics
    }

    func unroundedLayoutMetrics(
        in size: CGSize,
        layoutProperties: TextLayoutProperties? = nil
    ) -> LayoutMetrics {
        let width = max(size.width, 0) * scaleFactor
        let height = max(size.height, 0) * scaleFactor
        let maxWidth = Self.pixelLimit(width)
        let lineGlyphs = makeGlyphs(
            maxWidth: maxWidth,
            maximumHeight: height,
            lineLimit: layoutProperties?.lineLimit,
            truncationMode: layoutProperties?.truncationMode ?? .tail
        )
        return unroundedLayoutMetrics(lineGlyphs: lineGlyphs)
    }

    // The measurement owner applies margins before aligning baselines.
    func unroundedLayoutMetrics(lineGlyphs: [LineGlyphs]) -> LayoutMetrics {
        if lineGlyphs.isEmpty, storage.hasEmptyContent, let input = defaultLineMetrics {
            return LayoutMetrics(size: CGSize(width: 0, height: input.height / scaleFactor),
                firstBaseline: input.ascent / scaleFactor, lastBaseline: input.ascent / scaleFactor)
        }
        let pixelSize = lineGlyphs.reduce(CGSize.zero) { result, line in
            CGSize(
                width: max(result.width, line.width),
                height: max(result.height, line.maxY)
            )
        }
        let firstBaseline = lineGlyphs.first?.baseline ?? .zero
        let lastBaseline = lineGlyphs.last?.baseline ?? .zero
        let inverseScale = 1 / scaleFactor
        return LayoutMetrics(
            size: pixelSize * inverseScale,
            firstBaseline: firstBaseline * inverseScale,
            lastBaseline: lastBaseline * inverseScale
        )
    }

    var shading: GraphicsContext.Shading = .foreground

    func measure(in size: CGSize) -> CGSize {
        layoutMetrics(in: size).size
    }

    func measure(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> CGSize {
        layoutMetrics(in: CGSize(width: maxWidth ?? .infinity,
                                 height: maxHeight ?? .infinity)).size
    }

    func firstBaseline(in size: CGSize) -> CGFloat {
        layoutMetrics(in: size).firstBaseline
    }

    func lastBaseline(in size: CGSize) -> CGFloat {
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
        var glyphIndex: UInt32?
        var sourceRange: Range<Int>?
        var content: Content = .missing
        var advance: CGSize = .zero     // distance to next glyph
        var positionOffset: CGPoint = .zero
        // The selected face owns glyph/run metrics and artwork.
        var ascender: CGFloat = .zero
        var descender: CGFloat = .zero
        var leading: CGFloat = .zero
        // The explicit run's primary face owns line measurement.
        var lineBoxAscender: CGFloat = .zero
        var lineBoxDescender: CGFloat = .zero
        var fontLineMetrics: FontLineMetrics?
        var kerning: CGPoint = .zero    // kern advance from previous glyph.
        var attributes = _TextAttributeValues()
        var style = _ResolvedTextRunAttributes()
        var baselineOffset: CGFloat = .zero
        var foregroundColor: Color?
        var characterIndex: Int = 0
        var isTruncationToken: Bool = false

        init(scalar: UnicodeScalar, face: Typeface) {
            self.scalar = scalar
            self.face = face
            self.lineBoxAscender = face.ascender
            self.lineBoxDescender = face.descender
        }

        var lineAscender: CGFloat {
            lineBoxAscender + max(baselineOffset, 0)
        }

        var lineDescender: CGFloat {
            lineBoxDescender + min(baselineOffset, 0)
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

    static func sameCluster(_ lhs: Glyph, _ rhs: Glyph) -> Bool {
        guard let lhsRange = lhs.sourceRange,
              let rhsRange = rhs.sourceRange else {
            return false
        }
        return lhsRange == rhsRange &&
            lhs.isTruncationToken == rhs.isTruncationToken &&
            lhs.attributes == rhs.attributes &&
            lhs.style == rhs.style &&
            lhs.face.isEqual(to: rhs.face)
    }

    static func clusterRanges(in glyphs: [Glyph]) -> [Range<Int>] {
        guard !glyphs.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var lowerBound = glyphs.startIndex
        for index in glyphs.indices.dropFirst() where
            !sameCluster(glyphs[index - 1], glyphs[index]) {
            ranges.append(lowerBound..<index)
            lowerBound = index
        }
        ranges.append(lowerBound..<glyphs.endIndex)
        return ranges
    }

    struct LineGlyphs {
        enum Kind {
            case content
            case extra(Glyph?)
        }

        var glyphs: [Glyph]
        var ascender: CGFloat
        var descender: CGFloat
        var width: CGFloat
        var trailingBoundary: Glyph? = nil
        var paragraphIndex: Int = 0
        var paragraphInput: Glyph? = nil
        var kind: Kind = .content
        var isSimpleParagraph: Bool = false
        var isTruncated: Bool = false
        var forcedClusterBreak: Bool = false
        // Placement is resolved after wrapping and shared by all consumers.
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        var spacing: CGFloat = 0
        var paragraphStartSpacing: CGFloat = 0
        var isParagraphEnd: Bool = true
        var height: CGFloat { ascender - descender }
        var baseline: CGFloat { originY + ascender }
        var maxY: CGFloat { originY + height }
    }

    struct GlyphLayout {
        var lines: [LineGlyphs]
        var lineCount: Int
        var forcedClusterBreak: Bool
        var truncatedRanges: [Range<Int>]
    }

    struct GlyphAtom {
        var scalar: UnicodeScalar
        var sourceRange: Range<Int>
        var bounds: CGRect
    }

    func glyphAtoms(
        in size: CGSize,
        layoutProperties: TextLayoutProperties? = nil
    ) -> [GlyphAtom] {
        let width = max(size.width, 0) * scaleFactor
        let height = max(size.height, 0) * scaleFactor
        let maxWidth = Self.pixelLimit(width)
        let lines = makeGlyphs(
            maxWidth: maxWidth,
            maximumHeight: height,
            lineLimit: layoutProperties?.lineLimit,
            truncationMode: layoutProperties?.truncationMode ?? .tail
        )
        return glyphAtoms(lineGlyphs: lines, in: size)
    }

    func glyphAtoms(lineGlyphs lines: [LineGlyphs], in size: CGSize) -> [GlyphAtom] {
        let width = max(size.width, 0) * scaleFactor
        let scale = 1 / scaleFactor
        var atoms: [GlyphAtom] = []
        for line in lines {
            let clusterCount = Self.clusterRanges(in: line.glyphs).count
            let fallbackAdvance = line.width > 0 || line.glyphs.isEmpty
                ? CGFloat.zero
                : width / CGFloat(clusterCount)
            var glyphOriginX = line.originX
            var pendingAtom: GlyphAtom?
            for (index, glyph) in line.glyphs.enumerated() {
                let continuesCluster = index > 0 &&
                    Self.sameCluster(glyph, line.glyphs[index - 1])
                let advance = glyph.advance.width > 0
                    ? glyph.advance.width
                    : (continuesCluster ? 0 : fallbackAdvance)
                if index != 0 {
                    glyphOriginX += glyph.kerning.x
                }
                let atom = GlyphAtom(
                    scalar: glyph.scalar,
                    sourceRange: glyph.sourceRange ??
                        glyph.characterIndex..<(glyph.characterIndex + 1),
                    bounds: CGRect(
                        x: glyphOriginX * scale,
                        y: line.originY * scale,
                        width: advance * scale,
                        height: line.height * scale
                    )
                )
                if var pending = pendingAtom, continuesCluster {
                    pending.bounds = pending.bounds.union(atom.bounds)
                    pendingAtom = pending
                } else {
                    if let pendingAtom {
                        atoms.append(pendingAtom)
                    }
                    pendingAtom = atom
                }
                glyphOriginX += advance
            }
            if let pendingAtom {
                atoms.append(pendingAtom)
            }
        }
        return atoms
    }

    final class Drawing {
        struct Vertex {
            var position: CGPoint
            var texcoord: Float2
        }

        struct Batch {
            var texture: Texture
            var vertices: [Vertex]
            var colorGlyphs: Bool
            var foregroundColor: Color?
        }

        struct Attachment {
            var texture: Texture
            var frame: CGRect
            var textureFrame: CGRect
        }

        struct VectorBatch {
            var path: Path
            var foregroundColor: Color?
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

        var source: ResolvedTextSource
        // Point-space placement inside the expanded text drawing frame.
        let origin: CGPoint
        var lineGlyphs: [LineGlyphs]
        var batches: [Batch]
        var vectorBatches: [VectorBatch]
        var attachments: [Attachment]
        var backgrounds: [Background]
        var decorations: [Decoration]

        init(
            source: ResolvedTextSource,
            origin: CGPoint,
            lineGlyphs: [LineGlyphs],
            batches: [Batch],
            vectorBatches: [VectorBatch],
            attachments: [Attachment],
            backgrounds: [Background],
            decorations: [Decoration]
        ) {
            self.source = source
            self.origin = origin
            self.lineGlyphs = lineGlyphs
            self.batches = batches
            self.vectorBatches = vectorBatches
            self.attachments = attachments
            self.backgrounds = backgrounds
            self.decorations = decorations
        }

        var isEmpty: Bool {
            lineGlyphs.isEmpty
        }
    }

    struct TextGlyphs {
        private struct SourceSpan {
            var range: Range<Int>
            var face: Typeface
            var makesGlyphs: Bool
        }

        let glyphs: [Glyph]
        let width: CGFloat
        var height: CGFloat { ascender - descender }
        let ascender: CGFloat
        let descender: CGFloat
        let lastFace: Typeface?
        let lastCharacter: UnicodeScalar
        var fontLineMetrics: FontLineMetrics? = nil
        static func from(unicodeScalars: String.UnicodeScalarView,
                         with faces: [Typeface],
                         drawMissingGlyphs: Bool,
                         prevFace: Typeface?,
                         prevChar: UnicodeScalar,
                         fontResource: FontResource? = nil,
                         scaleFactor: CGFloat = 1) -> Self {
            assert(faces.isEmpty == false)
            let scalars = Array(unicodeScalars)
            var glyphs: [Glyph] = []
            var ascender: CGFloat = .zero
            var descender: CGFloat = .zero
            var width: CGFloat = .zero
            var face1 = prevFace
            var char1 = prevChar
            let primaryMetrics = fontResource?.resolvedMetrics(for: faces[0], scaleFactor: scaleFactor)
            let fontLineMetrics = primaryMetrics.map {
                FontLineMetrics(metrics: $0, pointSize: fontResource!.pointSize,
                                isTextStyle: fontResource!.stylePolicy != nil, scale: scaleFactor)
            }
            // Ordinary line inputs round in points before applying the render scale.
            // Natural font leading remains a separate run metric.
            let lineBoxAscender = primaryMetrics.map { floor($0.ascender + 0.5) * scaleFactor }
                ?? faces[0].ascender
            let lineBoxDescender = primaryMetrics.map { metrics in
                let ascent = floor(metrics.ascender + 0.5)
                let height = ascent + floor(-metrics.descender + 0.5)
                return (ascent - (height > 0 ? height : 0.0001)) * scaleFactor
            } ?? faces[0].descender

            var spans: [SourceSpan] = []
            func appendSpan(
                _ range: Range<Int>,
                face: Typeface,
                makesGlyphs: Bool
            ) {
                guard !range.isEmpty else { return }
                if let index = spans.indices.last,
                   spans[index].range.upperBound == range.lowerBound,
                   spans[index].makesGlyphs == makesGlyphs,
                   spans[index].face.isEqual(to: face) {
                    spans[index].range =
                        spans[index].range.lowerBound..<range.upperBound
                } else {
                    spans.append(SourceSpan(
                        range: range,
                        face: face,
                        makesGlyphs: makesGlyphs
                    ))
                }
            }

            let source = String(unicodeScalars)
            var scalarIndex = 0
            for character in source {
                let characterScalars = Array(character.unicodeScalars)
                let range = scalarIndex..<(scalarIndex + characterScalars.count)
                scalarIndex = range.upperBound
                let visibleScalars = characterScalars.filter {
                    !$0.properties.isDefaultIgnorableCodePoint && $0.value != 0x0b
                }
                let emojiRequested = characterScalars.contains { $0.value == 0xfe0f }
                let textRequested = characterScalars.contains { $0.value == 0xfe0e }
                let emojiDefault = characterScalars.first?.properties.isEmojiPresentation == true
                let textPreferred = textRequested || (!emojiRequested && !emojiDefault &&
                    characterScalars.first?.properties.isEmoji == true)
                let candidates: [Typeface]
                if emojiRequested {
                    candidates = faces.filter(\.isEmojiFallback) + faces.filter { !$0.isEmojiFallback }
                } else if emojiDefault && !textRequested {
                    // An explicit primary face keeps ownership when it covers
                    // the cluster; emoji defaults precede ordinary fallbacks.
                    candidates = Array(faces.prefix(1)) +
                        faces.dropFirst().filter(\.isEmojiFallback) +
                        faces.dropFirst().filter { !$0.isEmojiFallback }
                } else {
                    candidates = faces
                }
                func supportedFace() -> Typeface? {
                    func covers(_ face: Typeface) -> Bool {
                        visibleScalars.allSatisfy(face.hasGlyph(for:))
                    }
                    if textPreferred {
                        if let ordinary = faces.first(where: { !$0.isEmojiFallback && covers($0) }) {
                            return ordinary
                        }
                        if let monochrome = faces.first(where: {
                            $0.isEmojiFallback && !$0.hasColorGlyphs && covers($0)
                        }) {
                            return monochrome
                        }
                    }
                    return candidates.first(where: covers)
                }
                if visibleScalars.isEmpty {
                    appendSpan(range, face: faces[0], makesGlyphs: false)
                } else if let face = supportedFace() {
                    appendSpan(range, face: face, makesGlyphs: true)
                } else {
                    for index in range {
                        let scalar = scalars[index]
                        let supportedFace = faces.first {
                            $0.hasGlyph(for: scalar)
                        }
                        let makeMissingGlyph = drawMissingGlyphs &&
                            !scalar.properties.isDefaultIgnorableCodePoint
                        let face = supportedFace ?? (
                            makeMissingGlyph ? faces[faces.count - 1] : faces[0]
                        )
                        appendSpan(
                            index..<(index + 1),
                            face: face,
                            makesGlyphs:
                                supportedFace != nil || makeMissingGlyph
                        )
                    }
                }
            }

            func append(_ glyph: Glyph) {
                glyphs.append(glyph)
                ascender = max(ascender, glyph.lineBoxAscender)
                descender = min(descender, glyph.lineBoxDescender)
                width += glyph.advance.width + glyph.kerning.x
            }

            func appendScalarGlyphs(_ span: SourceSpan) {
                let rawMetrics = fontResource?.resolvedMetrics(for: span.face, scaleFactor: scaleFactor,
                    applyingStylePolicy: span.face.isEqual(to: faces[0]))
                let leading = rawMetrics.map { $0.leading * scaleFactor } ?? span.face.resolvedMetrics.leading
                for index in span.range {
                    let scalar = scalars[index]
                    var glyph = Glyph(scalar: scalar, face: span.face)
                    glyph.sourceRange = index..<(index + 1)
                    glyph.lineBoxAscender = lineBoxAscender
                    glyph.lineBoxDescender = lineBoxDescender
                    glyph.fontLineMetrics = fontLineMetrics
                    if span.makesGlyphs,
                       let metrics = span.face.glyphMetrics(for: scalar) {
                        glyph.content = .unresolved
                        glyph.advance = metrics.advance
                        glyph.ascender = metrics.ascender
                        glyph.descender = metrics.descender
                        if let face1, face1.isEqual(to: span.face) {
                            glyph.kerning = face1.kernAdvance(
                                left: char1,
                                right: scalar
                            )
                        }
                    } else {
                        glyph.ascender = span.face.ascender
                        glyph.descender = span.face.descender
                    }
                    if let rawMetrics {
                        glyph.ascender = rawMetrics.ascender * scaleFactor
                        glyph.descender = rawMetrics.descender * scaleFactor
                    }
                    glyph.leading = leading
                    append(glyph)
                    char1 = scalar
                    face1 = span.face
                }
            }

            for span in spans {
                let spanText = String(
                    decoding: scalars[span.range].map(\.value),
                    as: Unicode.UTF32.self
                )
                guard span.makesGlyphs,
                      let shaped = span.face.shape(
                        spanText,
                        direction: nil,
                        language: nil,
                        features: []
                      ),
                      shaped.direction == .leftToRight,
                      !shaped.glyphs.isEmpty else {
                    appendScalarGlyphs(span)
                    continue
                }

                guard shaped.glyphs.allSatisfy({ glyph in
                    !glyph.sourceRange.isEmpty &&
                        glyph.sourceRange.lowerBound >= 0 &&
                        glyph.sourceRange.upperBound <= span.range.count
                }) else {
                    appendScalarGlyphs(span)
                    continue
                }

                let rawMetrics = fontResource?.resolvedMetrics(for: span.face, scaleFactor: scaleFactor,
                    applyingStylePolicy: span.face.isEqual(to: faces[0]))
                let leading = rawMetrics.map { $0.leading * scaleFactor } ?? span.face.resolvedMetrics.leading
                for (index, shapedGlyph) in shaped.glyphs.enumerated() {
                    let sourceRange = (
                        span.range.lowerBound +
                            shapedGlyph.sourceRange.lowerBound
                    )..<(
                        span.range.lowerBound +
                            shapedGlyph.sourceRange.upperBound
                    )
                    let scalar = scalars[sourceRange.lowerBound]
                    var glyph = Glyph(scalar: scalar, face: span.face)
                    glyph.glyphIndex = shapedGlyph.index
                    glyph.sourceRange = sourceRange
                    glyph.advance = shapedGlyph.advance
                    glyph.positionOffset = shapedGlyph.offset
                    glyph.lineBoxAscender = lineBoxAscender
                    glyph.lineBoxDescender = lineBoxDescender
                    glyph.fontLineMetrics = fontLineMetrics
                    if let metrics = span.face.glyphMetrics(
                        at: shapedGlyph.index
                    ) {
                        glyph.content = .unresolved
                        glyph.ascender = metrics.ascender
                        glyph.descender = metrics.descender
                    } else {
                        glyph.ascender = span.face.ascender
                        glyph.descender = span.face.descender
                    }
                    if let rawMetrics {
                        glyph.ascender = rawMetrics.ascender * scaleFactor
                        glyph.descender = rawMetrics.descender * scaleFactor
                    }
                    glyph.leading = leading
                    if index == 0,
                       let face1,
                       face1.isEqual(to: span.face) {
                        glyph.kerning = face1.kernAdvance(
                            left: char1,
                            right: scalar
                        )
                    }
                    append(glyph)
                }

                char1 = scalars[span.range.upperBound - 1]
                face1 = span.face
            }

            if glyphs.isEmpty {
                ascender = lineBoxAscender
                descender = lineBoxDescender
            }
            assert((ascender - descender) > 0)
            return .init(
                glyphs: glyphs,
                width: width,
                ascender: ascender,
                descender: descender,
                lastFace: face1,
                lastCharacter: char1,
                fontLineMetrics: fontLineMetrics
            )
        }
    }

    func makeGlyphs(
        maxWidth: Int = .max,
        maxHeight: Int = .max,
        lineLimit: Int? = nil,
        truncationMode: Text.TruncationMode = .tail
    ) -> [LineGlyphs] {
        makeGlyphs(maxWidth: maxWidth, maximumHeight: CGFloat(maxHeight),
                   lineLimit: lineLimit, truncationMode: truncationMode)
    }

    func makeGlyphs(
        maxWidth: Int = .max,
        maximumHeight: CGFloat,
        lineLimit: Int? = nil,
        truncationMode: Text.TruncationMode = .tail
    ) -> [LineGlyphs] {
        makeGlyphLayout(maxWidth: maxWidth, maximumHeight: maximumHeight,
            lineLimit: lineLimit, truncationMode: truncationMode).lines
    }

    func makeGlyphLayout(
        maxWidth: Int,
        maximumHeight: CGFloat,
        lineLimit: Int? = nil,
        truncationMode: Text.TruncationMode = .tail,
        sourceLines: [LineGlyphs]? = nil
    ) -> GlyphLayout {
        _lineWrap(
            sourceLines ?? unwrappedGlyphLines(),
            maxWidth: maxWidth,
            maxHeight: maximumHeight,
            lineLimit: lineLimit,
            truncationMode: truncationMode
        )
    }

    func makeGlyphLayout(in size: CGSize, layoutProperties: TextLayoutProperties,
                         sourceLines: [LineGlyphs]? = nil) -> GlyphLayout {
        makeGlyphLayout(maxWidth: Self.pixelLimit(max(size.width, 0) * scaleFactor),
            maximumHeight: max(size.height, 0) * scaleFactor, lineLimit: layoutProperties.lineLimit,
            truncationMode: layoutProperties.truncationMode, sourceLines: sourceLines)
    }

    func unwrappedGlyphLines() -> [LineGlyphs] {
        storage.lineGlyphs { runs in
            Self._makeGlyphs(
                runs: runs,
                scaleFactor: self.scaleFactor,
                drawMissingGlyphs: self.drawMissingGlyphs
            )
        }
    }

    func prepareResources() {
        for line in makeGlyphs() {
            for glyph in line.glyphs {
                guard case .unresolved = glyph.content else { continue }
                if let index = glyph.glyphIndex {
                    _ = glyph.face.glyph(at: index)
                } else {
                    _ = glyph.face.glyph(for: glyph.scalar)
                }
            }
        }
    }

    func makeDrawing(
        in size: CGSize,
        layoutProperties: TextLayoutProperties? = nil,
        origin: CGPoint = .zero
    ) -> Drawing {
        let width = max(size.width, 0) * scaleFactor
        let height = max(size.height, 0) * scaleFactor
        let maxWidth = Self.pixelLimit(width)
        let lineGlyphs = makeGlyphs(
            maxWidth: maxWidth,
            maximumHeight: height,
            lineLimit: layoutProperties?.lineLimit,
            truncationMode: layoutProperties?.truncationMode ?? .tail
        )
        return makeDrawing(lineGlyphs: lineGlyphs, origin: origin)
    }

    func makeDrawing(lineGlyphs: [LineGlyphs], origin: CGPoint = .zero) -> Drawing {

        struct Quad {
            var vertices: [Drawing.Vertex]
            var texture: Texture
            var colorGlyphs: Bool
            var foregroundColor: Color?
        }

        var quads: [Quad] = []
        var vectorBatches: [Drawing.VectorBatch] = []
        var attachments: [Drawing.Attachment] = []
        var backgrounds: [Drawing.Background] = []
        var decorations: [Drawing.Decoration] = []

        func appendTexture(
            texture: Texture?,
            frame textureBounds: CGRect,
            offset: CGPoint,
            baseline: CGPoint,
            foregroundColor: Color?,
            scale: CGFloat = 1
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
                y: baseline.y - offset.y * scale,
                width: textureBounds.width * scale,
                height: textureBounds.height * scale
            ).insetBy(dx: -pad * scale, dy: -pad * scale)
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

        func appendVector(
            path: Path,
            baseline: CGPoint,
            foregroundColor: Color?
        ) {
            guard !path.isEmpty else { return }
            let transform = CGAffineTransform(
                translationX: baseline.x,
                y: baseline.y
            )
            if let index = vectorBatches.firstIndex(where: {
                $0.foregroundColor == foregroundColor
            }) {
                vectorBatches[index].path.addPath(
                    path,
                    transform: transform
                )
            } else {
                var transformedPath = Path()
                transformedPath.addPath(path, transform: transform)
                vectorBatches.append(Drawing.VectorBatch(
                    path: transformedPath,
                    foregroundColor: foregroundColor
                ))
            }
        }

        Self.forEachGlyph(in: lineGlyphs) { glyph, baseline in
            switch glyph.content {
            case .unresolved:
                let content: TypefaceGlyph?
                if let index = glyph.glyphIndex {
                    content = glyph.face.glyph(at: index)
                } else {
                    content = glyph.face.glyph(for: glyph.scalar)
                }
                switch content {
                case let .texture(data, scale):
                    appendTexture(
                        texture: data.texture,
                        frame: data.frame,
                        offset: data.offset,
                        baseline: CGPoint(
                            x: baseline.x + data.offset.x * scale,
                            y: baseline.y
                        ),
                        foregroundColor: glyph.foregroundColor,
                        scale: scale
                    )
                case let .vector(data):
                    appendVector(
                        path: data.path,
                        baseline: baseline,
                        foregroundColor: glyph.foregroundColor
                    )
                case nil:
                    break
                }

            case let .texture(data):
                guard glyph.scalar != UnicodeScalar(0) else { return }
                appendTexture(
                    texture: data.texture,
                    frame: data.frame,
                    offset: data.offset,
                    baseline: baseline,
                    foregroundColor: glyph.foregroundColor
                )

            case let .vector(data):
                appendVector(
                    path: data.path,
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

            case .missing:
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

        for line in lineGlyphs {
            var cellOriginX = line.originX
            for (index, glyph) in line.glyphs.enumerated() {
                let kerning = index == 0 ? 0 : glyph.kerning.x
                let cellWidth = kerning + glyph.advance.width
                let baseline = CGPoint(
                    x: cellOriginX + kerning,
                    y: line.baseline - glyph.baselineOffset
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
            origin: origin,
            lineGlyphs: lineGlyphs,
            batches: batches,
            vectorBatches: vectorBatches,
            attachments: attachments,
            backgrounds: backgrounds,
            decorations: decorations
        )
    }

    static func forEachGlyph(
        in lineGlyphs: [LineGlyphs],
        callback: (_ glyph: Glyph, _ baseline: CGPoint) -> Void
    ) {
        var offset: CGPoint = .zero
        for line in lineGlyphs {
            offset = CGPoint(x: line.originX, y: line.originY)
            for glyph in line.glyphs {
                let kerning: CGPoint = offset.x > line.originX
                    ? glyph.kerning
                    : .zero
                offset += kerning
                let baseline = CGPoint(
                    x: glyph.contentOffset.x + offset.x +
                        glyph.positionOffset.x,
                    y: line.ascender + offset.y - glyph.baselineOffset -
                        glyph.positionOffset.y
                )
                callback(glyph, baseline)
                offset.x += glyph.advance.width
            }
        }
    }

    private func _lineWrap(
        _ lines: [LineGlyphs],
        maxWidth: Int,
        maxHeight: CGFloat,
        lineLimit: Int?,
        truncationMode: Text.TruncationMode
    ) -> GlyphLayout {
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
        let wrappingWidth = { (glyphs: [Glyph]) -> CGFloat in
            let trailing = glyphs.reversed().prefix { CharacterSet.whitespaces.contains($0.scalar) }.count
            return getGlyphsWidth(Array(glyphs.dropLast(trailing)))
        }
        // Returns the glyph index immediately after a breakable cluster.
        let getBreakableSplitIndex = { (glyphs: [Glyph]) -> Int? in
            let clusters = Self.clusterRanges(in: glyphs)
            for clusterIndex in clusters.indices.reversed() {
                let cluster = clusters[clusterIndex]
                let scalar = glyphs[cluster.lowerBound].scalar
                if breakables.contains(scalar) {
                    var beforeNumber = false
                    var afterNumber = false
                    if clusterIndex + 1 < clusters.endIndex {
                        beforeNumber = decimalNumbers.contains(
                            glyphs[clusters[clusterIndex + 1].lowerBound].scalar
                        )
                    }
                    if clusterIndex > clusters.startIndex {
                        afterNumber = decimalNumbers.contains(
                            glyphs[clusters[clusterIndex - 1].lowerBound].scalar
                        )
                    }
                    if breakableNotBeforeDN.contains(scalar) && beforeNumber {
                        continue
                    }
                    if breakableNotBetweenDN.contains(scalar) && beforeNumber && afterNumber {
                        continue
                    }
                    return cluster.upperBound
                }
            }
            return nil
        }
        // Wrap long lines to satisfy line break conditions.
        let splitLineGlyphs = {
            (glyphs: [Glyph], maxWidth: Int) -> (first: [Glyph], second: [Glyph]) in
            let trailing = glyphs.reversed().prefix { CharacterSet.whitespaces.contains($0.scalar) }.count
            var first = Array(glyphs.dropLast(trailing))
            var second = Array(glyphs.suffix(trailing))
            while Self.clusterRanges(in: first).count > 1 &&
                    Int(ceil(wrappingWidth(first))) > maxWidth {
                if let splitIndex = getBreakableSplitIndex(first),
                   splitIndex != first.endIndex {
                    second.insert(
                        contentsOf: first[splitIndex...],
                        at: second.startIndex
                    )
                    first.removeSubrange(splitIndex...)
                } else if let cluster =
                    Self.clusterRanges(in: first).last {
                    second.insert(
                        contentsOf: first[cluster],
                        at: second.startIndex
                    )
                    first.removeSubrange(cluster)
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
            while Self.clusterRanges(in: line.glyphs).count > 1,
                  Int(ceil(wrappingWidth(line.glyphs))) > maxWidth {
                let split = splitLineGlyphs(line.glyphs, maxWidth)
                guard !split.second.isEmpty else { break }

                var first = line
                first.glyphs = split.first
                first.trailingBoundary = nil
                first.isParagraphEnd = false
                // Retain the fallback used for this particular split. A
                // later, unprocessed line must not affect fitting decisions.
                let boundary = getBreakableSplitIndex(first.glyphs)
                first.forcedClusterBreak = boundary != first.glyphs.endIndex &&
                    !CharacterSet.whitespaces.contains(split.second[0].scalar)
                updateMetrics(&first)
                if Int(ceil(wrappingWidth(first.glyphs))) <= maxWidth {
                    first.width = min(first.width, CGFloat(maxWidth))
                }
                wrappedLines.append(first)

                line.glyphs = split.second
                updateMetrics(&line)
            }
            // Trailing whitespace stays in the glyph range even when it
            // extends beyond the wrapping width. Clip its reported extent.
            if Int(ceil(wrappingWidth(line.glyphs))) <= maxWidth {
                line.width = min(line.width, CGFloat(maxWidth))
            }
            wrappedLines.append(line)
        }

        var paragraphInputs: [Int: Glyph] = [:]
        var precedingBoundary: Glyph?
        for line in lines {
            if paragraphInputs[line.paragraphIndex] == nil {
                paragraphInputs[line.paragraphIndex] = line.paragraphInput ?? line.glyphs.first ?? line.trailingBoundary ?? precedingBoundary
            }
            precedingBoundary = line.trailingBoundary
        }

        func metrics(for glyphs: [Glyph], usesSystemLeading: Bool, usesNegativeLeading: Bool) -> TextLineMetrics {
            var result = TextLineMetrics()
            for glyph in glyphs {
                let input = glyph.fontLineMetrics
                result.add(ascent: input?.ascent ?? glyph.lineBoxAscender,
                           height: input?.height(usesSystemLeading: usesSystemLeading) ??
                               (glyph.lineBoxAscender - glyph.lineBoxDescender),
                           leading: input?.leading(usesSystemLeading: usesSystemLeading,
                                                   usesNegativeLeading: usesNegativeLeading) ?? 0,
                           baselineOffset: glyph.baselineOffset)
            }
            return result
        }

        func paragraphOrigin(after previous: LineGlyphs?) -> CGFloat {
            guard let previous else { return 0 }
            return previous.maxY - previous.paragraphStartSpacing +
                (previous.paragraphIndex == 0 ? 0 : previous.spacing)
        }

        func place(_ source: LineGlyphs, after previous: LineGlyphs?) -> LineGlyphs {
            var line = source
            line.originY = previous?.maxY ?? 0
            if case .extra(nil) = line.kind {
                guard let input = defaultLineMetrics else {
                    preconditionFailure("A missing-attribute fragment requires default font metrics.")
                }
                line.ascender = input.ascent
                line.descender = input.ascent - input.height
                line.originY = (previous?.originY ?? 0) + input.height
                return line
            }
            let paragraphInput = paragraphInputs[line.paragraphIndex]
            let spacing = max(paragraphInput?.style.paragraphStyle?.lineSpacing ?? 0, 0) * scaleFactor
            let inputs: [Glyph]
            if case let .extra(attributes?) = line.kind {
                inputs = [attributes]
            } else {
                inputs = line.glyphs.isEmpty ? paragraphInput.map { [$0] } ?? [] : line.glyphs
            }
            if !inputs.isEmpty {
                let merged = metrics(for: inputs,
                                     usesSystemLeading: line.paragraphIndex != 0 || !line.isParagraphEnd,
                                     usesNegativeLeading: previous != nil)
                line.ascender = merged.baseline
                line.descender = merged.baseline - merged.height
                line.spacing = merged.spacing(requested: spacing)
            }
            if let previous {
                if previous.paragraphIndex == line.paragraphIndex {
                    line.paragraphStartSpacing = previous.paragraphStartSpacing
                    line.originY += previous.spacing
                } else {
                    // Paragraph advance and the first attribute's leading contribution
                    // are separate. A mixed paragraph cannot substitute its maximum here.
                    line.originY = paragraphOrigin(after: previous)
                    if let paragraphInput {
                        line.paragraphStartSpacing = metrics(for: [paragraphInput],
                            usesSystemLeading: true, usesNegativeLeading: true).spacing(requested: spacing)
                    }
                    if line.isSimpleParagraph {
                        line.descender -= line.paragraphStartSpacing
                    } else {
                        line.originY += line.paragraphStartSpacing
                    }
                }
            }
            return line
        }

        var visibleLines: [LineGlyphs] = []
        var processedLineCount = 0
        var forcedClusterBreak = false
        var truncatedRanges: [Range<Int>] = []
        func publish(_ line: LineGlyphs, countsAsLine: Bool = true) {
            visibleLines.append(line)
            if countsAsLine { processedLineCount += 1 }
        }
        func result() -> GlyphLayout {
            GlyphLayout(lines: visibleLines, lineCount: processedLineCount,
                        forcedClusterBreak: forcedClusterBreak, truncatedRanges: truncatedRanges)
        }
        let maximumLineCount = maxHeight == 0 ? 1 : lineLimit.map { max($0, 1) }
        let availableHeight = maxHeight == 0 ? CGFloat.infinity : maxHeight
        let heightEpsilon = 0.001 * scaleFactor
        var nextLineIndex = 0
        var needsTruncation = false
        paragraphLoop: while nextLineIndex < wrappedLines.count {
            let start = nextLineIndex
            let paragraph = wrappedLines[start].paragraphIndex
            var end = start + 1
            while end < wrappedLines.count, wrappedLines[end].paragraphIndex == paragraph {
                end += 1
            }
            let budget = maximumLineCount.map { $0 - visibleLines.count }
            if let budget, budget <= 0 { break }
            let paragraphY = paragraphOrigin(after: visibleLines.last)
            let remainingHeight = availableHeight - paragraphY
            if paragraphY > 0, remainingHeight <= 0 { break }

            if wrappedLines[start].isSimpleParagraph {
                let line = place(wrappedLines[start], after: visibleLines.last)
                forcedClusterBreak = forcedClusterBreak || line.forcedClusterBreak
                // Simple paragraphs test the font height before adding the
                // paragraph's starting spacing to the published rectangle.
                let height = line.height - line.paragraphStartSpacing
                if start != 0, height > remainingHeight + heightEpsilon { break }
                publish(line)
                nextLineIndex = start + 1
                // A simple paragraph publishes its missing-attribute extra
                // outside both its height check and its ordinary line budget.
                if nextLineIndex < end, case .extra(nil) = wrappedLines[nextLineIndex].kind {
                    publish(place(wrappedLines[nextLineIndex], after: visibleLines.last))
                    nextLineIndex += 1
                }
                continue
            }

            var candidates = Array(wrappedLines[start..<end])
            let hasFinalExtra: Bool
            if case .extra = candidates.last!.kind {
                hasFinalExtra = true
            } else {
                hasFinalExtra = false
                if let boundary = candidates.last!.trailingBoundary {
                    // A terminated paragraph must also attempt its continuation
                    // before committing its final content line. Only the last
                    // paragraph can expose this continuation as an extra line.
                    candidates.append(LineGlyphs(glyphs: [], ascender: 0, descender: 0, width: 0,
                        paragraphIndex: paragraph, paragraphInput: paragraphInputs[paragraph],
                        kind: .extra(boundary)))
                }
            }

            if candidates.count == 1, !hasFinalExtra,
               Int(ceil(candidates[0].width)) <= maxWidth {
                // A complete line that fits a rectangular container uses
                // the paragraph-origin gate, without a second height test.
                publish(place(candidates[0], after: visibleLines.last))
                nextLineIndex = end
                continue
            }

            var pending: (line: LineGlyphs, index: Int)?
            var admitted = 0
            for (offset, source) in candidates.enumerated() {
                if let budget, admitted >= budget {
                    if let pending, !pending.line.glyphs.isEmpty {
                        publish(pending.line)
                        nextLineIndex = pending.index + 1
                        needsTruncation = true
                    }
                    break paragraphLoop
                }
                let line = place(source, after: pending?.line ?? visibleLines.last)
                forcedClusterBreak = forcedClusterBreak || line.forcedClusterBreak
                let isExtra: Bool
                if case .extra = source.kind { isExtra = true } else { isExtra = false }
                let enforcesMinimum = start == 0 && admitted == 0
                let candidateHeight = (line.originY - paragraphY) + line.height
                if !enforcesMinimum, candidateHeight > remainingHeight + heightEpsilon {
                    if let pending {
                        if hasFinalExtra && isExtra {
                            // A failed final extra retains the pending rectangle.
                            // Publish the empty fragment there before finalizing
                            // any text, so their bounds can overlap.
                            var empty = pending.line
                            empty.glyphs = []
                            empty.width = 0
                            empty.trailingBoundary = nil
                            empty.kind = source.kind
                            publish(empty, countsAsLine: false)
                            if !pending.line.glyphs.isEmpty { publish(pending.line) }
                            nextLineIndex = end
                        } else if !pending.line.glyphs.isEmpty {
                            publish(pending.line)
                            nextLineIndex = pending.index + 1
                            // Finalization tests two pending line heights,
                            // excluding interline spacing and the admission
                            // tolerance. A failed provisional extra can thus
                            // finish this paragraph without truncating it.
                            let nextHeight = (pending.line.originY - paragraphY) +
                                pending.line.height + pending.line.height
                            needsTruncation = !isExtra || nextHeight > remainingHeight
                            if isExtra, !needsTruncation {
                                nextLineIndex = end
                                continue paragraphLoop
                            }
                        }
                    }
                    break paragraphLoop
                }
                if let pending {
                    publish(pending.line)
                    nextLineIndex = pending.index + 1
                }
                admitted += 1
                pending = (line, start + offset)
                if isExtra {
                    if hasFinalExtra { publish(line) }
                    pending = nil
                    nextLineIndex = end
                }
            }
            if let pending {
                // A shaped line can finalize without a following candidate.
                // A separator-only candidate has no such text line to flush.
                if !pending.line.glyphs.isEmpty { publish(pending.line) }
                nextLineIndex = end
            }
            if nextLineIndex != end {
                break
            }
        }

        guard let lastVisibleIndex = visibleLines.indices.last else {
            return result()
        }
        if !needsTruncation, Int(ceil(visibleLines[lastVisibleIndex].width)) <= maxWidth {
            return result()
        }

        let lastParagraph = visibleLines[lastVisibleIndex].paragraphIndex
        var paragraphGlyphs = visibleLines[lastVisibleIndex].glyphs
        var continuationIndex = nextLineIndex
        while visibleLines[lastVisibleIndex].trailingBoundary == nil,
              continuationIndex < wrappedLines.count,
              wrappedLines[continuationIndex].paragraphIndex ==
                lastParagraph {
            paragraphGlyphs.append(
                contentsOf: wrappedLines[continuationIndex].glyphs
            )
            let reachesBoundary = wrappedLines[continuationIndex].trailingBoundary != nil
            continuationIndex += 1
            // A hard line break ends the truncation source even when the
            // following line belongs to the same paragraph.
            if reachesBoundary { break }
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
            return result()
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
                prevChar: previous?.scalar ?? UnicodeScalar(UInt8(0)),
                fontResource: source.style.fontResource,
                scaleFactor: scaleFactor
            )
            guard var glyph = generated.glyphs.first else {
                return nil
            }
            glyph.attributes = source.attributes
            glyph.style = source.style
            glyph.baselineOffset = source.baselineOffset
            glyph.ascender = source.ascender
            glyph.descender = source.descender
            glyph.leading = source.leading
            glyph.lineBoxAscender = source.lineBoxAscender
            glyph.lineBoxDescender = source.lineBoxDescender
            glyph.fontLineMetrics = source.fontLineMetrics
            glyph.foregroundColor = source.foregroundColor
            glyph.characterIndex = characterIndex
            glyph.sourceRange = characterIndex..<(characterIndex + 1)
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

        func truncatedRange(_ clusters: ArraySlice<[Glyph]>) -> Range<Int>? {
            guard let lower = clusters.first?.first?.sourceRange?.lowerBound,
                  let upper = clusters.last?.last?.sourceRange?.upperBound,
                  lower < upper else { return nil }
            return lower..<upper
        }

        func tailTruncation(
            _ glyphs: [Glyph],
            explicitBoundary: Glyph?
        ) -> (glyphs: [Glyph], range: Range<Int>?)? {
            if let explicitBoundary,
               let source = glyphs.last {
                var prefix = Self.clusterRanges(in: glyphs).map {
                    Array(glyphs[$0])
                }
                while true {
                    let flattenedPrefix = prefix.flatMap { $0 }
                    guard let ellipsis = makeEllipsis(
                        inheriting: source,
                        characterIndex: explicitBoundary.characterIndex,
                        after: flattenedPrefix.last
                    ) else {
                        return nil
                    }
                    var candidate = flattenedPrefix + [ellipsis]
                    if !candidate.isEmpty {
                        candidate[0].kerning = .zero
                    }
                    if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                        return (candidate, nil)
                    }
                    guard !prefix.isEmpty else { return nil }
                    prefix.removeLast()
                }
            }

            let clusters = Self.clusterRanges(in: glyphs).map {
                Array(glyphs[$0])
            }
            guard clusters.count > 1 else { return nil }
            for prefixCount in stride(
                from: clusters.count - 1,
                through: 0,
                by: -1
            ) {
                guard let source = clusters[prefixCount].first else {
                    continue
                }
                var prefix = clusters[..<prefixCount].flatMap { $0 }
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
                    return (prefix, truncatedRange(clusters[prefixCount...]))
                }
            }
            return nil
        }

        func headTruncation(_ glyphs: [Glyph]) -> (glyphs: [Glyph], range: Range<Int>?)? {
            let clusters = Self.clusterRanges(in: glyphs).map {
                Array(glyphs[$0])
            }
            guard clusters.count > 1,
                  let source = glyphs.first,
                  let ellipsis = makeEllipsis(
                    inheriting: source,
                    characterIndex: source.characterIndex,
                    after: nil
                  ) else {
                return nil
            }
            for suffixCount in stride(
                from: clusters.count - 1,
                through: 0,
                by: -1
            ) {
                var suffix = clusters.suffix(suffixCount).flatMap { $0 }
                if !suffix.isEmpty {
                    suffix[0].kerning = adjacencyKerning(
                        from: ellipsis,
                        to: suffix[0]
                    )
                }
                let candidate = [ellipsis] + suffix
                if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                    return (candidate, truncatedRange(clusters.dropLast(suffixCount)))
                }
            }
            return nil
        }

        func middleTruncation(_ glyphs: [Glyph]) -> (glyphs: [Glyph], range: Range<Int>?)? {
            let clusters = Self.clusterRanges(in: glyphs).map {
                Array(glyphs[$0])
            }
            guard clusters.count > 1 else { return nil }

            var selectedPrefixCount = 0
            var selectedEllipsis: Glyph?
            for prefixCount in 0..<clusters.count {
                guard let source = clusters[prefixCount].first else {
                    continue
                }
                let prefix = clusters[..<prefixCount].flatMap { $0 }
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
                return ([ellipsis], truncatedRange(clusters[...]))
            }

            let maximumSuffixCount =
                clusters.count - selectedPrefixCount - 1
            let prefix = clusters[..<selectedPrefixCount].flatMap { $0 }
            for suffixCount in stride(
                from: maximumSuffixCount,
                through: 0,
                by: -1
            ) {
                var suffix = clusters.suffix(suffixCount).flatMap { $0 }
                if !suffix.isEmpty {
                    suffix[0].kerning = adjacencyKerning(
                        from: ellipsis,
                        to: suffix[0]
                    )
                }
                var candidate = prefix + [ellipsis] + suffix
                candidate[0].kerning = .zero
                if Int(ceil(getGlyphsWidth(candidate))) <= maxWidth {
                    return (candidate, truncatedRange(clusters[selectedPrefixCount..<(clusters.count - suffixCount)]))
                }
            }
            return nil
        }

        let explicitBoundary = hasExplicitLineOverflow
            ? visibleLines[lastVisibleIndex].trailingBoundary
            : nil
        let truncated: (glyphs: [Glyph], range: Range<Int>?)?
        if explicitBoundary != nil, truncationMode != .tail {
            return result()
        } else if explicitBoundary != nil {
            truncated = tailTruncation(
                visibleLines[lastVisibleIndex].glyphs,
                explicitBoundary: explicitBoundary
            )
        } else {
            switch truncationMode {
            case .head:
                truncated = headTruncation(paragraphGlyphs)
            case .middle:
                truncated = middleTruncation(paragraphGlyphs)
            case .tail:
                truncated = tailTruncation(
                    paragraphGlyphs,
                    explicitBoundary: nil
                )
            }
        }

        // Remeasuring the final line must preserve its admitted origin,
        // including an empty continuation that shares the same rectangle.
        let admittedOriginY = visibleLines[lastVisibleIndex].originY
        guard let truncated else {
            if hasParagraphOverflow {
                visibleLines[lastVisibleIndex].glyphs = paragraphGlyphs
                updateMetrics(&visibleLines[lastVisibleIndex])
                if maxWidth != .max {
                    visibleLines[lastVisibleIndex].width =
                        CGFloat(maxWidth)
                }
                visibleLines[lastVisibleIndex] = place(visibleLines[lastVisibleIndex],
                    after: lastVisibleIndex > 0 ? visibleLines[lastVisibleIndex - 1] : nil)
                visibleLines[lastVisibleIndex].originY = admittedOriginY
            }
            return result()
        }
        // A token or omitted content alone does not record truncation. Only
        // an accepted line with a nonempty removed source range contributes.
        if let range = truncated.range { truncatedRanges.append(range) }
        visibleLines[lastVisibleIndex].glyphs = truncated.glyphs
        visibleLines[lastVisibleIndex].trailingBoundary = nil
        visibleLines[lastVisibleIndex].isTruncated = hasParagraphOverflow
        updateMetrics(&visibleLines[lastVisibleIndex])
        visibleLines[lastVisibleIndex] = place(
            visibleLines[lastVisibleIndex],
            after: lastVisibleIndex > 0 ? visibleLines[lastVisibleIndex - 1] : nil
        )
        visibleLines[lastVisibleIndex].originY = admittedOriginY
        return result()
    }

    private static func _makeGlyphs(
        runs: [Run],
        scaleFactor: CGFloat,
        drawMissingGlyphs: Bool) -> [LineGlyphs] {
        var lines: [LineGlyphs] = []
        var glyphs: [Glyph] = []
        var offset: CGPoint = .zero
        var ascender: CGFloat = .zero
        var descender: CGFloat = .zero
        var char1 = UnicodeScalar(UInt8(0))
        var face1: Typeface?
        var characterIndex = 0
        var paragraphIndex = 0
        var paragraphInput: Glyph?
        var paragraphLength = 0
        var terminatedLength = 0
        var lastBreak: TextLineBreak?
        var lastBoundary: Glyph?
        var previousWasCR = false

        func addLine(_ boundary: Glyph?, isParagraphEnd: Bool) {
            lines.append(LineGlyphs(glyphs: glyphs,
                ascender: ascender, descender: descender, width: offset.x,
                trailingBoundary: boundary, paragraphIndex: paragraphIndex,
                paragraphInput: paragraphInput,
                isSimpleParagraph: boundary != nil && isParagraphEnd && paragraphLength == 1,
                isParagraphEnd: isParagraphEnd))
            glyphs.removeAll(keepingCapacity: true)
            offset.x = 0
            ascender = 0
            descender = 0
        }

        for s in runs {
            let textRun: ([Typeface], String, _TextAttributeValues, _ResolvedTextRunAttributes?)?
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
                let scalars = Array(text.unicodeScalars)
                let resolvedStyle = style ?? _ResolvedTextRunAttributes()
                let spacing = (resolvedStyle.tracking ?? resolvedStyle.kern ?? 0) * scaleFactor
                let baselineOffset = (resolvedStyle.baselineOffset ?? 0) * scaleFactor
                let fontInput = TextGlyphs.from(unicodeScalars: "".unicodeScalars,
                    with: faces, drawMissingGlyphs: false, prevFace: nil, prevChar: UnicodeScalar(0),
                    fontResource: style?.fontResource, scaleFactor: scaleFactor)

                func attributeGlyph(_ scalar: UnicodeScalar) -> Glyph {
                    var glyph = Glyph(scalar: scalar, face: faces[0])
                    glyph.ascender = fontInput.ascender
                    glyph.descender = fontInput.descender
                    glyph.lineBoxAscender = fontInput.ascender
                    glyph.lineBoxDescender = fontInput.descender
                    glyph.fontLineMetrics = fontInput.fontLineMetrics
                    glyph.attributes = attributes
                    glyph.style = resolvedStyle
                    glyph.baselineOffset = baselineOffset
                    glyph.foregroundColor = resolvedStyle.foregroundColor
                    glyph.characterIndex = characterIndex
                    glyph.sourceRange = characterIndex..<(characterIndex + 1)
                    return glyph
                }

                var index = 0
                while index < scalars.count {
                    let scalar = scalars[index]
                    if previousWasCR, scalar.value == 0x0a {
                        // A CRLF can cross attribute runs. Keep its first input
                        // for the paragraph and its final input for the extra line.
                        var boundary = attributeGlyph(scalar)
                        let start = lastBoundary!.sourceRange!.lowerBound
                        boundary.characterIndex = start
                        boundary.sourceRange = start..<(characterIndex + 1)
                        lines[lines.count - 1].trailingBoundary = boundary
                        lines[lines.count - 1].isSimpleParagraph = false
                        lastBoundary = boundary
                        terminatedLength += 1
                        characterIndex += 1
                        previousWasCR = false
                        index += 1
                        continue
                    }
                    previousWasCR = false
                    if let lineBreak = TextLineBreak(scalar) {
                        let boundary = attributeGlyph(scalar)
                        if paragraphInput == nil { paragraphInput = boundary }
                        if glyphs.isEmpty {
                            ascender = boundary.lineAscender
                            descender = boundary.lineDescender
                        }
                        paragraphLength += 1
                        addLine(boundary, isParagraphEnd: lineBreak == .paragraph)
                        lastBoundary = boundary
                        lastBreak = lineBreak
                        if lineBreak == .paragraph {
                            terminatedLength = paragraphLength
                            paragraphLength = 0
                            paragraphInput = nil
                            paragraphIndex += 1
                        }
                        characterIndex += 1
                        previousWasCR = scalar.value == 0x0d
                        face1 = nil
                        char1 = UnicodeScalar(UInt8(0))
                        index += 1
                        continue
                    }

                    let start = index
                    while index < scalars.count, TextLineBreak(scalars[index]) == nil {
                        paragraphLength += scalars[index].value > 0xffff ? 2 : 1
                        index += 1
                    }
                    if paragraphInput == nil { paragraphInput = attributeGlyph(scalars[start]) }
                    let span = String(String.UnicodeScalarView(scalars[start..<index]))
                    let textGlyphs = TextGlyphs.from(unicodeScalars: span.unicodeScalars,
                        with: faces, drawMissingGlyphs: drawMissingGlyphs, prevFace: face1,
                        prevChar: char1, fontResource: style?.fontResource, scaleFactor: scaleFactor)
                    face1 = textGlyphs.lastFace
                    char1 = textGlyphs.lastCharacter
                    lastBreak = nil
                    let runStartIndex = characterIndex
                    characterIndex += index - start
                    for var glyph in textGlyphs.glyphs {
                        if let range = glyph.sourceRange {
                            glyph.sourceRange = (runStartIndex + range.lowerBound)..<(runStartIndex + range.upperBound)
                            glyph.characterIndex = runStartIndex + range.lowerBound
                        } else {
                            glyph.characterIndex = runStartIndex
                        }
                        glyph.attributes = attributes
                        glyph.style = resolvedStyle
                        glyph.baselineOffset = baselineOffset
                        glyph.foregroundColor = resolvedStyle.foregroundColor
                        glyph.advance.width += spacing
                        if glyphs.isEmpty { glyph.kerning = .zero }
                        let kerning = glyphs.isEmpty ? CGFloat.zero : glyph.kerning.x
                        glyphs.append(glyph)
                        offset.x += kerning + glyph.advance.width
                        ascender = max(ascender, glyph.lineAscender)
                        descender = min(descender, glyph.lineDescender)
                    }
                }
            }
            let attachmentRun: ([Typeface], ImageDrawing, _TextAttributeValues)?
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
                glyph.lineBoxAscender = glyph.ascender
                glyph.lineBoxDescender = glyph.descender
                glyph.advance.width = width
                glyph.advance.height = height
                glyph.attributes = attributes
                glyph.characterIndex = characterIndex
                glyph.sourceRange =
                    characterIndex..<(characterIndex + 1)
                if paragraphInput == nil { paragraphInput = glyph }
                glyphs.append(glyph)
                characterIndex += 1
                paragraphLength += 1
                lastBreak = nil
                previousWasCR = false

                offset.x += glyph.advance.width
                ascender = max(ascender, glyph.lineAscender)
                descender = min(descender, glyph.lineDescender)

                face1 = nil
                char1 = UnicodeScalar(UInt8(0))
            }
        }
        if !glyphs.isEmpty {
            addLine(nil, isParagraphEnd: true)
        } else if let lastBreak, let lastBoundary, let previous = lines.last {
            let length = lastBreak == .paragraph ? terminatedLength : paragraphLength
            let attributes: Glyph? = length == 1 ? nil : lastBoundary
            // Only a retained extra fragment participates in paragraph leading.
            lines[lines.count - 1].isParagraphEnd = attributes == nil
            lines[lines.count - 1].isSimpleParagraph = length == 1
            lines.append(LineGlyphs(glyphs: [],
                ascender: attributes?.lineAscender ?? 0,
                descender: attributes?.lineDescender ?? 0, width: 0,
                paragraphIndex: previous.paragraphIndex, paragraphInput: previous.paragraphInput,
                kind: .extra(attributes)))
        }
        return lines
    }
}
