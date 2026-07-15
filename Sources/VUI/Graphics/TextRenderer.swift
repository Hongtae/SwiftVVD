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

private final class _TextProxyStorage {
    var resolvedText: GraphicsContext.ResolvedText

    init(resolvedText: GraphicsContext.ResolvedText) {
        self.resolvedText = resolvedText
    }
}

public struct TextProxy {
    private var storage: _TextProxyStorage

    init(_ resolvedText: GraphicsContext.ResolvedText) {
        storage = _TextProxyStorage(resolvedText: resolvedText)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let text = storage.resolvedText
        if proposal == .zero { return .zero }
        if proposal.width == 0 {
            let measured = text.measure(maxWidth: 0, maxHeight: proposal.height)
            return CGSize(width: 0, height: measured.height)
        }
        if proposal == .infinity { return text.measure() }
        return text.measure(maxWidth: proposal.width, maxHeight: proposal.height)
    }
}

fileprivate struct _TextLayoutRunStorage: Equatable {
    var glyphRange: Range<Int>
    var attributes: _TextAttributeValues
}

fileprivate struct _TextLayoutLineStorage {
    var glyphs: [GraphicsContext.ResolvedText.Glyph]
    var runs: [_TextLayoutRunStorage]
    var origin: CGPoint
    var width: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
}

fileprivate final class _TextLayoutStorage {
    var source: GraphicsContext.ResolvedText
    var lines: [_TextLayoutLineStorage]
    var layoutDirection: LayoutDirection
    var isTruncated: Bool

    init(
        source: GraphicsContext.ResolvedText,
        lines: [_TextLayoutLineStorage],
        layoutDirection: LayoutDirection,
        isTruncated: Bool
    ) {
        self.source = source
        self.lines = lines
        self.layoutDirection = layoutDirection
        self.isTruncated = isTruncated
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
        return Text.Layout.TypographicBounds(
            origin: CGPoint(x: offsets[glyphRange.lowerBound] * scale, y: 0),
            width: (offsets[glyphRange.upperBound] - offsets[glyphRange.lowerBound]) * scale,
            ascent: ascent,
            descent: descent,
            leading: max(line.ascent + line.descent - ascent - descent, 0)
        )
    }

    func lineGlyphs(line lineIndex: Int, glyphRange: Range<Int>) -> GraphicsContext.ResolvedText.LineGlyphs? {
        guard !glyphRange.isEmpty else { return nil }
        let line = lines[lineIndex]
        var glyphs = Array(line.glyphs[glyphRange])
        glyphs[0].kerning = .zero
        let ascent = glyphs.reduce(CGFloat.zero) { max($0, $1.ascender) }
        let descender = glyphs.reduce(CGFloat.zero) { min($0, $1.descender) }
        let width = glyphs.enumerated().reduce(CGFloat.zero) { partial, item in
            partial + item.element.advance.width + (item.offset == 0 ? 0 : item.element.kerning.x)
        }
        return GraphicsContext.ResolvedText.LineGlyphs(
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
        private var lines: _TextLayoutStorage
        public var isTruncated: Bool
        private var numberOfLines: Int

        fileprivate init(storage: _TextLayoutStorage) {
            self.lines = storage
            self.isTruncated = storage.isTruncated
            self.numberOfLines = storage.lines.count
        }

        public var startIndex: Int { 0 }
        public var endIndex: Int { lines.lines.count }

        public subscript(index: Int) -> Line {
            precondition(indices.contains(index), "Text.Layout index out of range")
            let line = lines.lines[index]
            return Line(
                line: _TextLayoutLine(storage: lines, index: index),
                lineIndex: index,
                origin: line.origin,
                drawingOptions: []
            )
        }

        public static func == (lhs: Layout, rhs: Layout) -> Bool {
            lhs.lines === rhs.lines &&
                lhs.isTruncated == rhs.isTruncated &&
                lhs.numberOfLines == rhs.numberOfLines
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
        }

        public struct Line: RandomAccessCollection, Equatable {
            private var _line: _TextLayoutLine
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
                    origin: .zero,
                    width: line.width,
                    ascent: line.ascent,
                    descent: line.descent,
                    leading: 0
                )
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

            var glyphRange: Range<Int> {
                line.storage.lines[line.index].runs[index].glyphRange
            }

            public var startIndex: Int { 0 }
            public var endIndex: Int { glyphRange.count }

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
                line.storage.bounds(line: line.index, glyphRange: glyphRange)
            }

            public var characterIndices: [CharacterIndex] {
                let prefix = line.storage.lines[..<line.index].reduce(0) { $0 + $1.glyphs.count }
                return glyphRange.map { CharacterIndex(value: prefix + $0) }
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
                let base = run.glyphRange.lowerBound
                return run.line.storage.bounds(
                    line: run.line.index,
                    glyphRange: (base + indices.lowerBound)..<(base + indices.upperBound)
                )
            }

            public var characterIndices: [CharacterIndex] {
                Array(run.characterIndices[indices])
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

extension GraphicsContext.ResolvedText {
    func makeLayout(in size: CGSize, layoutDirection: LayoutDirection) -> Text.Layout {
        let width = max(size.width, 0) * scaleFactor
        let height = max(size.height, 0) * scaleFactor
        let maxWidth = width > CGFloat(Int.max) ? Int.max : Int(width)
        let maxHeight = height > CGFloat(Int.max) ? Int.max : Int(height)
        let lineGlyphs = makeGlyphs(maxWidth: maxWidth, maxHeight: maxHeight)
        let unbounded = makeGlyphs()
        let isTruncated = lineGlyphs.flatMap { $0.glyphs }.map { $0.scalar } !=
            unbounded.flatMap { $0.glyphs }.map { $0.scalar }
        return makeLayout(
            lineGlyphs: lineGlyphs,
            layoutDirection: layoutDirection,
            isTruncated: isTruncated
        )
    }

    func makeLayout(
        lineGlyphs: [LineGlyphs],
        layoutDirection: LayoutDirection,
        isTruncated: Bool = false
    ) -> Text.Layout {
        let scale = 1 / scaleFactor
        var baseline = CGFloat.zero
        let lines = lineGlyphs.map { line -> _TextLayoutLineStorage in
            baseline += line.ascender * scale
            var runs: [_TextLayoutRunStorage] = []
            for glyphIndex in line.glyphs.indices {
                let glyph = line.glyphs[glyphIndex]
                if let last = runs.indices.last,
                   runs[last].glyphRange.upperBound == glyphIndex,
                   runs[last].attributes == glyph.attributes,
                   line.glyphs[runs[last].glyphRange.lowerBound].face.isEqual(to: glyph.face) {
                    runs[last].glyphRange = runs[last].glyphRange.lowerBound..<(glyphIndex + 1)
                } else {
                    runs.append(_TextLayoutRunStorage(
                        glyphRange: glyphIndex..<(glyphIndex + 1),
                        attributes: glyph.attributes
                    ))
                }
            }
            let result = _TextLayoutLineStorage(
                glyphs: line.glyphs,
                runs: runs,
                origin: CGPoint(x: 0, y: baseline),
                width: line.width * scale,
                ascent: line.ascender * scale,
                descent: -line.descender * scale
            )
            baseline += -line.descender * scale
            return result
        }
        return Text.Layout(storage: _TextLayoutStorage(
            source: self,
            lines: lines,
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
            draw(run, options: options)
        }
    }

    public func draw(
        _ run: Text.Layout.Run,
        options: Text.Layout.DrawingOptions = []
    ) {
        draw(run[run.startIndex..<run.endIndex], options: options)
    }

    public func draw(
        _ slice: Text.Layout.RunSlice,
        options: Text.Layout.DrawingOptions = []
    ) {
        let run = slice.run
        let base = run.glyphRange.lowerBound
        let glyphRange = (base + slice.indices.lowerBound)..<(base + slice.indices.upperBound)
        guard let lineGlyphs = run.line.storage.lineGlyphs(line: run.line.index, glyphRange: glyphRange) else {
            return
        }
        let bounds = run.line.storage.bounds(line: run.line.index, glyphRange: glyphRange)
        let drawing = run.layoutRenderer.source.makeDrawing(lineGlyphs: [lineGlyphs])
        let origin = CGPoint(
            x: run.lineOrigin.x + bounds.origin.x,
            y: run.lineOrigin.y - bounds.ascent
        )
        draw(
            drawing,
            in: CGRect(origin: origin, size: CGSize(width: bounds.width, height: bounds.ascent + bounds.descent)),
            shading: run.layoutRenderer.source.shading,
            snapOrigin: !run.baseDrawingOptions.union(options).contains(.disablesSubpixelQuantization)
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
    typealias Value = Attribute<TextRendererBoxBase>?
    static var defaultValue: Value { nil }

    static func valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs?.identifier == rhs?.identifier
    }
}

public struct _TextRendererViewModifier<Renderer: TextRenderer>: ViewModifier {
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
        inputs[TextRendererInput.self] = box
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

extension _TextRendererViewModifier: _ViewInputsModifier {
}

extension View {
    public func textRenderer<T>(_ renderer: T) -> some View where T: TextRenderer {
        modifier(_TextRendererViewModifier(renderer: renderer))
    }
}
