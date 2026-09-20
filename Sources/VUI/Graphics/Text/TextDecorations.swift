//
//  File: TextDecorations.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Text.Layout {
    struct Decorations {
        struct Fragment {
            var start: CGPoint
            var end: CGPoint
        }

        struct Segment {
            var color: Color.Resolved
            var thickness: CGFloat
            var runs: Range<Int>
            var dashes: [CGFloat]
            var fragments: [Fragment]
        }

        var segments: [Segment]

        // Selection retains the complete line's metrics and original run ranges.
        func selecting(runs: Range<Int>, bounds: ClosedRange<CGFloat>?,
                       keepsStart: Bool, keepsEnd: Bool) -> Self {
            Self(segments: segments.compactMap { segment in
                guard segment.runs.overlaps(runs) else { return nil }
                var segment = segment
                segment.fragments = segment.fragments.compactMap { fragment in
                    var fragment = fragment
                    if fragment.start.x > fragment.end.x {
                        swap(&fragment.start, &fragment.end)
                    }
                    if let bounds {
                        if !keepsStart || runs.lowerBound != segment.runs.lowerBound {
                            fragment.start.x = Swift.max(fragment.start.x, bounds.lowerBound)
                        }
                        if !keepsEnd || runs.upperBound != segment.runs.upperBound {
                            fragment.end.x = Swift.min(fragment.end.x, bounds.upperBound)
                        }
                    }
                    return fragment.start.x < fragment.end.x ? fragment : nil
                }
                return segment
            })
        }
    }
}

/// Produces line decorations from the portable font and shaping backend.
enum TextDecorationProducer {
    struct Metrics {
        var position: CGFloat
        var thickness: CGFloat
    }

    static func calculateGlyphIntersections(
        glyphs: [ResolvedTextSource.Glyph], range: Range<Int>, positions: [CGPoint],
        unit: CGFloat, glyphTransform: CGAffineTransform, strip: CGRect,
        _ body: (CGFloat, CGFloat) -> Void
    ) {
        let logicalScale = CGAffineTransform(scaleX: unit, y: unit)
        for index in range {
            let glyph = glyphs[index]
            guard let glyphIndex = glyph.glyphIndex,
                  let bounds = glyph.face.glyphBounds(at: glyphIndex) else { continue }
            var transform = glyphTransform
            // Glyph translation is local; emission applies the outer text origin.
            transform.tx = positions[index].x; transform.ty = positions[index].y
            let localBounds = bounds.applying(logicalScale).applying(transform)
            guard !localBounds.isEmpty, localBounds.intersects(strip),
                  let path = glyph.face.glyphOutline(at: glyphIndex) else { continue }
            let inverse = transform.inverted()
            let a = CGPoint(x: 0, y: strip.minY).applying(inverse).y
            let b = CGPoint(x: 0, y: strip.maxY).applying(inverse).y
            let intervals = TextDecorationIntersections.occupiedIntervals(
                in: path.applying(logicalScale), lower: min(a, b), upper: max(a, b))
            for interval in intervals {
                body(CGPoint(x: interval.lowerBound, y: 0).applying(transform).x,
                     CGPoint(x: interval.upperBound, y: 0).applying(transform).x)
            }
        }
    }

    static func metrics(_ raw: TypefaceDecorationMetrics, baselineOffset: CGFloat = 0, strikethrough: Bool,
                        scale: CGFloat) -> Metrics? {
        guard scale.isFinite, scale > 0 else { return nil }
        if strikethrough {
            guard let xHeight = raw.xHeight else { return nil }
            var position = (xHeight * 0.5 + baselineOffset) * scale
            var thickness = raw.underlineThickness * scale
            if position > 1 && thickness > 0.35 {
                thickness = ceil(thickness)
                position = thickness.truncatingRemainder(dividingBy: 2) == 0
                    ? floor(position + 0.5) : floor(position) + 0.5
            }
            return Metrics(position: position / scale, thickness: thickness / scale)
        }
        guard let ascent = raw.defaultAscent, let descent = raw.defaultDescent else { return nil }
        var bound = descent >= 2 ? descent : (ascent + descent) * 0.25
        let fallback = min(bound * 5.363699102829537, ascent + descent)
        let shiftedPosition = raw.underlinePosition + baselineOffset
        var position = -scale * (shiftedPosition < 0
            ? shiftedPosition : fallback * -0.08805546253922189)
        let rawThickness = raw.underlineThickness * scale
        let scaledOffset = baselineOffset * scale
        var thickness = rawThickness
        bound *= scale
        if bound >= 2 && thickness > 0.35 {
            thickness = ceil(thickness)
            if thickness >= bound || (bound <= 4 && thickness >= 3) || (bound <= 2.5 && thickness >= 2) {
                thickness -= 1
            }
            position = thickness.truncatingRemainder(dividingBy: 2) == 0
                ? floor(position + 0.5) : floor(position) + 0.5
            if position < 1.5 || (bound > 4 && position <= 1.5) { position += 1 }
        }
        if bound > 0 { position = min(position, floor(bound - scaledOffset) - thickness * 0.5) }
        position = max(position, ceil(rawThickness - scaledOffset) + thickness * 0.5)
        thickness /= scale
        return Metrics(position: -position / scale,
                       thickness: thickness > 0 ? thickness : fallback * 0.044027731269610945)
    }

    static func segments(glyphs: [ResolvedTextSource.Glyph], runs: [Range<Int>],
                         origin: CGPoint, glyphTransform: CGAffineTransform,
                         scaleFactor: CGFloat, scale: CGFloat,
                         displayScale: CGFloat, environment: EnvironmentValues)
        -> [(segment: Text.Layout.Decorations.Segment, style: Text.LineStyle)] {
        struct Group {
            var runs: Range<Int>
            var start: CGFloat
            var advance: CGFloat
            var metrics: Metrics
            var style: Text.LineStyle
            var color: Color.Resolved
            var quantized: Bool
        }
        var segments: [(Text.Layout.Decorations.Segment, Text.LineStyle)] = []
        let unit = 1 / scaleFactor
        var positions: [CGPoint] = []
        var offset = CGPoint.zero
        for (index, glyph) in glyphs.enumerated() {
            if index != 0 { offset.x += glyph.kerning.x; offset.y += glyph.kerning.y }
            positions.append(CGPoint(x: (offset.x + glyph.positionOffset.x) * unit,
                y: (offset.y + glyph.positionOffset.y + glyph.baselineOffset) * unit))
            offset.x += glyph.advance.width
        }
        for strike in [false, true] {
            var groups: [Group] = []
            var x: CGFloat = 0
            for (index, range) in runs.enumerated() {
                let advance = range.reduce(CGFloat.zero) { result, i in
                    result + glyphs[i].advance.width + (i == 0 ? 0 : glyphs[i].kerning.x)
                } * unit
                defer { x += advance }
                guard let first = range.first else { continue }
                let glyph = glyphs[first]
                guard let style = strike ? glyph.style.strikethroughStyle : glyph.style.underlineStyle,
                      let raw = glyph.face.decorationMetrics?.scaled(by: unit) else { continue }
                let color = (style.color ?? glyph.foregroundColor)?.resolve(in: environment)
                    ?? Color.Resolved(colorSpace: .sRGBLinear, red: -1, green: -1, blue: -1)
                // Custom faces without raw default metrics retain their own metric policy.
                let quantized = raw.defaultAscent != nil && raw.defaultDescent != nil
                var value: Metrics
                if quantized, let resolved = metrics(raw, baselineOffset: glyph.baselineOffset * unit,
                                                     strikethrough: strike, scale: scale) {
                    value = resolved
                } else {
                    guard !strike || raw.xHeight != nil else { continue }
                    value = Metrics(position: (strike ? raw.xHeight! * 0.5 : raw.underlinePosition)
                        + glyph.baselineOffset * unit,
                        thickness: ceil(raw.underlineThickness * displayScale) / displayScale)
                }
                if let last = groups.indices.last,
                   groups[last].runs.upperBound == index,
                   groups[last].style.nsUnderlineStyleValue == style.nsUnderlineStyleValue,
                   groups[last].color == color, groups[last].quantized == quantized,
                   (!strike && quantized || groups[last].metrics.position == value.position),
                   (quantized || groups[last].metrics.thickness == value.thickness) {
                    groups[last].runs = groups[last].runs.lowerBound..<(index + 1)
                    groups[last].advance += advance
                    groups[last].metrics.position = min(groups[last].metrics.position, value.position)
                    groups[last].metrics.thickness = max(groups[last].metrics.thickness, value.thickness)
                } else {
                    if quantized && !strike { value.position = min(0, value.position) }
                    groups.append(Group(runs: index..<(index + 1), start: x, advance: advance,
                                        metrics: value, style: style, color: color, quantized: quantized))
                }
            }
            for group in groups {
                let length = group.quantized ? ceil(group.advance) : group.advance
                let groupEnd = group.start + length
                let start = CGPoint(x: origin.x + group.start, y: origin.y - group.metrics.position)
                let end = CGPoint(x: origin.x + groupEnd, y: start.y)
                let decoration = ResolvedTextSource.Drawing.Decoration(start: start, end: end,
                    lineWidth: group.metrics.thickness, lineStyle: group.style)
                var fragments: [Text.Layout.Decorations.Fragment] = []
                if !strike && group.quantized {
                    let center = group.metrics.position * glyphTransform.d
                    let lower = center - group.metrics.thickness * 0.5
                    let upper = center + group.metrics.thickness * 0.5
                    // Bounds admission uses raw advance; only emitted endpoints are rounded.
                    let strip = CGRect(x: group.start, y: lower, width: group.advance, height: upper - lower)
                    var currentStart = group.start
                    let minimumGap = group.metrics.thickness * 0.75
                    for run in group.runs {
                        calculateGlyphIntersections(glyphs: glyphs, range: runs[run], positions: positions,
                            unit: unit, glyphTransform: glyphTransform, strip: strip) { occupiedStart, occupiedEnd in
                            let gapEnd = occupiedStart - group.metrics.thickness
                            if gapEnd - currentStart > minimumGap {
                                fragments.append(.init(start: CGPoint(x: origin.x + currentStart, y: start.y),
                                                       end: CGPoint(x: origin.x + gapEnd, y: start.y)))
                            }
                            // Every callback replaces the start, including overlapping intervals.
                            currentStart = occupiedEnd + group.metrics.thickness
                        }
                    }
                    if groupEnd - currentStart > minimumGap {
                        fragments.append(.init(start: CGPoint(x: origin.x + currentStart, y: start.y), end: end))
                    }
                } else if start.x < end.x { fragments = [.init(start: start, end: end)] }
                segments.append((.init(color: group.color, thickness: group.metrics.thickness,
                    runs: group.runs, dashes: decoration.dashPattern(lineWidth: group.metrics.thickness),
                    fragments: fragments), group.style))
            }
        }
        return segments
    }
}
