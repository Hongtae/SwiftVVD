//
//  File: TextRenderer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol TextAttribute: Hashable {
}

struct _AnyTextAttribute: Equatable {
    let type: ObjectIdentifier
    let value: AnyHashable

    init<T: TextAttribute>(_ value: T) {
        self.type = ObjectIdentifier(T.self)
        self.value = AnyHashable(value)
    }

    func value<T: TextAttribute>(as type: T.Type) -> T? {
        guard self.type == ObjectIdentifier(type) else { return nil }
        return value.base as? T
    }
}

struct _TextAttributeValues: Equatable {
    private var values: [ObjectIdentifier: _AnyTextAttribute] = [:]

    var isEmpty: Bool { values.isEmpty }

    mutating func set(_ value: _AnyTextAttribute) {
        values[value.type] = value
    }

    mutating func merge(_ other: _TextAttributeValues) {
        values.merge(other.values) { _, new in new }
    }

    func value<T: TextAttribute>(for type: T.Type) -> T? {
        values[ObjectIdentifier(type)]?.value(as: type)
    }

    func hash(into hasher: inout Hasher) {
        for value in values.values.sorted(by: { $0.type.hashValue < $1.type.hashValue }) {
            hasher.combine(value.type)
            hasher.combine(value.value)
        }
    }
}

public protocol TextRenderer: Animatable {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext)
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize
    var displayPadding: EdgeInsets { get }
}

extension TextRenderer {
    public func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        text.sizeThatFits(proposal)
    }

    public var displayPadding: EdgeInsets { EdgeInsets() }
}

/// Measures text with its resolved layout properties.
public struct TextProxy {
    private var text: ResolvedStyledText

    init(_ text: ResolvedStyledText) {
        self.text = text
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if proposal == .zero { return .zero }
        return text.sizeThatFits(_ProposedSize(proposal))
    }
}

fileprivate struct _TextLayoutRunStorage: Equatable {
    var glyphRange: Range<Int>
    // Deleted source slots remain in the line for layout and source queries.
    // Only runs with a filtered public collection need an index projection.
    var glyphIndices: [Int]?
    var attributes: _TextAttributeValues
    var style: _ResolvedTextRunAttributes
}

fileprivate struct _TextLayoutLineStorage {
    var glyphs: [ResolvedTextSource.Glyph]
    var runs: [_TextLayoutRunStorage]
    var origin: CGPoint
    var width: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
    var sourceStart: ResolvedTextSource.Glyph?
}

fileprivate final class _TextLayoutStorage {
    var source: ResolvedTextSource
    var lines: [_TextLayoutLineStorage]
    var origin: CGPoint
    var layoutDirection: LayoutDirection
    var isTruncated: Bool
    // Shaping ranges use scalar offsets; public character indices use UTF-16.
    let utf16Indices: [Int]?

    init(
        source: ResolvedTextSource,
        lines: [_TextLayoutLineStorage],
        origin: CGPoint,
        layoutDirection: LayoutDirection,
        isTruncated: Bool
    ) {
        self.source = source
        self.lines = lines
        self.origin = origin
        self.layoutDirection = layoutDirection
        self.isTruncated = isTruncated
        var offsets: [Int]?
        var scalarIndex = 0
        var utf16Index = 0
        for run in source.runs {
            let text: String
            switch run {
            case let .text(_, value), let .attributedText(_, value, _), let .styledText(_, value, _, _):
                text = value
            case .attachment, .attributedAttachment, .styledAttachment:
                text = "\u{fffc}"
            }
            for scalar in text.unicodeScalars {
                let count = scalar.value > 0xffff ? 2 : 1
                if count == 2 && offsets == nil { offsets = Array(0...scalarIndex) }
                scalarIndex += 1
                utf16Index += count
                offsets?.append(utf16Index)
            }
        }
        self.utf16Indices = offsets
    }

    init(copying original: _TextLayoutStorage, shading: GraphicsContext.Shading) {
        source = original.source
        source.shading = shading
        lines = original.lines
        origin = original.origin
        layoutDirection = original.layoutDirection
        isTruncated = original.isTruncated
        utf16Indices = original.utf16Indices
    }

    func xOffsets(line index: Int) -> [CGFloat] {
        let glyphs = lines[index].glyphs
        var offsets = Array(repeating: CGFloat.zero, count: glyphs.count + 1)
        for glyphIndex in glyphs.indices {
            let glyph = glyphs[glyphIndex]
            let kerning = glyphIndex == glyphs.startIndex ? 0 : glyph.kerning.x
            offsets[glyphIndex + 1] = offsets[glyphIndex] + kerning + glyph.advance.width
        }
        return offsets
    }

    func bounds(line lineIndex: Int, glyphRange: Range<Int>) -> Text.Layout.TypographicBounds {
        guard !glyphRange.isEmpty else { return .init() }
        let line = lines[lineIndex]
        let scale = 1 / source.scaleFactor
        let offsets = xOffsets(line: lineIndex)
        let glyphs = line.glyphs[glyphRange]
        let ascent = glyphs.reduce(CGFloat.zero) { max($0, $1.ascender) } * scale
        let descent = -glyphs.reduce(CGFloat.zero) { min($0, $1.descender) } * scale
        // Run construction keeps one selected face and font request per range.
        let leading = (glyphs.first?.leading ?? 0) * scale
        let baselineOffset = glyphs.first?.baselineOffset ?? 0
        return Text.Layout.TypographicBounds(
            origin: CGPoint(
                x: offsets[glyphRange.lowerBound] * scale,
                y: -baselineOffset * scale
            ),
            width: (offsets[glyphRange.upperBound] - offsets[glyphRange.lowerBound]) * scale,
            ascent: ascent,
            descent: descent,
            leading: leading
        )
    }

    func lineGlyphs(line lineIndex: Int, glyphRange: Range<Int>) -> ResolvedTextSource.LineGlyphs? {
        guard !glyphRange.isEmpty else { return nil }
        let line = lines[lineIndex]
        var glyphs = Array(line.glyphs[glyphRange])
        glyphs[0].kerning = .zero
        let ascent = line.ascent * source.scaleFactor
        let descender = -line.descent * source.scaleFactor
        let width = glyphs.enumerated().reduce(CGFloat.zero) { partial, item in
            partial + item.element.advance.width + (item.offset == 0 ? 0 : item.element.kerning.x)
        }
        return ResolvedTextSource.LineGlyphs(
            glyphs: glyphs,
            ascender: ascent,
            descender: descender,
            width: width
        )
    }
}

fileprivate struct _TextLayoutLine {
    var storage: _TextLayoutStorage
    var index: Int
    var reserved: Int = 0
}

fileprivate final class _TextLayoutLineReference {
    let storage: _TextLayoutStorage
    let index: Int

    init(storage: _TextLayoutStorage, index: Int) {
        self.storage = storage
        self.index = index
    }
}

extension Text {
    public struct Layout: RandomAccessCollection, Equatable {
        private var lines: [Line]
        public var isTruncated: Bool
        private var numberOfLines: Int

        init(lines: [Line], isTruncated: Bool, numberOfLines: Int) {
            self.lines = lines
            self.isTruncated = isTruncated
            self.numberOfLines = numberOfLines
        }

        fileprivate init(storage: _TextLayoutStorage) {
            self.init(
                lines: storage.lines.indices.map { index in
                    Line(
                        line: _TextLayoutLine(storage: storage, index: index),
                        lineIndex: index,
                        origin: storage.lines[index].origin,
                        drawingOptions: []
                    )
                },
                isTruncated: storage.isTruncated,
                numberOfLines: storage.lines.count
            )
        }

        public var startIndex: Int { 0 }
        public var endIndex: Int { lines.count }

        public subscript(index: Int) -> Line {
            precondition(indices.contains(index), "Text.Layout index out of range")
            return lines[index]
        }

        public static func == (lhs: Layout, rhs: Layout) -> Bool {
            lhs.lines == rhs.lines &&
                lhs.isTruncated == rhs.isTruncated &&
                lhs.numberOfLines == rhs.numberOfLines
        }

        mutating func truncateLast(_ suffix: Line, width: CGFloat) {
            guard var last = lines.last, let token = last.truncationToken else { return }
            let tokenWidth = token.typographicBounds.width
            let suffixWidth = suffix.typographicBounds.width
            let available = Swift.max(width - tokenWidth - suffixWidth, 0)
            let bodyWidth = last.typographicBounds.width - last.trailingWhitespaceWidth
            let alignment = last.lastRunAttributes?.paragraphStyle?.horizontalAlignment
                .textAlignment(for: last._line.storage.layoutDirection) ?? .leading
            let factor: CGFloat = alignment == .center ? 0.5 : alignment == .trailing ? 1 : 0
            var suffix = suffix
            if bodyWidth > available {
                guard var replacement = last.truncated(to: available, token: token) else { return }
                let used = replacement.typographicBounds.width - replacement.trailingWhitespaceWidth + suffixWidth
                replacement.origin = CGPoint(x: (width - used) * factor, y: last.origin.y)
                suffix.origin = CGPoint(x: replacement.origin.x + replacement.typographicBounds.width,
                                        y: last.origin.y)
                lines.removeLast()
                lines.append(replacement)
                lines.append(suffix)
            } else {
                let used = bodyWidth + tokenWidth + suffixWidth
                last.origin.x = (width - used) * factor
                var token = token
                token.origin = CGPoint(x: last.origin.x + bodyWidth, y: last.origin.y)
                suffix.origin = CGPoint(x: token.origin.x + tokenWidth, y: last.origin.y)
                lines.removeLast()
                lines.append(last)
                lines.append(token)
                lines.append(suffix)
            }
        }

        func placed(at origin: CGPoint, shading: GraphicsContext.Shading? = nil) -> Layout {
            var storageCopies: [ObjectIdentifier: _TextLayoutStorage] = [:]
            return Layout(lines: lines.map { line in
                var line = line
                line.origin.x += origin.x
                line.origin.y += origin.y
                if let shading {
                    let original = line._line.storage
                    let key = ObjectIdentifier(original)
                    if storageCopies[key] == nil {
                        storageCopies[key] = _TextLayoutStorage(copying: original, shading: shading)
                    }
                    line._line.storage = storageCopies[key]!
                }
                return line
            }, isTruncated: isTruncated, numberOfLines: numberOfLines)
        }

        func glyphAtoms() -> [ResolvedTextSource.GlyphAtom] {
            lines.flatMap { line -> [ResolvedTextSource.GlyphAtom] in
                let storage = line._line.storage
                let index = line._line.index
                guard var glyphs = storage.lineGlyphs(line: index,
                    glyphRange: storage.lines[index].glyphs.indices) else { return [] }
                glyphs.originX = line.origin.x * storage.source.scaleFactor
                glyphs.originY = (line.origin.y - storage.lines[index].ascent) * storage.source.scaleFactor
                return storage.source.glyphAtoms(lineGlyphs: [glyphs], in: .zero)
            }
        }

        public struct CharacterIndex: Comparable, Hashable, Strideable, Sendable {
            var value: Int

            init(value: Int) { self.value = value }

            public static func < (lhs: CharacterIndex, rhs: CharacterIndex) -> Bool {
                lhs.value < rhs.value
            }

            public func advanced(by n: Int) -> CharacterIndex {
                CharacterIndex(value: value + n)
            }

            public func distance(to other: CharacterIndex) -> Int {
                other.value - value
            }
        }

        public struct TypographicBounds: Equatable, Sendable {
            public var origin: CGPoint
            public var width: CGFloat
            public var ascent: CGFloat
            public var descent: CGFloat
            public var leading: CGFloat

            public init() {
                origin = .zero
                (width, ascent, descent, leading) = (0, 0, 0, 0)
            }

            fileprivate init(
                origin: CGPoint,
                width: CGFloat,
                ascent: CGFloat,
                descent: CGFloat,
                leading: CGFloat
            ) {
                self.origin = origin
                self.width = width
                self.ascent = ascent
                self.descent = descent
                self.leading = leading
            }

            public var rect: CGRect {
                CGRect(
                    x: origin.x,
                    y: origin.y - ascent,
                    width: width,
                    height: ascent + descent
                )
            }

            public static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.origin == rhs.origin &&
                    lhs.width == rhs.width &&
                    lhs.ascent == rhs.ascent &&
                    lhs.descent == rhs.descent &&
                    lhs.leading == rhs.leading
            }
        }

        public struct Line: RandomAccessCollection, Equatable {
            fileprivate var _line: _TextLayoutLine
            public var origin: CGPoint
            var drawingOptions: DrawingOptions

            fileprivate init(
                line: _TextLayoutLine,
                lineIndex: Int,
                origin: CGPoint,
                drawingOptions: DrawingOptions
            ) {
                self._line = line
                precondition(line.index == lineIndex)
                self.origin = origin
                self.drawingOptions = drawingOptions
            }

            public var startIndex: Int { 0 }
            public var endIndex: Int { _line.storage.lines[_line.index].runs.count }

            public subscript(index: Int) -> Run {
                precondition(indices.contains(index), "Text.Layout.Line index out of range")
                return Run(
                    line: _TextLayoutLineReference(
                        storage: _line.storage,
                        index: _line.index
                    ),
                    index: index,
                    lineOrigin: origin,
                    baseDrawingOptions: drawingOptions,
                    layoutRenderer: _line.storage
                )
            }

            public var typographicBounds: TypographicBounds {
                let line = _line.storage.lines[_line.index]
                return TypographicBounds(
                    origin: origin,
                    width: line.width,
                    ascent: line.ascent,
                    descent: line.descent,
                    leading: 0
                )
            }

            private var attributeSource: ResolvedTextSource.Glyph? {
                let line = _line.storage.lines[_line.index]
                return line.sourceStart ?? line.glyphs.last
            }

            var lastRunAttributes: _ResolvedTextRunAttributes? { attributeSource?.style }

            fileprivate var trailingWhitespaceWidth: CGFloat {
                let glyphs = _line.storage.lines[_line.index].glyphs
                return glyphs.reversed().prefix { CharacterSet.whitespaces.contains($0.scalar) }
                    .reduce(0) { $0 + $1.advance.width + $1.kerning.x } / _line.storage.source.scaleFactor
            }

            fileprivate var truncationToken: Line? {
                guard let input = attributeSource else { return nil }
                let original = _line.storage.source
                var source = ResolvedTextSource(runs: [.styledText([input.face], "…", input.attributes, input.style)],
                    scaleFactor: original.scaleFactor, displayScale: original.displayScale)
                source.shading = original.shading
                guard var glyphs = source.unwrappedGlyphLines().first, !glyphs.glyphs.isEmpty else { return nil }
                for index in glyphs.glyphs.indices { glyphs.glyphs[index].isTruncationToken = true }
                glyphs.ascender = glyphs.glyphs.map(\.ascender).max() ?? 0
                glyphs.descender = glyphs.glyphs.map(\.descender).min() ?? 0
                return source.makeLayout(lineGlyphs: [glyphs], layoutDirection: _line.storage.layoutDirection).first
            }

            fileprivate func truncated(to width: CGFloat, token: Line) -> Line? {
                let source = _line.storage.source
                let tokenGlyphs = token._line.storage.lines[token._line.index].glyphs
                guard token.typographicBounds.width <= width else { return nil }
                let glyphs = _line.storage.lines[_line.index].glyphs
                let clusters = ResolvedTextSource.clusterRanges(in: glyphs)
                let offsets = _line.storage.xOffsets(line: _line.index)
                let tokenAdvance = token.typographicBounds.width * source.scaleFactor
                for count in stride(from: clusters.count, through: 0, by: -1) {
                    let end = count == 0 ? 0 : clusters[count - 1].upperBound
                    var tokenGlyphs = tokenGlyphs
                    if end > 0, let first = tokenGlyphs.first {
                        let previous = glyphs[end - 1]
                        if previous.face.isEqual(to: first.face) {
                            tokenGlyphs[0].kerning = first.face.kernAdvance(left: previous.scalar, right: first.scalar)
                        }
                    }
                    let advance = offsets[end] + tokenAdvance + (end == 0 ? 0 : tokenGlyphs[0].kerning.x)
                    guard advance <= width * source.scaleFactor else { continue }
                    var selected = Array(glyphs.prefix(end))
                    let index = selected.last?.sourceRange?.upperBound ?? glyphs.first?.characterIndex ?? 0
                    for i in tokenGlyphs.indices {
                        tokenGlyphs[i].characterIndex = index
                        tokenGlyphs[i].sourceRange = index..<(index + 1)
                    }
                    selected += tokenGlyphs
                    selected[0].kerning = .zero
                    let line = ResolvedTextSource.LineGlyphs(glyphs: selected,
                        ascender: selected.map(\.ascender).max() ?? 0,
                        descender: selected.map(\.descender).min() ?? 0, width: advance)
                    return source.makeLayout(lineGlyphs: [line], layoutDirection: _line.storage.layoutDirection).first
                }
                return nil
            }

            public static func == (lhs: Line, rhs: Line) -> Bool {
                lhs._line.storage === rhs._line.storage && lhs._line.index == rhs._line.index &&
                    lhs.origin == rhs.origin && lhs.drawingOptions == rhs.drawingOptions
            }
        }

        public struct Run: RandomAccessCollection, Equatable {
            fileprivate var line: _TextLayoutLineReference
            fileprivate var index: Int
            fileprivate var lineOrigin: CGPoint
            fileprivate var baseDrawingOptions: DrawingOptions
            fileprivate var layoutRenderer: _TextLayoutStorage

            var customAttributes: _TextAttributeValues {
                line.storage.lines[line.index].runs[index].attributes
            }

            var glyphRange: Range<Int> {
                line.storage.lines[line.index].runs[index].glyphRange
            }

            func glyphRange(for indices: Range<Int>) -> Range<Int> {
                precondition(
                    indices.lowerBound >= 0 &&
                        indices.upperBound <= endIndex
                )
                if let glyphIndices = line.storage.lines[line.index].runs[index].glyphIndices {
                    let lower = indices.lowerBound == glyphIndices.count
                        ? glyphRange.upperBound : glyphIndices[indices.lowerBound]
                    let upper = indices.isEmpty ? lower : glyphIndices[indices.upperBound - 1] + 1
                    return lower..<upper
                }
                let lower = glyphRange.lowerBound + indices.lowerBound
                let upper = glyphRange.lowerBound + indices.upperBound
                return lower..<upper
            }

            public var startIndex: Int { 0 }
            public var endIndex: Int {
                line.storage.lines[line.index].runs[index].glyphIndices?.count ?? glyphRange.count
            }

            public subscript(index: Int) -> RunSlice {
                self[index ..< index + 1]
            }

            public subscript(bounds: Range<Int>) -> RunSlice {
                precondition(bounds.lowerBound >= 0 && bounds.upperBound <= endIndex)
                return RunSlice(run: self, indices: bounds)
            }

            public subscript<T>(key: T.Type) -> T? where T: TextAttribute {
                line.storage.lines[line.index].runs[index].attributes.value(for: key)
            }

            public var layoutDirection: LayoutDirection { line.storage.layoutDirection }

            public var typographicBounds: TypographicBounds {
                var bounds = line.storage.bounds(
                    line: line.index,
                    glyphRange: glyphRange(for: startIndex..<endIndex)
                )
                bounds.origin.x += lineOrigin.x
                bounds.origin.y += lineOrigin.y
                return bounds
            }

            public var characterIndices: [CharacterIndex] {
                let indices = line.storage.lines[line.index].runs[index].glyphIndices
                return self.indices.map { ordinal in
                    let glyphIndex = indices?[ordinal] ?? glyphRange.lowerBound + ordinal
                    let index = line.storage.lines[line.index].glyphs[glyphIndex].characterIndex
                    return CharacterIndex(value: line.storage.utf16Indices?[index] ?? index)
                }
            }

            public static func == (lhs: Run, rhs: Run) -> Bool {
                lhs.line.storage === rhs.line.storage && lhs.line.index == rhs.line.index &&
                    lhs.index == rhs.index && lhs.lineOrigin == rhs.lineOrigin &&
                    lhs.baseDrawingOptions == rhs.baseDrawingOptions &&
                    lhs.layoutRenderer === rhs.layoutRenderer
            }

            fileprivate init(
                line: _TextLayoutLineReference,
                index: Int,
                lineOrigin: CGPoint,
                baseDrawingOptions: DrawingOptions,
                layoutRenderer: _TextLayoutStorage
            ) {
                self.line = line
                self.index = index
                self.lineOrigin = lineOrigin
                self.baseDrawingOptions = baseDrawingOptions
                self.layoutRenderer = layoutRenderer
            }
        }

        public struct RunSlice: RandomAccessCollection, Equatable {
            public var run: Run
            public var indices: Range<Int>

            public init(run: Run, indices: Range<Int>) {
                precondition(indices.lowerBound >= run.startIndex && indices.upperBound <= run.endIndex)
                self.run = run
                self.indices = indices
            }

            public var startIndex: Int { indices.lowerBound }
            public var endIndex: Int { indices.upperBound }

            public subscript(index: Int) -> RunSlice {
                self[index ..< index + 1]
            }

            public subscript(bounds: Range<Int>) -> RunSlice {
                precondition(bounds.lowerBound >= startIndex && bounds.upperBound <= endIndex)
                return RunSlice(run: run, indices: bounds)
            }

            public subscript<T>(key: T.Type) -> T? where T: TextAttribute { run[key] }

            public var typographicBounds: TypographicBounds {
                var bounds = run.line.storage.bounds(
                    line: run.line.index,
                    glyphRange: run.glyphRange(for: indices)
                )
                bounds.origin.x += run.lineOrigin.x
                bounds.origin.y += run.lineOrigin.y
                return bounds
            }

            public var characterIndices: [CharacterIndex] {
                Array(run.characterIndices[indices])
            }

            public static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.run == rhs.run && lhs.indices == rhs.indices
            }
        }

        public struct DrawingOptions: OptionSet {
            public let rawValue: UInt32
            public init(rawValue: UInt32) { self.rawValue = rawValue }
            public static var disablesSubpixelQuantization: DrawingOptions {
                DrawingOptions(rawValue: 1 << 0)
            }
        }
    }
}

extension Text.Layout.Decorations {
    private init(storage: _TextLayoutStorage, line: Int, origin: CGPoint, scale: CGFloat) {
        let value = storage.lines[line]
        segments = TextDecorationProducer.segments(glyphs: value.glyphs,
            runs: value.runs.map(\.glyphRange), origin: origin,
            glyphTransform: CGAffineTransform(scaleX: 1, y: -1),
            scaleFactor: storage.source.scaleFactor, scale: scale, displayScale: storage.source.displayScale,
            environment: storage.source.fontResolutionContext?.environment ?? EnvironmentValues()).map(\.segment)
    }

    init(line: Text.Layout.Line, scale: CGFloat) {
        self.init(storage: line._line.storage, line: line._line.index, origin: line.origin, scale: scale)
    }

    init(run: Text.Layout.Run, scale: CGFloat) {
        self.init(storage: run.line.storage, line: run.line.index, origin: run.lineOrigin, scale: scale)
        let bounds = run.typographicBounds.rect
        self = selecting(runs: run.index..<(run.index + 1), bounds: bounds.minX...bounds.maxX,
                         keepsStart: true, keepsEnd: true)
    }

    init(slice: Text.Layout.RunSlice, scale: CGFloat) {
        let run = slice.run
        self.init(storage: run.line.storage, line: run.line.index, origin: run.lineOrigin, scale: scale)
        // Empty selections carry a present zero rectangle, independently of origin.
        let bounds = slice.isEmpty ? CGRect.zero : slice.typographicBounds.rect
        self = selecting(runs: run.index..<(run.index + 1), bounds: bounds.minX...bounds.maxX,
                         keepsStart: slice.startIndex == run.startIndex, keepsEnd: slice.endIndex == run.endIndex)
    }
}

extension ResolvedTextSource {
    static func drawingRunRanges(in glyphs: [Glyph]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for index in glyphs.indices {
            let glyph = glyphs[index]
            if let last = ranges.indices.last {
                let first = glyphs[ranges[last].lowerBound]
                if Self.samePublicationRun(first, glyph) {
                    ranges[last] = ranges[last].lowerBound..<(index + 1)
                    continue
                }
            }
            ranges.append(index..<(index + 1))
        }
        return ranges
    }

    func makeLayout(
        in size: CGSize,
        layoutDirection: LayoutDirection,
        layoutProperties: TextLayoutProperties? = nil,
        origin: CGPoint = .zero
    ) -> Text.Layout {
        let width = max(size.width, 0) * scaleFactor
        let height = max(size.height, 0) * scaleFactor
        let maxWidth = width > CGFloat(Int.max)
            ? Int.max
            : Int(ceil(width))
        let lineGlyphs = makeGlyphs(
            maxWidth: maxWidth,
            maximumHeight: height,
            lineLimit: layoutProperties?.lineLimit,
            truncationMode: layoutProperties?.truncationMode ?? .tail
        )
        let isTruncated = lineGlyphs.contains { $0.isTruncated }
        return makeLayout(
            lineGlyphs: lineGlyphs,
            layoutDirection: layoutDirection,
            isTruncated: isTruncated,
            origin: origin
        )
    }

    func makeLayout(
        lineGlyphs: [LineGlyphs],
        layoutDirection: LayoutDirection,
        isTruncated: Bool = false,
        origin: CGPoint = .zero,
        usesLineStartAttributes: Bool = false
    ) -> Text.Layout {
        let scale = 1 / scaleFactor
        let lines = lineGlyphs.map { line -> _TextLayoutLineStorage in
            var runs: [_TextLayoutRunStorage] = []
            // Publication preserves the original run boundaries. A deleted
            // middle run can separate otherwise identical visible runs, and
            // its font still contributes to the already resolved line metrics.
            for range in Self.drawingRunRanges(in: line.glyphs) {
                var indices: [Int]?
                if range.contains(where: { line.glyphs[$0].glyphIndex == 65535 }) {
                    let published = range.filter {
                        line.glyphs[$0].glyphIndex != 65535 ||
                            line.publishedDeletedGlyphIndex == $0
                    }
                    if published.count != range.count { indices = published }
                }
                if indices?.isEmpty != true ||
                    (line.retainsEmptyLeadingPublicationRun && range.contains(0)) {
                    let input = line.glyphs[range.lowerBound]
                    runs.append(_TextLayoutRunStorage(glyphRange: range, glyphIndices: indices,
                        attributes: input.attributes, style: input.style))
                }
            }
            let sourceStart = usesLineStartAttributes ? line.sourceStart ?? line.glyphs.first ?? line.trailingBoundary : nil
            let trimsTrailingSpace = sourceStart?.style.paragraphStyle?.horizontalAlignment == .right
            let trailingSpace = trimsTrailingSpace ? line.glyphs.reversed()
                .prefix { CharacterSet.whitespaces.contains($0.scalar) }
                .reduce(0) { $0 + $1.advance.width + $1.kerning.x } : 0
            let result = _TextLayoutLineStorage(
                glyphs: line.glyphs,
                runs: runs,
                origin: CGPoint(x: origin.x + line.originX * scale, y: origin.y + line.baseline * scale),
                width: ((line.fragmentWidth ?? line.width) - trailingSpace) * scale,
                ascent: line.ascender * scale,
                descent: -line.descender * scale,
                sourceStart: sourceStart
            )
            return result
        }
        return Text.Layout(storage: _TextLayoutStorage(
            source: self,
            lines: lines,
            origin: origin,
            layoutDirection: layoutDirection,
            isTruncated: isTruncated
        ))
    }
}

extension GraphicsContext {
    public func draw(
        _ line: Text.Layout.Line,
        options: Text.Layout.DrawingOptions = []
    ) {
        for run in line {
            drawGlyphs(run[run.startIndex..<run.endIndex], options: options)
        }
        draw(Text.Layout.Decorations(line: line, scale: userToDeviceScale),
             shading: line._line.storage.source.shading)
    }

    public func draw(
        _ run: Text.Layout.Run,
        options: Text.Layout.DrawingOptions = []
    ) {
        drawGlyphs(run[run.startIndex..<run.endIndex], options: options)
        draw(Text.Layout.Decorations(run: run, scale: userToDeviceScale),
             shading: run.layoutRenderer.source.shading)
    }

    public func draw(
        _ slice: Text.Layout.RunSlice,
        options: Text.Layout.DrawingOptions = []
    ) {
        drawGlyphs(slice, options: options)
        draw(Text.Layout.Decorations(slice: slice, scale: userToDeviceScale),
             shading: slice.run.layoutRenderer.source.shading)
    }

    private func drawGlyphs(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions) {
        let run = slice.run
        var glyphRange = run.glyphRange(for: slice.indices)
        // A zero-length draw range selects the remaining glyphs in its run.
        // Decoration selection still uses the original slice bounds.
        if glyphRange.isEmpty {
            glyphRange = glyphRange.lowerBound..<run.glyphRange.upperBound
        }
        guard let lineGlyphs = run.line.storage.lineGlyphs(line: run.line.index, glyphRange: glyphRange) else {
            return
        }
        let bounds = run.line.storage.bounds(line: run.line.index, glyphRange: glyphRange)
        let sourceLine = run.line.storage.lines[run.line.index]
        let drawing = run.layoutRenderer.source.makeDrawing(lineGlyphs: [lineGlyphs], includesDecorations: false)
        let origin = CGPoint(
            x: run.lineOrigin.x + bounds.origin.x,
            y: run.lineOrigin.y - sourceLine.ascent
        )
        draw(
            drawing,
            in: CGRect(
                origin: origin,
                size: CGSize(
                    width: bounds.width,
                    height: sourceLine.ascent + sourceLine.descent
                )
            ),
            shading: run.layoutRenderer.source.shading,
            snapOrigin: !run.baseDrawingOptions.union(options).contains(.disablesSubpixelQuantization),
            // Preserve fractional line placement relative to the text origin.
            // Only an explicit edit of the public line origin moves that anchor.
            snappingOrigin: CGPoint(x: run.line.storage.origin.x + run.lineOrigin.x - sourceLine.origin.x,
                                    y: run.line.storage.origin.y + run.lineOrigin.y - sourceLine.origin.y),
            // Typographic slice bounds do not clip the glyph's ink.
            clipBounds: false
        )
    }
}

class TextRendererBoxBase {
    var environment: EnvironmentValues { fatalError("abstract TextRendererBoxBase") }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) { fatalError("abstract TextRendererBoxBase") }
    func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect { fatalError("abstract TextRendererBoxBase") }
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { fatalError("abstract TextRendererBoxBase") }
    var displayPadding: EdgeInsets { fatalError("abstract TextRendererBoxBase") }
}

private final class TextRendererBox<Renderer: TextRenderer>: TextRendererBoxBase {
    var renderer: Renderer
    override var environment: EnvironmentValues { values }
    private var values: EnvironmentValues

    init(renderer: Renderer, environment: EnvironmentValues) {
        self.renderer = renderer
        self.values = environment
    }

    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        context.copyOnWrite()
        context.environment = values
        renderer.draw(layout: layout, in: &context)
    }

    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect {
        CGRect(origin: .zero, size: size)
    }

    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        renderer.sizeThatFits(proposal: proposal, text: text)
    }

    override var displayPadding: EdgeInsets { renderer.displayPadding }
}

struct TextRendererInput: ViewInput {
    typealias Value = WeakAttribute<TextRendererBoxBase>
    static var defaultValue: Value { WeakAttribute() }

    static func valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs == rhs
    }
}

public struct _TextRendererViewModifier<Renderer: TextRenderer> {
    var renderer: Renderer

    init(renderer: Renderer) {
        self.renderer = renderer
    }

    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active _AGGraph context.")
        }
        var renderer = modifier[\.renderer]
        Renderer._makeAnimatable(value: &renderer, inputs: inputs.base)
        let environment = inputs.base.cachedEnvironment.value.environment
        let box: Attribute<TextRendererBoxBase> = graph.makeStatefulRule(
            MakeTextRenderer(renderer: renderer._attribute, environment: environment, tracker: _PropertyListTracker())
        )
        inputs[TextRendererInput.self] = WeakAttribute(box)
    }

    public typealias Body = Never

    private struct MakeTextRenderer: StatefulRule {
        typealias Value = TextRendererBoxBase

        var renderer: Attribute<Renderer>
        var environment: Attribute<EnvironmentValues>
        var tracker: _PropertyListTracker

        mutating func updateValue() {
            let values = environment.value
            if _AGGraph.currentStatefulOutput(Value.self) != nil,
               !_AGGraph.currentStatefulInputChanged(renderer.identifier),
               !tracker.hasDifferentUsedValues(values._plist) {
                return
            }
            tracker.reset()
            let trackedValues = EnvironmentValues(values._plist, tracker: tracker)
            _AGGraph.setStatefulOutput(TextRendererBox(
                renderer: renderer.value,
                environment: trackedValues
            ) as TextRendererBoxBase)
        }
    }
}

extension _TextRendererViewModifier: ViewInputsModifier, PrimitiveViewModifier {
}

extension View {
    public func textRenderer<T>(_ renderer: T) -> some View where T: TextRenderer {
        modifier(_TextRendererViewModifier(renderer: renderer))
    }
}
