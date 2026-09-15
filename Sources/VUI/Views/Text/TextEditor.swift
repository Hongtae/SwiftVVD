//
//  File: TextEditor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct TextEditor: View {
    enum Storage {
        case string((Binding<String>, Binding<TextSelection?>?))
    }

    @Environment(\.scrollContentBackground)
    var _contentBackground
    var storage: Storage

    public init(text: Binding<String>) {
        storage = .string((text, nil))
    }

    public init(
        text: Binding<String>,
        selection: Binding<TextSelection?>
    ) {
        storage = .string((text, selection))
    }

    init(configuration: TextEditorStyleConfiguration) {
        storage = configuration.storage
    }

    public var body: some View {
        ResolvedTextEditorStyle(
            configuration: TextEditorStyleConfiguration(storage: storage)
        )
    }
}

struct ResolvedTextEditorStyle: StyleableView {
    typealias Configuration = TextEditorStyleConfiguration

    var configuration: TextEditorStyleConfiguration

    var body: some View {
        TextEditor(configuration: configuration)
    }

    typealias DefaultStyleModifier =
        TextEditorStyleModifier<AutomaticTextEditorStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        TextEditorStyleModifier(style: AutomaticTextEditorStyle())
    }
}

struct TextEditorInputState: Equatable {
    var compositionRange: Range<Int>?
    var pendingCompositionRange: Range<Int>?
    var caretOffset = 0
    var selectionRange: Range<Int>?
    var selectionAffinity: TextSelectionAffinity = .automatic
    var isFocused = false
    var preferredHorizontalOffset: CGFloat?
    var blinkResetID = 0

    var selectionOffsets: Range<Int> {
        selectionRange ?? caretOffset..<caretOffset
    }

    var selectionAnchor: Int {
        guard let selectionRange else { return caretOffset }
        return caretOffset <= selectionRange.lowerBound
            ? selectionRange.upperBound
            : selectionRange.lowerBound
    }

    var hasSelection: Bool {
        selectionRange?.isEmpty == false
    }

    func selectedText(in text: String) -> String? {
        guard let selectionRange, !selectionRange.isEmpty else { return nil }
        let lower = text.index(
            text.startIndex,
            offsetBy: min(max(selectionRange.lowerBound, 0), text.count)
        )
        let upper = text.index(
            text.startIndex,
            offsetBy: min(max(selectionRange.upperBound, 0), text.count)
        )
        return String(text[lower..<upper])
    }

    mutating func setFocused(_ focused: Bool, text: String) {
        isFocused = focused
        finalizeComposition()
        preferredHorizontalOffset = nil
        if focused {
            caretOffset = text.count
            selectionRange = nil
            selectionAffinity = .upstream
            resetCaretBlink()
        } else {
            clamp(to: text)
        }
    }

    mutating func finalizeComposition() {
        compositionRange = nil
        pendingCompositionRange = nil
    }

    mutating func setSelection(
        _ selection: TextSelection,
        text: String
    ) -> Bool {
        let offsets: Range<Int>
        switch selection.indices {
        case .selection(let range):
            offsets = text.distance(
                from: text.startIndex,
                to: range.lowerBound
            )..<text.distance(
                from: text.startIndex,
                to: range.upperBound
            )
        case .multiSelection:
            return false
        }
        return setSelection(
            offsets,
            affinity: selection.affinity,
            text: text
        )
    }

    @discardableResult
    mutating func setSelection(
        _ offsets: Range<Int>,
        affinity: TextSelectionAffinity,
        text: String
    ) -> Bool {
        setSelection(
            anchor: offsets.lowerBound,
            extent: offsets.upperBound,
            affinity: affinity,
            text: text
        )
    }

    @discardableResult
    mutating func setSelection(
        anchor: Int,
        extent: Int,
        affinity: TextSelectionAffinity,
        text: String
    ) -> Bool {
        let anchor = min(max(anchor, 0), text.count)
        let extent = min(max(extent, 0), text.count)
        let lower = min(anchor, extent)
        let upper = max(anchor, extent)
        let oldOffsets = selectionOffsets
        let oldAffinity = selectionAffinity
        caretOffset = extent
        selectionRange = lower == upper ? nil : lower..<upper
        selectionAffinity = affinity
        finalizeComposition()
        preferredHorizontalOffset = nil
        if oldOffsets != selectionOffsets || oldAffinity != affinity {
            resetCaretBlink()
            return true
        }
        return false
    }

    mutating func collapseSelection(
        to offset: Int,
        affinity: TextSelectionAffinity,
        text: String
    ) {
        _ = setSelection(
            offset..<offset,
            affinity: affinity,
            text: text
        )
    }

    func textSelection(in text: String) -> TextSelection {
        let offsets = selectionOffsets
        let lower = text.index(
            text.startIndex,
            offsetBy: min(max(offsets.lowerBound, 0), text.count)
        )
        let upper = text.index(
            text.startIndex,
            offsetBy: min(max(offsets.upperBound, 0), text.count)
        )
        var selection = TextSelection(range: lower..<upper)
        selection.affinity = selectionAffinity
        return selection
    }

    mutating func replaceComposition(
        with replacement: String,
        in text: inout String
    ) -> Bool {
        clamp(to: text)

        if replacement.isEmpty {
            if let compositionRange {
                pendingCompositionRange = compositionRange
                self.compositionRange = nil
                caretOffset = compositionRange.upperBound
                selectionRange = nil
                selectionAffinity = .upstream
                preferredHorizontalOffset = nil
                resetCaretBlink()
            }
            return false
        }

        let range = compositionRange
            ?? pendingCompositionRange
            ?? selectionOffsets
        replace(range, with: replacement, in: &text)
        let inserted = range.lowerBound..<(range.lowerBound + replacement.count)
        compositionRange = inserted
        pendingCompositionRange = nil
        caretOffset = inserted.upperBound
        selectionRange = nil
        selectionAffinity = .upstream
        preferredHorizontalOffset = nil
        resetCaretBlink()
        return true
    }

    mutating func handleTextInput(
        _ input: String,
        text: inout String
    ) -> Bool {
        clamp(to: text)
        let replacementRange = compositionRange
            ?? pendingCompositionRange
            ?? selectionOffsets
        compositionRange = nil
        pendingCompositionRange = nil
        selectionRange = replacementRange.isEmpty ? nil : replacementRange
        caretOffset = replacementRange.upperBound

        switch input {
        case "\u{1B}":
            return false
        case "\u{8}", "\u{7F}":
            if removeSelection(from: &text) {
                selectionAffinity = .downstream
                preferredHorizontalOffset = nil
                resetCaretBlink()
                return true
            }
            guard caretOffset > 0 else { return false }
            let end = text.index(text.startIndex, offsetBy: caretOffset)
            let start = text.index(before: end)
            text.removeSubrange(start..<end)
            caretOffset -= 1
            selectionAffinity = .downstream
            preferredHorizontalOffset = nil
            resetCaretBlink()
            return true
        case "\u{F728}":
            if removeSelection(from: &text) {
                selectionAffinity = .downstream
                preferredHorizontalOffset = nil
                resetCaretBlink()
                return true
            }
            guard caretOffset < text.count else { return false }
            let start = text.index(text.startIndex, offsetBy: caretOffset)
            let end = text.index(after: start)
            text.removeSubrange(start..<end)
            selectionAffinity = .downstream
            preferredHorizontalOffset = nil
            resetCaretBlink()
            return true
        default:
            guard !input.isEmpty else { return false }
            _ = removeSelection(from: &text)
            let normalized = input
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let index = text.index(text.startIndex, offsetBy: caretOffset)
            text.insert(contentsOf: normalized, at: index)
            caretOffset += normalized.count
            selectionRange = nil
            selectionAffinity = normalized.last == "\n"
                ? .downstream
                : .upstream
            preferredHorizontalOffset = nil
            resetCaretBlink()
            return true
        }
    }

    mutating func handleKeyDown(
        _ key: VirtualKey,
        modifiers: KeyboardModifierFlags,
        text: String,
        layout: TextEditorSelectionLayout,
        viewportHeight: CGFloat
    ) -> Bool {
        clamp(to: text)
        let unsupported: KeyboardModifierFlags = [
            .control,
            .option,
            .command,
        ]
        guard modifiers.intersection(unsupported).isEmpty else { return false }

        let extendsSelection = modifiers.contains(.shift)
        let anchor = selectionAnchor
        let extent: Int
        let affinity: TextSelectionAffinity
        var verticalPreferredOffset: CGFloat?

        switch key {
        case .left:
            if !extendsSelection, let selectionRange {
                extent = selectionRange.lowerBound
            } else {
                extent = max(caretOffset - 1, 0)
            }
            affinity = .downstream
            preferredHorizontalOffset = nil
        case .right:
            if !extendsSelection, let selectionRange {
                extent = selectionRange.upperBound
            } else {
                extent = min(caretOffset + 1, text.count)
            }
            affinity = .upstream
            preferredHorizontalOffset = nil
        case .home:
            extent = layout.visualLineRange(
                containing: caretOffset,
                affinity: selectionAffinity
            ).lowerBound
            affinity = .upstream
            preferredHorizontalOffset = nil
        case .end:
            extent = layout.visualLineRange(
                containing: caretOffset,
                affinity: selectionAffinity
            ).upperBound
            affinity = .downstream
            preferredHorizontalOffset = nil
        case .up, .down, .pageUp, .pageDown:
            let direction: Int
            switch key {
            case .up: direction = -1
            case .down: direction = 1
            case .pageUp: direction = -layout.pageLineCount(viewportHeight)
            case .pageDown: direction = layout.pageLineCount(viewportHeight)
            default: direction = 0
            }
            let movement = layout.verticalMovement(
                from: caretOffset,
                affinity: selectionAffinity,
                preferredX: preferredHorizontalOffset,
                lineDelta: direction
            )
            extent = movement.offset
            verticalPreferredOffset = movement.preferredX
            preferredHorizontalOffset = movement.preferredX
            affinity = .downstream
        default:
            return false
        }

        if extendsSelection {
            _ = setSelection(
                anchor: anchor,
                extent: extent,
                affinity: affinity,
                text: text
            )
            if let verticalPreferredOffset {
                preferredHorizontalOffset = verticalPreferredOffset
            }
        } else {
            caretOffset = extent
            selectionRange = nil
            selectionAffinity = affinity
            finalizeComposition()
            resetCaretBlink()
        }
        return true
    }

    func wordRange(at offset: Int, in text: String) -> Range<Int>? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        let offset = min(max(offset, 0), characters.count)
        let seed: Int
        if offset < characters.count,
           Self.isWordCharacter(characters[offset]) {
            seed = offset
        } else if offset > 0,
                  Self.isWordCharacter(characters[offset - 1]) {
            seed = offset - 1
        } else {
            return nil
        }

        var lower = seed
        var upper = seed + 1
        while lower > 0, Self.isWordCharacter(characters[lower - 1]) {
            lower -= 1
        }
        while upper < characters.count,
              Self.isWordCharacter(characters[upper]) {
            upper += 1
        }
        return lower..<upper
    }

    func logicalLineRange(at offset: Int, in text: String) -> Range<Int> {
        let characters = Array(text)
        let offset = min(max(offset, 0), characters.count)
        var lower = offset
        while lower > 0, !Self.isNewline(characters[lower - 1]) {
            lower -= 1
        }
        var upper = offset
        while upper < characters.count, !Self.isNewline(characters[upper]) {
            upper += 1
        }
        if upper < characters.count {
            upper += 1
        }
        return lower..<upper
    }

    func transformationRange(in text: String) -> Range<Int>? {
        if let selectionRange, !selectionRange.isEmpty {
            return selectionRange
        }
        return wordRange(at: caretOffset, in: text)
    }

    @discardableResult
    mutating func transformSelection(
        in text: inout String,
        transform: (String) -> String
    ) -> Bool {
        guard let range = transformationRange(in: text) else { return false }
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        let replacement = transform(String(text[lower..<upper]))
        text.replaceSubrange(lower..<upper, with: replacement)
        caretOffset = range.lowerBound + replacement.count
        selectionRange = range.lowerBound..<caretOffset
        selectionAffinity = .upstream
        finalizeComposition()
        preferredHorizontalOffset = nil
        resetCaretBlink()
        return true
    }

    @discardableResult
    mutating func replaceSelection(
        with replacement: String,
        in text: inout String
    ) -> Bool {
        clamp(to: text)
        let range = selectionOffsets
        guard !range.isEmpty || !replacement.isEmpty else { return false }
        replace(range, with: replacement, in: &text)
        caretOffset = range.lowerBound + replacement.count
        selectionRange = nil
        selectionAffinity = replacement.last == "\n"
            ? .downstream
            : (replacement.isEmpty ? .downstream : .upstream)
        finalizeComposition()
        preferredHorizontalOffset = nil
        resetCaretBlink()
        return true
    }

    mutating func synchronize(with text: String) {
        clamp(to: text)
        finalizeComposition()
        preferredHorizontalOffset = nil
    }

    private mutating func replace(
        _ range: Range<Int>,
        with replacement: String,
        in text: inout String
    ) {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        text.replaceSubrange(lower..<upper, with: replacement)
    }

    private mutating func removeSelection(from text: inout String) -> Bool {
        guard let selectionRange, !selectionRange.isEmpty else { return false }
        replace(selectionRange, with: "", in: &text)
        caretOffset = selectionRange.lowerBound
        self.selectionRange = nil
        return true
    }

    private mutating func clamp(to text: String) {
        caretOffset = min(max(caretOffset, 0), text.count)
        selectionRange = Self.clamped(selectionRange, to: text.count)
        compositionRange = Self.clamped(compositionRange, to: text.count)
        pendingCompositionRange = Self.clamped(
            pendingCompositionRange,
            to: text.count
        )
    }

    private mutating func resetCaretBlink() {
        blinkResetID &+= 1
    }

    private static func clamped(
        _ range: Range<Int>?,
        to count: Int
    ) -> Range<Int>? {
        guard let range else { return nil }
        let lower = min(max(range.lowerBound, 0), count)
        let upper = min(max(range.upperBound, lower), count)
        return lower..<upper
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func isNewline(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.newlines.contains($0)
        }
    }
}

struct TextEditorSelectionLayout: Equatable {
    static let trailingSentinel = "\u{200B}"

    struct Line: Equatable {
        var characterRange: Range<Int>
        var logicalSelectionEnd: Int
        var characterOffsets: [CGFloat]
        var frame: CGRect

        func x(at offset: Int) -> CGFloat {
            let offset = min(
                max(offset, characterRange.lowerBound),
                characterRange.upperBound
            )
            return characterOffsets[offset - characterRange.lowerBound]
        }

        func characterOffset(atX x: CGFloat) -> Int {
            guard characterRange.isEmpty == false else {
                return characterRange.lowerBound
            }
            for index in 0..<(characterOffsets.count - 1) {
                let midpoint = (
                    characterOffsets[index] + characterOffsets[index + 1]
                ) * 0.5
                if x < midpoint {
                    return characterRange.lowerBound + index
                }
            }
            return characterRange.upperBound
        }
    }

    var lines: [Line]
    var contentSize: CGSize

    static var empty: TextEditorSelectionLayout {
        TextEditorSelectionLayout(lines: [], contentSize: .zero)
    }

    static func displayText(for text: String) -> String {
        text + trailingSentinel
    }

    func lineIndex(
        containing offset: Int,
        affinity: TextSelectionAffinity
    ) -> Int {
        guard !lines.isEmpty else { return 0 }
        let candidates = lines.indices.filter {
            let range = lines[$0].characterRange
            return offset >= range.lowerBound && offset <= range.upperBound
        }
        guard let first = candidates.first else {
            return offset <= lines[0].characterRange.lowerBound
                ? lines.startIndex
                : lines.index(before: lines.endIndex)
        }
        guard candidates.count > 1 else { return first }
        return affinity == .upstream ? first : candidates.last!
    }

    func visualLineRange(
        containing offset: Int,
        affinity: TextSelectionAffinity
    ) -> Range<Int> {
        guard !lines.isEmpty else { return 0..<0 }
        return lines[lineIndex(containing: offset, affinity: affinity)]
            .characterRange
    }

    func characterOffset(at point: CGPoint) -> Int {
        guard !lines.isEmpty else { return 0 }
        let line: Line
        if point.y <= lines[0].frame.minY {
            line = lines[0]
        } else if point.y >= lines[lines.count - 1].frame.maxY {
            line = lines[lines.count - 1]
        } else {
            line = lines.first {
                point.y >= $0.frame.minY && point.y < $0.frame.maxY
            } ?? lines[lines.count - 1]
        }
        return line.characterOffset(atX: point.x)
    }

    func caretX(
        at offset: Int,
        affinity: TextSelectionAffinity
    ) -> CGFloat {
        guard !lines.isEmpty else { return 0 }
        let line = lines[lineIndex(containing: offset, affinity: affinity)]
        return line.x(at: offset)
    }

    func caretRect(
        at offset: Int,
        affinity: TextSelectionAffinity,
        width: CGFloat = 1
    ) -> CGRect {
        guard !lines.isEmpty else { return .zero }
        let line = lines[lineIndex(containing: offset, affinity: affinity)]
        return CGRect(
            x: line.x(at: offset),
            y: line.frame.minY,
            width: width,
            height: line.frame.height
        )
    }

    func selectionRects(for selection: Range<Int>) -> [CGRect] {
        guard !selection.isEmpty else { return [] }
        var result: [CGRect] = []
        for line in lines {
            let lower = max(selection.lowerBound, line.characterRange.lowerBound)
            let upper = min(selection.upperBound, line.characterRange.upperBound)
            if lower < upper {
                result.append(CGRect(
                    x: line.x(at: lower),
                    y: line.frame.minY,
                    width: max(line.x(at: upper) - line.x(at: lower), 1),
                    height: line.frame.height
                ))
            }
            if selection.upperBound > line.characterRange.upperBound,
               selection.lowerBound < line.logicalSelectionEnd,
               line.logicalSelectionEnd > line.characterRange.upperBound {
                result.append(CGRect(
                    x: line.x(at: line.characterRange.upperBound),
                    y: line.frame.minY,
                    width: 2,
                    height: line.frame.height
                ))
            }
        }
        return result
    }

    func verticalMovement(
        from offset: Int,
        affinity: TextSelectionAffinity,
        preferredX: CGFloat?,
        lineDelta: Int
    ) -> (offset: Int, preferredX: CGFloat) {
        guard !lines.isEmpty else { return (0, 0) }
        let sourceIndex = lineIndex(containing: offset, affinity: affinity)
        let x = preferredX ?? lines[sourceIndex].x(at: offset)
        let targetIndex = min(
            max(sourceIndex + lineDelta, lines.startIndex),
            lines.index(before: lines.endIndex)
        )
        return (lines[targetIndex].characterOffset(atX: x), x)
    }

    func pageLineCount(_ viewportHeight: CGFloat) -> Int {
        let averageHeight = lines.isEmpty
            ? 1
            : lines.reduce(CGFloat.zero) { $0 + $1.frame.height }
                / CGFloat(lines.count)
        return max(Int(viewportHeight / max(averageHeight, 1)), 1)
    }

    static func resolve(
        text: String,
        width: CGFloat,
        environment: EnvironmentValues,
        sceneResources: SceneResources
    ) -> TextEditorSelectionLayout {
        let context = GraphTextResolutionContext(
            environment: environment,
            sceneResources: sceneResources
        )
        guard let resolved = Text(verbatim: displayText(for: text))._resolve(
            context: context,
            referenceDate: Date()
        ) else {
            fatalError("TextEditor selection layout failed to resolve text")
        }

        let scale = resolved.scaleFactor
        let scaledWidth = max(width, 1) * scale
        let maxWidth = scaledWidth > CGFloat(Int.max)
            ? Int.max
            : Int(ceil(scaledWidth))
        let glyphLines = resolved.makeGlyphs(
            maxWidth: maxWidth,
            maxHeight: .max
        )
        let sourceMap = SourceMap(text: text)
        var y: CGFloat = 0
        var maximumWidth: CGFloat = 0
        var result: [Line] = []
        result.reserveCapacity(glyphLines.count)

        for glyphLine in glyphLines {
            let clusters = clusters(
                in: glyphLine,
                scale: scale,
                sourceMap: sourceMap
            )
            let start: Int
            let end: Int
            if let boundary = glyphLine.trailingBoundary?.sourceRange {
                start = clusters.first?.characterRange.lowerBound
                    ?? sourceMap.characterOffset(atOrBefore: boundary.lowerBound)
                end = sourceMap.characterOffset(atOrBefore: boundary.lowerBound)
            } else {
                start = clusters.first?.characterRange.lowerBound
                    ?? sourceMap.characterCount
                end = min(
                    clusters.last?.characterRange.upperBound
                        ?? sourceMap.characterCount,
                    sourceMap.characterCount
                )
            }
            let lower = min(start, end)
            let upper = max(start, end)
            var offsets = Array(
                repeating: CGFloat.nan,
                count: upper - lower + 1
            )
            offsets[0] = 0
            for cluster in clusters {
                let clusterLower = max(cluster.characterRange.lowerBound, lower)
                let clusterUpper = min(cluster.characterRange.upperBound, upper)
                guard clusterLower < clusterUpper else { continue }
                let count = clusterUpper - clusterLower
                for index in 0...count {
                    let progress = CGFloat(index) / CGFloat(count)
                    offsets[clusterLower - lower + index] =
                        cluster.minX + (cluster.maxX - cluster.minX) * progress
                }
            }
            var previous: CGFloat = 0
            for index in offsets.indices {
                if offsets[index].isFinite {
                    previous = offsets[index]
                } else {
                    offsets[index] = previous
                }
            }
            let height = max(glyphLine.height / scale, 1)
            let lineWidth = max(glyphLine.width / scale, offsets.last ?? 0)
            result.append(Line(
                characterRange: lower..<upper,
                logicalSelectionEnd: glyphLine.trailingBoundary == nil
                    ? upper
                    : min(upper + 1, sourceMap.characterCount),
                characterOffsets: offsets,
                frame: CGRect(x: 0, y: y, width: lineWidth, height: height)
            ))
            maximumWidth = max(maximumWidth, lineWidth)
            y += height
        }

        return TextEditorSelectionLayout(
            lines: result,
            contentSize: CGSize(width: maximumWidth, height: y)
        )
    }

    private struct Cluster {
        var characterRange: Range<Int>
        var minX: CGFloat
        var maxX: CGFloat
    }

    private static func clusters(
        in line: ResolvedTextSource.LineGlyphs,
        scale: CGFloat,
        sourceMap: SourceMap
    ) -> [Cluster] {
        var result: [Cluster] = []
        var x: CGFloat = 0
        for range in ResolvedTextSource.clusterRanges(
            in: line.glyphs
        ) {
            let glyphs = line.glyphs[range]
            guard let first = glyphs.first else { continue }
            if range.lowerBound != line.glyphs.startIndex {
                x += first.kerning.x
            }
            let minX = x / scale
            var sourceLower = Int.max
            var sourceUpper = Int.min
            for (index, glyph) in glyphs.enumerated() {
                if index != 0 {
                    x += glyph.kerning.x
                }
                x += glyph.advance.width
                let sourceRange = glyph.sourceRange
                    ?? glyph.characterIndex..<(glyph.characterIndex + 1)
                sourceLower = min(sourceLower, sourceRange.lowerBound)
                sourceUpper = max(sourceUpper, sourceRange.upperBound)
            }
            let lower = sourceMap.characterOffset(atOrBefore: sourceLower)
            let upper = sourceMap.characterOffset(atOrAfter: sourceUpper)
            result.append(Cluster(
                characterRange: lower..<max(lower, upper),
                minX: minX,
                maxX: x / scale
            ))
        }
        return result
    }

    private struct SourceMap {
        var scalarOffsets: [Int]

        init(text: String) {
            scalarOffsets = [0]
            scalarOffsets.reserveCapacity(text.count + 1)
            var offset = 0
            for character in text {
                offset += character.unicodeScalars.count
                scalarOffsets.append(offset)
            }
        }

        var characterCount: Int { scalarOffsets.count - 1 }

        func characterOffset(atOrBefore scalarOffset: Int) -> Int {
            var result = 0
            for (index, offset) in scalarOffsets.enumerated() {
                guard offset <= scalarOffset else { break }
                result = index
            }
            return min(result, characterCount)
        }

        func characterOffset(atOrAfter scalarOffset: Int) -> Int {
            for (index, offset) in scalarOffsets.enumerated()
            where offset >= scalarOffset {
                return min(index, characterCount)
            }
            return characterCount
        }
    }
}

final class TextEditorSelectionLayoutStorage {
    var value = TextEditorSelectionLayout.empty
}

struct TextEditorRenderer: TextRenderer {
    typealias AnimatableData = EmptyAnimatableData

    var selectionLayout: TextEditorSelectionLayoutStorage
    var inputState: TextEditorInputState
    var drawsCaret: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if inputState.hasSelection {
            for rect in selectionLayout.value.selectionRects(
                for: inputState.selectionOffsets
            ) {
                context.fill(
                    Path(rect),
                    with: .color(Color.blue.opacity(0.35))
                )
            }
        }

        for line in layout {
            context.draw(line)
        }

        if let compositionRange = inputState.compositionRange {
            for rect in selectionLayout.value.selectionRects(
                for: compositionRange
            ) {
                context.fill(
                    Path(CGRect(
                        x: rect.minX,
                        y: max(rect.maxY - 1, rect.minY),
                        width: rect.width,
                        height: 1
                    )),
                    with: .color(.blue)
                )
            }
        }

        if drawsCaret, inputState.isFocused, !inputState.hasSelection {
            let rect = selectionLayout.value.caretRect(
                at: inputState.caretOffset,
                affinity: inputState.selectionAffinity
            )
            if !rect.isEmpty {
                context.fill(Path(rect), with: .color(.blue))
            }
        }
    }
}

struct TextEditorInputModifier: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var text: Binding<String>
    var selection: Binding<TextSelection?>?
    var selectionValue: TextSelection?
    var inputState: Binding<TextEditorInputState>
    var selectionLayout: TextEditorSelectionLayoutStorage
    var scrollables: WeakAttribute<[any Scrollable]>
    var contentInsets: EdgeInsets

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextEditorInputModifier._makeView called outside AG context"
            )
        }

        var contentInputs = inputs
        contentInputs.preferences.keys.add(ScrollGeometryPreferenceKey.self)
        var outputs = body(_Graph(), contentInputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let scrollGeometry = outputs.preferences.reducedValue(
            for: ScrollGeometryPreferenceKey.self,
            in: graph
        )
        let childNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map(\.value)
        let children: Attribute<[ViewResponder]>
        if childNodes.isEmpty {
            children = graph.makeInput(value: [])
        } else if childNodes.count == 1 {
            children = Attribute(childNodes[0])
        } else {
            children = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for node in childNodes {
                    let value = Attribute<[ViewResponder]>(node).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let responder = graph.makeStatefulRule(
            TextEditorResponderFilter(
                modifier: modifier._attribute,
                environment: inputs.base.cachedEnvironment.value.environment,
                position: inputs.position,
                size: inputs.size,
                transform: inputs.transform,
                children: children,
                scrollGeometry: scrollGeometry.map(OptionalAttribute.init)
                    ?? OptionalAttribute(),
                responder: nil
            )
        )
        outputs.preferences.preferences.removeAll {
            $0.key == ViewRespondersKey.self
        }
        outputs.preferences.append(
            ViewRespondersKey.self,
            node: responder.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "TextEditorInputModifier._makeViewList called outside AG context"
            )
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private struct TextEditorResponderFilter: StatefulRule, RemovableAttribute {
    typealias Value = [ViewResponder]

    var modifier: Attribute<TextEditorInputModifier>
    var environment: Attribute<EnvironmentValues>
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var transform: Attribute<ViewTransform>
    var children: Attribute<[ViewResponder]>
    var scrollGeometry: OptionalAttribute<[ScrollGeometryState]>
    var responder: TextEditorResponder?

    mutating func updateValue() {
        let isInitial = !context.hasValue
        if responder == nil {
            responder = TextEditorResponder()
        }
        guard let responder else {
            fatalError("TextEditorResponderFilter failed to create responder")
        }

        let modifier = modifier.value
        let environment = environment.value
        responder.text = modifier.text
        responder.selection = modifier.selection
        responder.inputState = modifier.inputState
        responder.scrollGeometry = scrollGeometry.attribute?.value.first?
            .geometry ?? ScrollGeometry()
        responder.scrollables = modifier.scrollables
        responder.contentInsets = modifier.contentInsets
        responder.isEnabled = environment.isEnabled
        responder.isTextFieldCursorEnabled =
            environment.isTextFieldCursorEnabled
        responder.synchronizeTextValue()

        guard let viewGraph = _AGGraphContext.current?.context as? ViewGraph,
              let rendererHost = viewGraph.rendererHost else {
            fatalError(
                "TextEditorResponderFilter requires an active renderer host"
            )
        }
        let contentWidth = max(
            size.value.value.width
                - modifier.contentInsets.leading
                - modifier.contentInsets.trailing,
            0
        )
        let layout = TextEditorSelectionLayout.resolve(
            text: modifier.text.wrappedValue,
            width: contentWidth,
            environment: environment,
            sceneResources: rendererHost.sceneResources
        )
        responder.updateSelectionLayout(
            layout,
            text: modifier.text.wrappedValue,
            resolver: { text in
                TextEditorSelectionLayout.resolve(
                    text: text,
                    width: contentWidth,
                    environment: environment,
                    sceneResources: rendererHost.sceneResources
                )
            }
        )
        modifier.selectionLayout.value = layout
        responder.synchronizeSelection(modifier.selectionValue)
        responder.helper.update(
            data: (value: TrivialContentResponder(), changed: false),
            size: (
                value: size.value,
                changed: _AGGraph.currentStatefulInputChanged(size.identifier)
            ),
            position: (
                value: position.value,
                changed: _AGGraph.currentStatefulInputChanged(position.identifier)
            ),
            transform: (
                value: transform.value,
                changed: _AGGraph.currentStatefulInputChanged(transform.identifier)
            ),
            parent: responder
        )
        responder.updateChildren((
            value: children.value,
            changed: isInitial
                || _AGGraph.currentStatefulInputChanged(children.identifier)
        ))

        if !environment.isEnabled {
            responder.resetHoverEvents()
            (responder.host as? WindowController)?.resignTextInputFocus(
                responder
            )
        }
        _AGGraph.setStatefulOutput([responder])
    }

    static func willRemove(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextEditorResponderFilter.willRemove called outside AG context"
            )
        }
        var responder: TextEditorResponder?
        graph.mutateStatefulRule(attribute, as: Self.self) { rule in
            responder = rule.responder
        }
        guard let responder else { return }
        responder.resetHoverEvents()
        (responder.host as? WindowController)?.resignTextInputFocus(responder)
    }
}

final class TextEditorResponder: MultiViewResponder,
    ExclusiveResponderEventConsumer, TextInputResponder,
    TextEditingCommandResponder, HoverEventObserver {
    var helper = ContentResponderHelper<TrivialContentResponder>()
    var text: Binding<String>? {
        didSet {
            if text == nil {
                observedTextValue = nil
            } else if observedTextValue == nil {
                observedTextValue = text?.wrappedValue
            }
        }
    }
    var selection: Binding<TextSelection?>? {
        didSet {
            let location = selection.map { ObjectIdentifier($0.location) }
            if location != selectionLocation {
                selectionLocation = location
                selectionBindingValue = nil
                hasSelectionBindingValue = false
            }
        }
    }
    var inputState: Binding<TextEditorInputState>?
    var scrollGeometry = ScrollGeometry()
    var scrollables = WeakAttribute<[any Scrollable]>()
    var contentInsets = EdgeInsets()
    var selectionLayout = TextEditorSelectionLayout.empty
    var isEnabled = true
    var isTextFieldCursorEnabled = true {
        didSet {
            guard isTextFieldCursorEnabled != oldValue else { return }
            updateTextCursor()
        }
    }

    private var observedTextValue: String?
    private var selectionLocation: ObjectIdentifier?
    private var selectionBindingValue: TextSelection?
    private var hasSelectionBindingValue = false
    private var consumedKeyStreams: Set<KeyStream> = []
    private var cursorHoverEventIDs: Set<EventID> = []
    private var hasRequestedIBeamCursor = false
    private var pointerSelectionSession: (
        eventID: EventID,
        anchor: Int
    )?
    private var selectionLayoutText: String?
    private var selectionLayoutResolver:
        ((String) -> TextEditorSelectionLayout)?
    private struct KeyStream: Hashable {
        var deviceID: Int
        var key: VirtualKey
    }

    func updateSelectionLayout(
        _ layout: TextEditorSelectionLayout,
        text: String,
        resolver: @escaping (String) -> TextEditorSelectionLayout
    ) {
        selectionLayout = layout
        selectionLayoutText = text
        selectionLayoutResolver = resolver
    }

    func synchronizeTextValue() {
        guard let text else { return }
        let projectedValue = text.wrappedValue
        guard let observedTextValue else {
            self.observedTextValue = projectedValue
            return
        }
        guard observedTextValue != projectedValue else { return }
        self.observedTextValue = projectedValue
        guard inputState != nil else { return }
        Update.enqueueAction { [weak self] in
            guard let self,
                  self.text?.wrappedValue == projectedValue,
                  let inputState = self.inputState else {
                return
            }
            var state = inputState.wrappedValue
            state.synchronize(with: projectedValue)
            inputState.wrappedValue = state
            self.publishSelection(state, text: projectedValue)
        }
    }

    private func storeTextValue(_ value: String) {
        guard let text else { return }
        text.wrappedValue = value
        observedTextValue = text.wrappedValue
    }

    private func refreshSelectionLayout(for text: String) {
        guard selectionLayoutText != text,
              let selectionLayoutResolver else { return }
        selectionLayout = selectionLayoutResolver(text)
        selectionLayoutText = text
    }

    override var features: Features {
        [.platformViews, .gestures]
    }

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        isEnabled || options.contains(.allowDisabledViews)
            ? .include
            : .exclude
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .stop
        }
        return helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        isEnabled && (eventType == MouseEvent.self || eventType == TouchEvent.self)
    }

    func exclusivelyConsumes(_ event: any EventType) -> Bool {
        if let event = event as? MouseEvent {
            return event.button == .primary
        }
        return event is TouchEvent
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at _: Time
    ) -> GesturePhase<Void> {
        var result: GesturePhase<Void> = .possible(nil)
        for (eventID, event) in events.sorted(by: {
            $0.key.serial < $1.key.serial
        }) {
            let pointer: (
                phase: EventPhase,
                location: CGPoint,
                modifiers: EventModifiers,
                clickCount: Int
            )?
            if let event = event as? MouseEvent,
               event.button == .primary {
                pointer = (
                    event.phase,
                    event.globalLocation,
                    event.modifiers,
                    event.clickCount
                )
            } else if let event = event as? TouchEvent {
                pointer = (
                    event.phase,
                    event.globalLocation,
                    event.modifiers,
                    1
                )
            } else {
                pointer = nil
            }
            guard let pointer else { continue }

            switch pointer.phase {
            case .began:
                (host as? WindowController)?.focusTextInputResponder(self)
                if let offset = textOffset(atGlobalPoint: pointer.location) {
                    if pointer.modifiers.contains(.shift) {
                        let anchor = inputState?.wrappedValue.selectionAnchor
                            ?? offset
                        pointerSelectionSession = (eventID, anchor)
                        updatePointerSelection(anchor: anchor, extent: offset)
                    } else if pointer.clickCount == 2 {
                        pointerSelectionSession = nil
                        updatePointerWordSelection(at: offset)
                    } else if pointer.clickCount >= 3 {
                        pointerSelectionSession = nil
                        updatePointerLineSelection(at: offset)
                    } else {
                        pointerSelectionSession = (eventID, offset)
                        updatePointerSelection(anchor: offset, extent: offset)
                    }
                }
                result = .active(())
            case .active:
                guard let session = pointerSelectionSession,
                      session.eventID == eventID,
                      let offset = textOffset(atGlobalPoint: pointer.location)
                else {
                    continue
                }
                updatePointerSelection(anchor: session.anchor, extent: offset)
                result = .active(())
            case .ended:
                if let session = pointerSelectionSession,
                   session.eventID == eventID,
                   let offset = textOffset(atGlobalPoint: pointer.location) {
                    updatePointerSelection(anchor: session.anchor, extent: offset)
                }
                if pointerSelectionSession?.eventID == eventID {
                    pointerSelectionSession = nil
                }
                result = .ended(())
            case .failed:
                if pointerSelectionSession?.eventID == eventID {
                    pointerSelectionSession = nil
                }
                result = .failed
            }
        }
        return result
    }

    func resetEventSession() {
        pointerSelectionSession = nil
    }

    private func textOffset(atGlobalPoint point: CGPoint) -> Int? {
        guard inputState != nil else { return nil }
        var points = [point]
        helper.transform.convertGlobal(to: .local, points: &points)
        let documentPoint = CGPoint(
            x: points[0].x + scrollGeometry.contentOffset.x
                - contentInsets.leading,
            y: points[0].y + scrollGeometry.contentOffset.y
                - contentInsets.top
        )
        return selectionLayout.characterOffset(at: documentPoint)
    }

    private func updatePointerSelection(anchor: Int, extent: Int) {
        guard let text, let inputState else { return }
        Update.enqueueAction {
            let value = text.wrappedValue
            var state = inputState.wrappedValue
            _ = state.setSelection(
                anchor: anchor,
                extent: extent,
                affinity: .upstream,
                text: value
            )
            inputState.wrappedValue = state
            self.publishSelection(state, text: value)
            self.revealCaret(state, text: value)
        }
    }

    private func updatePointerWordSelection(at offset: Int) {
        guard let text, let inputState else { return }
        Update.enqueueAction {
            let value = text.wrappedValue
            var state = inputState.wrappedValue
            if let range = state.wordRange(at: offset, in: value) {
                _ = state.setSelection(
                    range,
                    affinity: .upstream,
                    text: value
                )
            } else {
                state.collapseSelection(
                    to: offset,
                    affinity: .upstream,
                    text: value
                )
            }
            inputState.wrappedValue = state
            self.publishSelection(state, text: value)
        }
    }

    private func updatePointerLineSelection(at offset: Int) {
        guard let text, let inputState else { return }
        Update.enqueueAction {
            let value = text.wrappedValue
            var state = inputState.wrappedValue
            _ = state.setSelection(
                state.logicalLineRange(at: offset, in: value),
                affinity: .upstream,
                text: value
            )
            inputState.wrappedValue = state
            self.publishSelection(state, text: value)
        }
    }

    func containsTextInputPoint(_ point: CGPoint) -> Bool {
        helper.containsGlobalPoints(
            [point],
            cacheKey: nil,
            options: .platformDefault,
            children: children
        ).mask[0]
    }

    func updateHoverEvent(id: EventID, at _: CGPoint, time _: Time) -> Bool {
        guard isEnabled else { return false }
        cursorHoverEventIDs.insert(id)
        updateTextCursor()
        return isTextFieldCursorEnabled
    }

    func endHoverEvent(id: EventID, time _: Time) -> Bool {
        guard cursorHoverEventIDs.remove(id) != nil else { return false }
        updateTextCursor()
        return isTextFieldCursorEnabled
    }

    func resetHoverEvents() {
        cursorHoverEventIDs.removeAll(keepingCapacity: true)
        updateTextCursor()
    }

    private func updateTextCursor() {
        let shouldRequestIBeam = isEnabled
            && isTextFieldCursorEnabled
            && !cursorHoverEventIDs.isEmpty
        guard shouldRequestIBeam != hasRequestedIBeamCursor else { return }
        hasRequestedIBeamCursor = shouldRequestIBeam
        (host as? WindowController)?.requestTextInputCursor(
            shouldRequestIBeam ? .text : nil
        )
    }

    func textInputFocusDidChange(_ focused: Bool) {
        guard let text, let inputState else { return }
        Update.enqueueAction {
            let value = text.wrappedValue
            var state = inputState.wrappedValue
            if focused {
                state.setFocused(true, text: value)
                if let selection = self.selection?.wrappedValue {
                    _ = state.setSelection(selection, text: value)
                }
            } else {
                state.setFocused(false, text: value)
            }
            inputState.wrappedValue = state
            self.publishSelection(state, text: value)
        }
    }

    func handleTextInputEvent(_ event: VVD.KeyboardEvent) -> Bool {
        guard isEnabled, let text, let inputState else { return false }

        switch event.type {
        case .textComposition:
            Update.enqueueAction {
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                let changed = state.replaceComposition(
                    with: event.text,
                    in: &value
                )
                if changed {
                    self.storeTextValue(value)
                }
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                if changed {
                    self.revealAfterLayout(state, text: value)
                } else {
                    self.revealCaret(state, text: value)
                }
            }
            return true

        case .textInput:
            Update.enqueueAction {
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                let changed = state.handleTextInput(event.text, text: &value)
                if changed {
                    self.storeTextValue(value)
                }
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                if changed {
                    self.revealAfterLayout(state, text: value)
                }
            }
            return true

        case .keyDown:
            var preview = inputState.wrappedValue
            guard preview.handleKeyDown(
                event.key,
                modifiers: event.modifiers,
                text: text.wrappedValue,
                layout: selectionLayout,
                viewportHeight: scrollGeometry.containerSize.height
            ) else {
                return false
            }
            consumedKeyStreams.insert(KeyStream(
                deviceID: event.deviceID,
                key: event.key
            ))
            Update.enqueueAction {
                let value = text.wrappedValue
                var state = inputState.wrappedValue
                _ = state.handleKeyDown(
                    event.key,
                    modifiers: event.modifiers,
                    text: value,
                    layout: self.selectionLayout,
                    viewportHeight: self.scrollGeometry.containerSize.height
                )
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                self.revealCaret(state, text: value)
            }
            return true

        case .keyUp:
            return consumedKeyStreams.remove(KeyStream(
                deviceID: event.deviceID,
                key: event.key
            )) != nil
        }
    }

    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool {
        canPerformTextEditingCommand(command, clipboard: appContext?.clipboard)
    }

    private func canPerformTextEditingCommand(
        _ command: TextEditingCommand,
        clipboard: (any Clipboard)?
    ) -> Bool {
        guard isEnabled,
              text != nil,
              let inputState,
              inputState.wrappedValue.isFocused else {
            return false
        }
        switch command {
        case .copy, .cut:
            return clipboard != nil && inputState.wrappedValue.hasSelection
        case .paste:
            return clipboard?.containsData(
                forType: ClipboardContentType.utf8PlainText
            ) == true
        case .delete:
            return inputState.wrappedValue.hasSelection
        case .selectAll, .jumpToSelection:
            return true
        case .makeUpperCase, .makeLowerCase, .capitalize:
            return inputState.wrappedValue.transformationRange(
                in: text?.wrappedValue ?? ""
            ) != nil
        default:
            return false
        }
    }

    func performTextEditingCommand(_ command: TextEditingCommand) {
        let clipboard = appContext?.clipboard
        guard canPerformTextEditingCommand(command, clipboard: clipboard),
              let text,
              let inputState else {
            return
        }

        switch command {
        case .copy:
            guard let clipboard else { return }
            Update.enqueueAction {
                guard let selected = inputState.wrappedValue.selectedText(
                    in: text.wrappedValue
                ) else { return }
                try? clipboard.setData(
                    Data(selected.utf8),
                    forType: ClipboardContentType.utf8PlainText
                )
            }

        case .cut:
            guard let clipboard else { return }
            Update.enqueueAction {
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                guard let selected = state.selectedText(in: value) else {
                    return
                }
                do {
                    try clipboard.setData(
                        Data(selected.utf8),
                        forType: ClipboardContentType.utf8PlainText
                    )
                } catch {
                    return
                }
                guard state.replaceSelection(with: "", in: &value) else {
                    return
                }
                self.storeTextValue(value)
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                self.revealAfterLayout(state, text: value)
            }

        case .paste:
            guard let clipboard else { return }
            Update.enqueueAction {
                guard let data = try? clipboard.data(
                    forType: ClipboardContentType.utf8PlainText
                ),
                      let replacement = String(data: data, encoding: .utf8)
                else {
                    return
                }
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                guard state.replaceSelection(
                    with: replacement,
                    in: &value
                ) else {
                    return
                }
                self.storeTextValue(value)
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                self.revealAfterLayout(state, text: value)
            }

        case .delete:
            Update.enqueueAction {
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                guard state.replaceSelection(with: "", in: &value) else {
                    return
                }
                self.storeTextValue(value)
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                self.revealAfterLayout(state, text: value)
            }

        case .selectAll:
            Update.enqueueAction {
                let value = text.wrappedValue
                var state = inputState.wrappedValue
                _ = state.setSelection(
                    0..<value.count,
                    affinity: .upstream,
                    text: value
                )
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
            }

        case .jumpToSelection:
            Update.enqueueAction {
                self.revealSelection(
                    inputState.wrappedValue,
                    text: text.wrappedValue,
                    centered: true
                )
            }

        case .makeUpperCase, .makeLowerCase, .capitalize:
            Update.enqueueAction {
                var value = text.wrappedValue
                var state = inputState.wrappedValue
                let changed = state.transformSelection(in: &value) { source in
                    switch command {
                    case .makeUpperCase: source.uppercased()
                    case .makeLowerCase: source.lowercased()
                    case .capitalize: source.capitalized
                    default: source
                    }
                }
                guard changed else { return }
                self.storeTextValue(value)
                inputState.wrappedValue = state
                self.publishSelection(state, text: value)
                self.revealAfterLayout(state, text: value)
            }

        default:
            return
        }
    }

    func synchronizeSelection(_ selectionValue: TextSelection?) {
        guard !hasSelectionBindingValue
                || selectionBindingValue != selectionValue else {
            return
        }
        selectionBindingValue = selectionValue
        hasSelectionBindingValue = true
        guard let selectionValue, let text, let inputState else { return }
        Update.enqueueAction {
            let value = text.wrappedValue
            var state = inputState.wrappedValue
            guard state.setSelection(selectionValue, text: value) else {
                return
            }
            inputState.wrappedValue = state
        }
    }

    private func publishSelection(
        _ inputState: TextEditorInputState,
        text: String
    ) {
        guard let selection else { return }
        let value = inputState.textSelection(in: text)
        selectionBindingValue = value
        hasSelectionBindingValue = true
        selection.wrappedValue = value
    }

    private func revealCaret(
        _ state: TextEditorInputState,
        text: String
    ) {
        revealSelection(state, text: text, centered: false)
    }

    private func revealAfterLayout(
        _ state: TextEditorInputState,
        text: String,
        centered: Bool = false
    ) {
        refreshSelectionLayout(for: text)
        let reveal: () -> Void = { [weak self] in
            self?.revealSelection(state, text: text, centered: centered)
        }
        Update.enqueueAction(reveal)
    }

    private func revealSelection(
        _ state: TextEditorInputState,
        text: String,
        centered: Bool
    ) {
        refreshSelectionLayout(for: text)
        var target = selectionLayout.caretRect(
            at: state.caretOffset,
            affinity: state.selectionAffinity
        )
        target.origin.x += contentInsets.leading
        target.origin.y += contentInsets.top
        let visible = scrollGeometry.visibleRect
        guard visible.height > 0 else { return }
        let anchor: UnitPoint?
        if centered {
            anchor = .center
        } else if target.minY < visible.minY {
            anchor = nil
        } else if target.maxY > visible.maxY {
            anchor = nil
        } else {
            return
        }
        scroll(to: target, anchor: anchor)
    }

    private func scroll(to targetRect: CGRect, anchor: UnitPoint?) {
        let scrollables = scrollables
        Update.ensure {
            guard let graph = scrollables.graph else { return }
            _AGGraphContext(graph: graph).withCurrent {
                guard scrollables.isValid(in: graph) else { return }
                var transaction = Transaction.current
                transaction.scrollToRequiresCompleteVisibility = true
                for scrollable in scrollables.toStrong().value {
                    let handled = Transaction.withScopedThreadTransaction(
                        transaction
                    ) {
                        scrollable.setContentTarget { _, _ in
                            ScrollTarget(rect: targetRect, anchor: anchor)
                        }
                    }
                    if handled {
                        break
                    }
                }
            }
        }
    }
}
