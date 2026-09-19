//
//  File: CharacterComposer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
private import ICUTextAnalysis

/// Character composition precedes the font's substitution and positioning tables.
/// Original scalar indices remain the authority for feature ranges and glyph sources.
package enum CharacterComposer {
    package struct Input {
        package let scalars: [UInt32]
        package let deletedSources: [Int]
        package let ranges: [Range<Int>]
        package let composedRanges: [Range<Int>]

        package func sliced(to range: Range<Int>) -> Self {
            func clipped(_ ranges: [Range<Int>]) -> [Range<Int>] {
                ranges.compactMap {
                    let a = max($0.lowerBound, range.lowerBound)
                    let b = min($0.upperBound, range.upperBound)
                    return a < b ? (a - range.lowerBound)..<(b - range.lowerBound) : nil
                }
            }
            return Self(scalars: Array(scalars[range]),
                deletedSources: deletedSources.filter(range.contains).map { $0 - range.lowerBound },
                ranges: clipped(ranges), composedRanges: clipped(composedRanges))
        }
    }

    package static func accepts(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.map(\.value)
        guard scalars.contains(where: {
            let category = ICUTextGetIntProperty(Int32($0), 0x1005)
            return category == 6 || category == 7
        }) else { return false }
        return ScriptRun.ranges(in: scalars).contains { accepts($0, scalars: scalars) }
    }

    /// Attributed preparation has a base font for cmap admission and original
    /// slot fonts for publication. It precedes independent glyph shaping groups.
    package static func prepare(_ text: String, isLastResort: (Int) -> Bool,
                                hasGlyph: (Int, UInt32) -> Bool,
                                fontsEqual: (Int, Int) -> Bool) -> Input? {
        let scalars = text.unicodeScalars.map(\.value)
        var graphemes: [Range<Int>] = []
        for character in text {
            let start = graphemes.count
            let count = character.unicodeScalars.count
            graphemes.append(contentsOf: repeatElement(start..<(start + count), count: count))
        }
        let ranges = ScriptRun.ranges(in: scalars).filter { accepts($0, scalars: scalars) }.map(\.range)
        guard !ranges.isEmpty else { return nil }
        var result = scalars
        var deleted: [Int] = []
        var composed: [Range<Int>] = []
        for range in ranges {
            if let input = prepare(scalars, range: range, graphemes: graphemes,
                                   isLastResort: isLastResort, hasGlyph: hasGlyph, fontsEqual: fontsEqual) {
                result.replaceSubrange(range, with: input.scalars[range])
                deleted += input.deletedSources
                composed += input.composedRanges
            }
        }
        return Input(scalars: result, deletedSources: deleted, ranges: ranges, composedRanges: composed)
    }

    static func accepts(_ run: ScriptRun, scalars: [UInt32]) -> Bool {
        // These alphabetic runs use the default OpenType shaper. Other script
        // shapers retain ownership of their character preparation.
        guard run.script == 8 || run.script == 14 || run.script == 25 else { return false }
        return scalars[run.range].contains {
            let category = ICUTextGetIntProperty(Int32($0), 0x1005)
            return category == 6 || category == 7
        }
    }

    /// The caller holds the font lock and supplies complete grapheme intervals.
    /// Context outside the selected run is retained without modification.
    static func prepare(_ scalars: [UInt32], range: Range<Int>,
                        graphemes: [Range<Int>], isLastResort: Bool,
                        hasGlyph: (UInt32) -> Bool) -> Input? {
        prepare(scalars, range: range, graphemes: graphemes,
                isLastResort: { _ in isLastResort }, hasGlyph: { _, scalar in hasGlyph(scalar) },
                fontsEqual: { _, _ in true })
    }

    private static func prepare(_ scalars: [UInt32], range: Range<Int>,
                                graphemes: [Range<Int>], isLastResort: (Int) -> Bool,
                                hasGlyph: (Int, UInt32) -> Bool,
                                fontsEqual: (Int, Int) -> Bool) -> Input? {
        var prepared = scalars
        var deletedSources: [Int] = []
        var composedRanges: [Range<Int>] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let end = min(graphemes[start].upperBound, range.upperBound)
            if end - start < 2 || isLastResort(start) {
                start = end
                continue
            }
            let original = scalars[start..<end]
            let text = String(String.UnicodeScalarView(original.map { Unicode.Scalar($0)! }))
            let composed = text.precomposedStringWithCanonicalMapping
            let removed = text.utf16.count - composed.utf16.count
            let characters = composed.unicodeScalars.map(\.value)
            let supported = removed > 0 && characters.allSatisfy { hasGlyph(start, $0) }
            if supported {
                composedRanges.append(start..<end)
                // Keep every source slot. The first slot receives the composed
                // base, excess leading slots become deleted glyphs, and later
                // characters retain the original trailing UTF-16 positions.
                var originalOffsets: [Int: Int] = [:]
                var offset = 0
                for index in start..<end {
                    originalOffsets[offset] = index
                    offset += scalars[index] > 0xffff ? 2 : 1
                }
                offset = 0
                var retainedSources: Set<Int> = []
                for (index, scalar) in characters.enumerated() {
                    let sourceOffset = index == 0 ? 0 : removed + offset
                    guard let source = originalOffsets[sourceOffset] else {
                        preconditionFailure("Character composition split a source scalar")
                    }
                    if fontsEqual(start, source) {
                        prepared[source] = scalar
                        retainedSources.insert(source)
                    }
                    offset += scalar > 0xffff ? 2 : 1
                }
                deletedSources.append(contentsOf: (start..<end).filter { !retainedSources.contains($0) })
            }
            start = end
        }
        guard !deletedSources.isEmpty else { return nil }
        return Input(scalars: prepared, deletedSources: deletedSources,
                     ranges: [range], composedRanges: composedRanges)
    }
}
