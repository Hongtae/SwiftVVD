//
//  File: GlyphComposer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
internal import HarfBuzz
private import ICUTextAnalysis

/// Geometric composition for marks left unattached by positioning tables.
/// A font shaping caller prepares one locked face; higher text owners can
/// prepare per-glyph bounds and metrics from several selected faces.
package enum GlyphComposer {
    package struct Metrics {
        package var capHeight: CGFloat
        package var xHeight: CGFloat
        package var ascender: CGFloat

        package init(capHeight: CGFloat, xHeight: CGFloat, ascender: CGFloat) {
            self.capHeight = capHeight
            self.xHeight = xHeight
            self.ascender = ascender
        }

        package func scaled(by scale: CGFloat) -> Self {
            Self(capHeight: capHeight * scale, xHeight: xHeight * scale,
                 ascender: ascender * scale)
        }
    }

    package struct Glyph {
        package var scalar: UInt32
        package var sourceIndex: Int
        package var bounds: CGRect?
        package var isPresent: Bool
        package var allowsMarkComposition: Bool
        package var hasResolvedMarkPosition: Bool
        package var metrics: Metrics?
        package var advance: CGSize
        package var offset: CGPoint

        package init(
            scalar: UInt32,
            sourceIndex: Int,
            bounds: CGRect?,
            isPresent: Bool,
            allowsMarkComposition: Bool,
            hasResolvedMarkPosition: Bool,
            metrics: Metrics?,
            advance: CGSize,
            offset: CGPoint
        ) {
            self.scalar = scalar
            self.sourceIndex = sourceIndex
            self.bounds = bounds
            self.isPresent = isPresent
            self.allowsMarkComposition = allowsMarkComposition
            self.hasResolvedMarkPosition = hasResolvedMarkPosition
            self.metrics = metrics
            self.advance = advance
            self.offset = offset
        }
    }

    private static let complexScripts: Set<String> = [
        "adlm", "ahom", "bali", "batk", "beng", "bhks", "brah", "bugi", "buhd",
        "cakm", "cham", "chrs", "deva", "diak", "dogr", "dupl", "egyp", "elym",
        "gara", "gong", "gonm", "gran", "gujr", "gukh", "guru", "hano", "hmng",
        "hmnp", "java", "kali", "kawi", "khar", "khoj", "kits", "knda", "krai",
        "kthi", "lana", "lepc", "limb", "mahj", "maka", "mand", "mani", "marc",
        "mlym", "modi", "mong", "mtei", "mult", "nagm", "nand", "newa", "nkoo",
        "onao", "orya", "ougr", "phag", "phlp", "plrd", "rjng", "rohg", "saur",
        "shrd", "sidd", "sind", "sinh", "sogd", "soyo", "sund", "sunu", "sylo",
        "tagb", "takr", "tale", "talu", "taml", "tavt", "telu", "tfng", "tglg",
        "thaa", "tibt", "tirh", "tnsa", "todr", "toto", "tutg", "vith", "wcho",
        "yezi", "zanb",
    ]

    package static func isMark(_ scalar: UInt32) -> Bool {
        let category = ICUTextGetIntProperty(Int32(scalar), 0x1005)
        return category == 6 || category == 7
    }

    package static func accepts(_ scalar: UInt32) -> Bool {
        guard isMark(scalar), ICUTextHasBinaryProperty(Int32(scalar), 5) == 0,
              !(0x590..<0x700).contains(scalar) else { return false }
        // Double marks depend on the following base's font, bounds and tracking.
        // That context is not part of a single-font shaping request.
        let combining = ICUTextGetIntProperty(Int32(scalar), 0x1002)
        guard combining != 233 && combining != 234 else { return false }
        let script = ICUTextGetScript(Int32(scalar))
        switch script {
        case 2, 18, 19, 23, 24, 28, 37, 38, 117: return false
        case 0, 1: return true
        default:
            guard let name = ICUTextGetScriptName(script) else { return false }
            return !complexScripts.contains(String(cString: name).lowercased())
        }
    }

    /// Returns source-scalar ranges from Foundation's composed-character
    /// cursor. These ranges remain separate from Swift Character ranges used
    /// for wrapping and selection.
    package static func uncombinedRanges(in text: String) -> [Range<Int>]? {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return [] }
        var utf16Offsets: [Int] = [0]
        utf16Offsets.reserveCapacity(scalars.count + 1)
        for scalar in scalars {
            utf16Offsets.append(utf16Offsets.last! + (scalar.value <= 0xffff ? 1 : 2))
        }

        let source = text as NSString
        var ranges: [Range<Int>] = []
        var lower = 0
        while lower < scalars.count {
            let range = source.rangeOfComposedCharacterSequence(at: utf16Offsets[lower])
            let utf16Upper = NSMaxRange(range)
            var upper = lower + 1
            while upper < utf16Offsets.count && utf16Offsets[upper] < utf16Upper {
                upper += 1
            }
            guard range.location == utf16Offsets[lower],
                  upper < utf16Offsets.count,
                  utf16Offsets[upper] == utf16Upper else { return nil }
            ranges.append(lower..<upper)
            lower = upper
        }
        return ranges
    }

    private static func resolvedClass(_ scalar: UInt32) -> UInt8 {
        let value = ICUTextGetIntProperty(Int32(scalar), 0x1002)
        if value == 0 {
            return (0x20dd...0x20e4).contains(scalar) && scalar != 0x20e1 ? 255 : 0
        }
        if value == 240 { return 220 }
        guard value < 133 else { return UInt8(value) }
        let values: [UInt8] = [
            0, 1, 0, 0, 0, 0, 0, 220, 226, 220, 220, 220, 220, 220, 220, 220,
            220, 220, 220, 228, 220, 1, 220, 230, 232, 228, 230, 230, 230, 220,
            230, 230, 220, 230, 230, 230, 230, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 232, 0, 0, 0, 0, 0, 0,
            220, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 222, 0, 0, 0, 232, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 220, 0, 0, 0, 230, 0, 0, 0, 0, 0, 0, 220,
            230, 0, 220,
        ]
        return values[Int(value)]
    }

    static func compose(_ glyphs: inout [Font.ShapedGlyph], scalars: [UInt32],
                        font: OpaquePointer, metrics: Metrics, units: CGFloat,
                        scale: CGSize, attachments: [Range<Int>],
                        uncombinedRange: Range<Int>?,
                        allowsLeadingMarkBase: Bool) {
        var attached = [Bool](repeating: false, count: glyphs.count)
        for range in attachments {
            precondition(range.lowerBound >= 0 && range.upperBound <= glyphs.count)
            for index in range { attached[index] = true }
        }
        let face = hb_font_get_face(font)
        func bounds(_ index: Int) -> CGRect? {
            var extents = hb_glyph_extents_t()
            guard hb_font_get_glyph_extents(font, glyphs[index].index, &extents) != 0 else { return nil }
            return CGRect(x: CGFloat(extents.x_bearing) / units * scale.width,
                          y: (CGFloat(extents.y_bearing) + CGFloat(extents.height)) / units * scale.height,
                          width: CGFloat(extents.width) / units * scale.width,
                          height: -CGFloat(extents.height) / units * scale.height)
        }
        let leadingMarkIndex = allowsLeadingMarkBase ? uncombinedRange.flatMap { range in
            glyphs.indices.first { index in
                let sourceIndex = glyphs[index].sourceIndex
                return sourceIndex == range.lowerBound &&
                    isMark(scalars[sourceIndex])
            }
        } : nil
        var prepared = glyphs.indices.map { index in
            let glyph = glyphs[index]
            let glyphBounds = glyph.index == 0 ? nil : bounds(index)
            let glyphClass = glyphBounds.map { _ in
                hb_ot_layout_get_glyph_class(face, glyph.index)
            }
            var advance = glyph.advance
            var offset = glyph.offset
            if index == leadingMarkIndex, let glyphBounds {
                // A marked cursor range can begin without an ordinary base.
                // Move its negative left bearing into run space before any
                // attached or geometric marks consume that leading glyph.
                let leadingAdvance = max(-glyphBounds.minX, 0)
                advance.width = leadingAdvance
                offset.x += leadingAdvance
            }
            return Glyph(
                scalar: scalars[glyph.sourceIndex],
                sourceIndex: glyph.sourceIndex,
                bounds: glyphBounds,
                isPresent: glyph.index != 0 && glyph.index != 65535,
                allowsMarkComposition:
                    glyphClass == HB_OT_LAYOUT_GLYPH_CLASS_UNCLASSIFIED ||
                    glyphClass == HB_OT_LAYOUT_GLYPH_CLASS_MARK,
                hasResolvedMarkPosition: attached[index],
                metrics: metrics,
                advance: advance,
                offset: offset
            )
        }
        compose(&prepared, sourceUpperBound: scalars.count,
                uncombinedRange: uncombinedRange,
                allowsLeadingMarkBase: allowsLeadingMarkBase)
        for index in glyphs.indices {
            let glyph = glyphs[index]
            glyphs[index] = Font.ShapedGlyph(
                index: glyph.index,
                sourceIndex: glyph.sourceIndex,
                sourceRange: glyph.sourceRange,
                scriptRunRange: glyph.scriptRunRange,
                advance: prepared[index].advance,
                offset: prepared[index].offset,
                hasResolvedMarkPosition: prepared[index].hasResolvedMarkPosition
            )
        }
    }

    package static func compose(
        _ glyphs: inout [Glyph],
        sourceUpperBound: Int,
        uncombinedRange: Range<Int>? = nil,
        allowsLeadingMarkBase: Bool = true
    ) {
        guard glyphs.count > 1 else { return }
        var groups: [[Int]] = []
        // Canonical glyph reordering does not reorder the source composition walk.
        for index in glyphs.indices.sorted(by: {
            let a = glyphs[$0].sourceIndex, b = glyphs[$1].sourceIndex
            return a == b ? $0 < $1 : a < b
        }) {
            if groups.isEmpty || !isMark(glyphs[index].scalar) {
                groups.append([index])
            } else {
                groups[groups.count - 1].append(index)
            }
        }
        var advances = glyphs.map(\.advance)
        var offsets = glyphs.map(\.offset)
        for group in groups where group.count > 1 {
            let baseIndex = group[0]
            let baseScalar = glyphs[baseIndex].scalar
            let isLeadingMarkBase = allowsLeadingMarkBase && isMark(baseScalar) &&
                uncombinedRange?.lowerBound == glyphs[baseIndex].sourceIndex
            let baseIsDefaultIgnorable =
                ICUTextHasBinaryProperty(Int32(baseScalar), 5) != 0
            let admitsVisibleCursorBase = uncombinedRange.map { range in
                range.lowerBound == glyphs[baseIndex].sourceIndex &&
                    group.allSatisfy { range.contains(glyphs[$0].sourceIndex) }
            } == true
            guard !isMark(baseScalar) || isLeadingMarkBase,
                  !baseIsDefaultIgnorable || admitsVisibleCursorBase,
                  glyphs[baseIndex].isPresent,
                  var base = glyphs[baseIndex].bounds else { continue }
            // Admission applies to the whole remaining character group. A
            // retained ignorable mark prevents geometric composition of that
            // group; skipping only that mark would reposition its neighbors.
            guard !group.dropFirst().contains(where: {
                ICUTextHasBinaryProperty(Int32(glyphs[$0].scalar), 5) != 0
            }) else { continue }
            var advance = advances[baseIndex].width
            base.origin.x += offsets[baseIndex].x
            base.origin.y += offsets[baseIndex].y
            if base.width == 0 { base.size.width = advance }
            var left: CGFloat = 0
            var maximumPosition: CGFloat = 0
            var placed: [(Int, CGPoint)] = []
            for index in group.dropFirst() {
                let scalar = glyphs[index].scalar
                guard !glyphs[index].hasResolvedMarkPosition, accepts(scalar),
                      glyphs[index].isPresent,
                      glyphs[index].allowsMarkComposition,
                      let mark = glyphs[index].bounds,
                      let metrics = glyphs[index].metrics ?? glyphs[baseIndex].metrics else { continue }
                let combining = resolvedClass(scalar)
                let point: CGPoint
                let centered: Bool
                if combining == 0 {
                    if ICUTextHasBinaryProperty(Int32(scalar), 8) != 0 {
                        point = base.origin
                    } else {
                        point = CGPoint(x: base.maxX, y: 0)
                    }
                    centered = false
                } else {
                    (point, centered) = position(mark: mark, base: base, advance: advance,
                                                 combining: combining, metrics: metrics)
                }
                placed.append((index, point))
                maximumPosition = max(maximumPosition, point.x)
                let positioned = mark.offsetBy(dx: point.x, dy: point.y)
                if !centered {
                    advance += max(positioned.maxX - base.maxX, 0)
                    if left + positioned.minX < 0 {
                        let shift = -(left + positioned.minX)
                        left += shift
                        advance += shift
                    }
                }
                base = base.union(positioned)
            }
            guard !placed.isEmpty else { continue }
            if glyphs[group.last!].sourceIndex == sourceUpperBound - 1 {
                advance = max(advance, maximumPosition)
            }
            advances[baseIndex].width = advance
            offsets[baseIndex].x += left
            for (index, position) in placed {
                advances[index] = .zero
                offsets[index] = CGPoint(x: position.x + left - advance, y: position.y)
                glyphs[index].hasResolvedMarkPosition = true
            }
        }
        for index in glyphs.indices {
            glyphs[index].advance = advances[index]
            glyphs[index].offset = offsets[index]
        }
    }

    /// Returns a baseline-relative origin and whether horizontal ink preserves
    /// the base's advance. Geometry is evaluated before any raster rounding.
    static func position(mark: CGRect, base: CGRect, advance: CGFloat,
                         combining: UInt8, metrics: Metrics) -> (CGPoint, Bool) {
        var base = base
        var mark = mark
        var value = Int(combining)
        var gap = CGPoint.zero
        var centered = false
        let horizontal: Int
        let vertical: Int
        if value == 1 {
            centered = true
            if metrics.capHeight != 0 { base.origin.y = 0; base.size.height = metrics.capHeight }
            horizontal = 2
            vertical = 3
            if advance > 0 { base.origin.x = 0; base.size.width = advance }
        } else {
            var doubleMark = false
            if (218...254).contains(value) {
                if value == 224 {
                    gap.x = base.origin.x
                    value -= 16
                } else if value == 226 {
                    gap.x = mark.origin.x
                    value -= 16
                } else {
                    if metrics.xHeight != 0 && base.maxY < metrics.capHeight {
                        gap.y = metrics.xHeight / 5
                    } else if metrics.capHeight != 0 {
                        gap.y = metrics.capHeight / 8
                    } else {
                        gap.y = (metrics.ascender != 0 ? metrics.ascender : mark.size.height) / 8
                    }
                    if value == 233 || value == 234 {
                        doubleMark = true
                        centered = true
                        mark.size.width *= 0.5
                        base.size.width = max(advance, 0)
                        base.origin.x = base.size.width - advance
                    } else {
                        value -= value <= 223 ? 18 : 16
                    }
                }
            }
            if doubleMark {
                horizontal = 4
                vertical = value == 234 ? 1 : 2
            } else if value == 1 || value == 255 {
                horizontal = 2
                vertical = 3
            } else if value == 208 || value == 210 {
                horizontal = value == 208 ? 0 : 4
                vertical = 0
            } else {
                horizontal = value - (value < 208 ? 200 : 212)
                vertical = value < 208 ? 2 : 1
                if horizontal == 2 {
                    centered = true
                    if advance > 0 { base.origin.x = 0; base.size.width = advance }
                }
            }
        }
        var point = base.origin
        if base.size.width > 0 {
            switch horizontal {
            case 0:
                point.x = vertical == 0 ? base.origin.x - mark.size.width - gap.x : base.origin.x - mark.origin.x
            case 4:
                point.x = base.origin.x + base.size.width - mark.origin.x +
                    (vertical == 0 ? gap.x : -mark.size.width)
            default:
                point.x = base.origin.x - mark.origin.x + (base.size.width - mark.size.width) * 0.5 + gap.x
            }
        }
        if base.size.height > 0 {
            switch vertical {
            case 0: break
            case 1: point.y = base.origin.y + base.size.height - mark.origin.y + gap.y
            case 2: point.y = base.origin.y - (mark.origin.y + mark.size.height) - gap.y
            default: point.y = base.origin.y - mark.origin.y + (base.size.height - mark.size.height) * 0.5
            }
        }
        return (point, centered)
    }
}
