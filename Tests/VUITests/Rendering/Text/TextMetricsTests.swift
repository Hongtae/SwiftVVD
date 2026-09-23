import Foundation
import XCTest
import VVD
@testable import VUI

final class TextMetricsTests: XCTestCase {
    // ASSERTIONS fontGraphicsFitting27Observed
    func testSuppliedFontAutomaticFittingRetainsEachMetricOwner() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let ordinaryValues: [[CGFloat]] = [
            [80,48,19,43], [79,15,12,12], [30,28,11,25], [80,56,22,50],
            [80,48,19,43], [79,15,12,12], [30,28,11,25], [79.5,56,22,50],
            [80,52,21,47], [80,19,15,15], [26,33,11,29], [80,65,22,57],
            [80,56,22,50], [78,19,15,15], [30,33,11,29], [78,65,22,57]]
        let managerValues: [[CGFloat]] = [
            [79.5,46,18,41], [80,15,12,12], [30,28,11,25], [80,56,22,50],
            [79.5,48,19,43], [80,15,12,12], [30,28,11,25], [79.5,56,22,50],
            [80,54,21,48], [80,19,15,15], [26,33,11,29], [80,65,22,57],
            [80,56,22,50], [78,19,15,15], [30,33,11,29], [78,65,22,57]]
        let ordinaryScales: [CGFloat] = [0.859375,0.546875,0.5,1, 0.875,0.5546875,0.5,1, 0.71875,0.5,0.5,1, 0.75,0.5,0.5,1]
        let managerScales: [CGFloat] = [0.8515625,0.546875,0.5,1, 0.875,0.5625,0.5,1, 0.71875,0.5,0.5,1, 0.7421875,0.5,0.5,1]
        for memory in [false, true] {
            for contentScale: CGFloat in [1, 2] {
                for index in ordinaryValues.indices {
                    let group = index / 4, proposal = index % 4
                    let weight: CGFloat = group == 1 ? 700 : group == 3 ? 530.0013885498047 : 400
                    let width: CGFloat = group == 1 || group == 3 ? 90 : 100
                    let secondSize: CGFloat = group < 2 ? 23.375 : 31.375
                    var backends: [CGFloat: VVD.Font] = [:]
                    func font(_ size: CGFloat) throws -> VUI.Font {
                        if let backend = backends[size] { return VUI.Font(vector: backend) }
                        let backend = try XCTUnwrap(memory ? VVD.Font(data: Data(contentsOf: file)) : VVD.Font(path: file.path))
                        backend.setPointSize(size, dpi: (UInt32(72 * contentScale), UInt32(72 * contentScale)))
                        XCTAssertTrue(backend.setVariationCoordinates([0x77676874: weight, 0x77647468: width]))
                        backends[size] = backend
                        return VUI.Font(vector: backend)
                    }
                    let text = try Text(verbatim: "AAA ").font(font(23.375)).foregroundColor(.red)
                        + Text(verbatim: "BBB BBB").font(font(secondSize)).foregroundColor(.blue)
                    try withOwner(text, configure: {
                        $0.minimumScaleFactor = proposal == 3 ? 1 : 0.5
                        $0.lineLimit = proposal == 1 ? 1 : 2
                        $0.displayScale = proposal == 1 ? 1 : 2
                        $0._contentScaleFactor = contentScale
                    }) { ordinary in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                            layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                            let request = CGSize(width: proposal == 2 ? 30 : 80, height: proposal == 1 ? 24 : 120)
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            let label = "memory=\(memory) contentScale=\(contentScale) custom=\(custom) case=\(index + 1)"
                            let expected = custom ? managerValues[index] : ordinaryValues[index]
                            XCTAssertEqual(metrics.scale, custom ? managerScales[index] : ordinaryScales[index], label)
                            XCTAssertEqual([metrics.size.width, metrics.size.height, metrics.firstBaseline, metrics.lastBaseline], expected, label)
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            XCTAssertEqual(metrics.numberOfLines, proposal == 1 ? 1 : 2, label)
                            let source = try XCTUnwrap(owner.resolvedText)
                            for (fontSize, backend) in backends {
                                XCTAssertEqual(backend.pointSize, fontSize, label)
                                XCTAssertEqual(backend.dpi.y, UInt32(72 * contentScale), label)
                                XCTAssertEqual(backend.variationCoordinates, [0x77676874: weight, 0x77647468: width], label)
                            }
                            XCTAssertEqual(source.runs.count, 2, label)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textNegativeMultilineFitting27Observed textNegativeMultilineDrawing27Observed
    func testNegativeMultilineFittingRetainsParagraphMeasurementAndDrawingOwners() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        typealias Observation = (width: CGFloat, height: CGFloat, first: CGFloat, last: CGFloat,
            scale: CGFloat, lines: UInt, truncated: Bool)
        let ordinaryObservations: [Observation] = [
            (55, 94, 29, 90, 1, 3, false), (14.5, 336, 21, 332, 1, 11, false),
            (45, 40, 21, 37, 0.7265625, 2, false), (20, 31, 16, 29, 0.5703125, 2, false),
            (55, 94, 29, 90, 1, 3, false), (14.5, 336, 21, 332, 1, 11, false),
            (45, 40, 21, 37, 0.7265625, 2, false), (20, 31, 16, 29, 0.5703125, 2, false),
            (33.5, 57, 29, 53, 1, 2, false), (20, 97, 29, 93, 1, 4, false),
            (24, 40, 21, 37, 0.7265625, 2, false), (20, 33, 17, 31, 0.59375, 2, false),
            (33.5, 57, 29, 53, 1, 2, false), (20, 97, 29, 93, 1, 4, false),
            (24, 40, 21, 37, 0.7265625, 2, false), (20, 33, 17, 31, 0.59375, 2, false)
        ]
        var managerObservations = ordinaryObservations
        managerObservations[2] = (52, 26, 21, 21, 0.7265625, 1, true)
        managerObservations[10] = (0, 26, 21, 21, 0.7265625, 1, true)
        managerObservations[11] = (0, 22, 17, 17, 0.6015625, 1, true)
        managerObservations[14] = (24.5, 40, 21, 37, 0.7265625, 2, false)
        managerObservations[15] = (20, 33, 17, 31, 0.6015625, 2, false)
        let narrowWidths: [CGFloat] = [14.0078125, 7.00390625]
            + Array(repeating: CGFloat(11.314453125), count: 6)
            + Array(repeating: CGFloat(11.06494140625), count: 3)
        let managerDrawingWidths: [[CGFloat]] = [
            [54.955078125, 46.6806640625], narrowWidths, [12.31201171875], [17.55858612060547],
            [54.955078125, 33.943359375, 33.19482421875], narrowWidths,
            [44.90277099609375, 24.118114471435547], [19.76239013671875, 18.93142318725586],
            [24.6240234375], [19.88671875, 11.06494140625, 11.06494140625, 11.06494140625],
            [0], [0], [19.88671875, 33.19482421875],
            [19.88671875, 11.06494140625, 11.06494140625, 11.06494140625],
            [0, 24.118114471435547], [0, 19.968761444091797]
        ]
        for contentScale: CGFloat in [1, 2] {
            for kind in ["kern", "tracking"] {
                for index in ordinaryObservations.indices {
                    let spacing: CGFloat = index < 8 ? -8 : -16
                    let separator = index % 8 < 4 ? "\n" : "\u{2028}"
                    let fitting = index % 4 >= 2
                    func run(_ string: String, size: CGFloat, color: VUI.Color) -> Text {
                        let value = Text(verbatim: string).font(.file(file, size: size)).foregroundColor(color)
                        return kind == "kern" ? value.kerning(spacing) : value.tracking(spacing)
                    }
                    let text = run("AAA ", size: 23, color: .red)
                        + run("BBB BBB" + separator, size: 31, color: .blue)
                        + Text(verbatim: "CCC").font(.file(file, size: 17)).foregroundColor(.green)
                    try withOwner(text, configure: {
                        $0.minimumScaleFactor = fitting ? 0.5 : 1
                        $0.lineLimit = fitting ? 2 : nil
                        $0._contentScaleFactor = contentScale
                    }) { ordinary in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                            layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                            let expected = custom ? managerObservations[index] : ordinaryObservations[index]
                            let label = "\(kind) case=\(index + 1) custom=\(custom) contentScale=\(contentScale)"
                            let request = CGSize(width: index % 2 == 0 ? 80 : 20, height: fitting ? 40 : 500)
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(metrics.size, CGSize(width: expected.width, height: expected.height), label)
                            XCTAssertEqual(metrics.firstBaseline, expected.first, label)
                            XCTAssertEqual(metrics.lastBaseline, expected.last, label)
                            XCTAssertEqual(metrics.scale, expected.scale, label)
                            XCTAssertEqual(metrics.numberOfLines, expected.lines, label)
                            XCTAssertEqual(metrics.hasTruncatedRanges, expected.truncated, label)
                            if custom {
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                XCTAssertEqual(layout.map(\.typographicBounds.width), managerDrawingWidths[index], label)
                                XCTAssertEqual(layout.isTruncated, index == 3, label)
                                let drawingScale: CGFloat = [2, 10, 11].contains(index) ? 0.5 : expected.scale
                                XCTAssertEqual(prepared.lines.first?.glyphs.first?.style.fontResource?.pointSize,
                                    23 * drawingScale, label)
                            }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textNegativeSpacingAdvance27Observed textNegativeSpacingFitting27Observed
    // ASSERTIONS textNegativeSpacingToken27Observed
    func testNegativeSpacingPreservesCollapsedGlyphsAndSelectsFittedTokens() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        typealias Observation = (width: CGFloat, height: CGFloat, baseline: CGFloat,
            factor: CGFloat, kept: Int, tokenSize: CGFloat?)
        var observations: [Observation] = [
            (67, 37, 29, 1, 5, 31), (11.5, 37, 29, 1, 0, 23),
            (80, 25, 20, 0.7109375, 11, nil), (17, 18, 14, 0.5, 3, 31),
            (79.5, 37, 29, 1, 9, 31), (14.5, 37, 29, 1, 1, 23),
            (80, 34, 27, 0.9453125, 11, nil), (20, 20, 16, 0.5703125, 11, nil)
        ]
        observations += Array(repeating: Observation(20, 37, 29, 1, 11, nil), count: 4)
        observations += Array(repeating: Observation(0, 37, 29, 1, 11, nil), count: 4)
        observations += [(0, 37, 29, 1, 3, nil), (5, 37, 29, 1, 3, 31), (0, 37, 29, 1, 0, 23)]
        var inputs: [(spacing: CGFloat, width: CGFloat, minimum: CGFloat, wide: Bool)] = []
        for spacing: CGFloat in [-4, -8, -16, -24] {
            for (width, minimum): (CGFloat, CGFloat) in [(80, 1), (20, 1), (80, 0.5), (20, 0.5)] {
                inputs.append((spacing, width, minimum, false))
            }
        }
        inputs += [(-16, 1, 1, false), (-16, 8, 1, false), (-16, 1, 1, true)]
        for contentScale: CGFloat in [1, 2] {
            for kind in ["kern", "tracking"] {
                for (index, input) in inputs.enumerated() {
                    func run(_ string: String, size: CGFloat, color: VUI.Color) -> Text {
                        let text = Text(verbatim: string).font(.file(file, size: size)).foregroundColor(color)
                        return kind == "kern" ? text.kerning(input.spacing) : text.tracking(input.spacing)
                    }
                    let text = run(input.wide ? "WWW " : "AAA ", size: 23, color: .red)
                        + run(input.wide ? "WWW WWW" : "BBB BBB", size: 31, color: .blue)
                    try withOwner(text, configure: {
                        $0.minimumScaleFactor = input.minimum; $0.lineLimit = 1
                        $0._contentScaleFactor = contentScale
                    }) { ordinary in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                            layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                            var expected = observations[index]
                            if custom && index == 3 { expected = (14.5, 18, 14, 0.5, 3, 23) }
                            if custom && index == 6 { expected = (79, 34, 27, 0.9375, 11, nil) }
                            if custom && index == 17 { expected = (0, 37, 29, 1, 3, nil) }
                            let label = "\(kind) case=\(index) custom=\(custom) contentScale=\(contentScale)"
                            let request = CGSize(width: input.width, height: 60)
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(metrics.size, CGSize(width: expected.width, height: expected.height), label)
                            XCTAssertEqual(metrics.scale, expected.factor, label)
                            XCTAssertEqual(metrics.firstBaseline, expected.baseline, label)
                            XCTAssertEqual(metrics.lastBaseline, expected.baseline, label)
                            XCTAssertEqual(metrics.numberOfLines, 1, label)
                            XCTAssertEqual(metrics.hasTruncatedRanges, expected.kept < 11, label)
                            let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            let line = try XCTUnwrap(prepared.lines.first)
                            XCTAssertEqual(prepared.lines.count, 1, label)
                            let body = Array((input.wide ? "WWW WWW WWW" : "AAA BBB BBB").unicodeScalars)
                            let scalars = Array(body.prefix(expected.kept))
                                + (expected.tokenSize == nil ? [] : Array("…".unicodeScalars))
                            XCTAssertEqual(line.glyphs.map(\.scalar), scalars, label)
                            XCTAssertEqual(line.glyphs.map(\.characterIndex), Array(scalars.indices), label)
                            func selectedSize(_ size: CGFloat) -> CGFloat {
                                let scaled = size * expected.factor
                                return custom ? scaled : (scaled * 4).rounded() / 4
                            }
                            var expectedWidth: CGFloat = 0
                            for (position, glyph) in line.glyphs.enumerated() {
                                let token = position == expected.kept
                                let size = selectedSize(token ? expected.tokenSize! : position < 4 ? 23 : 31)
                                let units: CGFloat = token ? 1370 : scalars[position] == "A" ? 1336
                                    : scalars[position] == "B" ? 1276 : 508
                                let advance = max(units * size / 2048 + input.spacing, 0)
                                XCTAssertEqual(glyph.advance.width / prepared.source.scaleFactor, advance, label)
                                XCTAssertEqual(glyph.style.fontResource?.pointSize, size, label)
                                XCTAssertEqual(glyph.isTruncationToken, token, label)
                                XCTAssertEqual(glyph.style.tracking, kind == "tracking" ? input.spacing : nil, label)
                                XCTAssertEqual(glyph.style.kern, kind == "kern" ? input.spacing : nil, label)
                                expectedWidth += advance
                            }
                            XCTAssertEqual(line.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width + $1.kerning.x }
                                / prepared.source.scaleFactor, expectedWidth, label)
                            if custom {
                                let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                XCTAssertEqual(layout.first?.typographicBounds.width, expectedWidth, label)
                                XCTAssertEqual(layout.isTruncated, expected.kept < 11, label)
                            }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                            else { ordinary.resetCache() }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textStringDrawingFullMetricsPayloadObserved
    func testMetricsEqualityRetainsFieldsOutsideSizeAndScale() {
        let value = NSAttributedString.Metrics(size: CGSize(width: 41.5, height: 81), scale: 0.5,
            firstBaseline: 21, lastBaseline: 75, baselineAdjustment: 0.25,
            requestedWidth: 100, numberOfLines: 2, hasTruncatedRanges: true)
        var changed = value
        changed.firstBaseline = 1
        changed.lastBaseline = 2
        changed.baselineAdjustment = 3
        changed.requestedWidth = 4
        changed.numberOfLines = nil
        changed.hasTruncatedRanges = false
        XCTAssertEqual(changed, value)
        changed.size.width += 0.5
        XCTAssertNotEqual(changed, value)
        changed = value
        changed.size.height += 0.5
        XCTAssertNotEqual(changed, value)
        changed = value
        changed.scale = 1
        XCTAssertNotEqual(changed, value)

        var updated = value
        updated.update(layoutMargins: EdgeInsets(top: 0.1, leading: 2.25, bottom: 3.5, trailing: 4.125),
                       pixelLength: 1)
        XCTAssertEqual(updated.size, CGSize(width: 47.875, height: 84.6))
        XCTAssertEqual(updated.firstBaseline, 21)
        XCTAssertEqual(updated.lastBaseline, 75)
        XCTAssertEqual(updated.baselineAdjustment, -0.1, accuracy: 1e-12)
        XCTAssertEqual(updated.scale, 0.5)
        XCTAssertEqual(updated.requestedWidth, 100)
        XCTAssertEqual(updated.numberOfLines, 2)
        XCTAssertTrue(updated.hasTruncatedRanges)
        updated.update(layoutMargins: .init(), pixelLength: 0.5)
        XCTAssertEqual(updated.baselineAdjustment, 0)
        XCTAssertEqual(updated.size, CGSize(width: 47.875, height: 84.6))
    }

    // ASSERTIONS textStringDrawingCountConsumerObserved textStringDrawingCountAndTruncationProducersObserved
    // ASSERTIONS textStringDrawingMetricsCacheReuseObserved
    func testCountRequestsKeepNilEntriesAndCountActualFragments() throws {
        for (text, height, count, measuredHeight): (String, CGFloat, UInt, CGFloat) in [
            ("", 14, 0, 14), ("A", 14, 1, 27), ("\n", 54, 1, 54),
            ("\n\n", 81, 2, 81), ("A\n", 54, 2, 54), ("A\n", 14, 1, 27),
            ("\n\n\n\n", 14, 1, 27), ("\n\n\n\n", 54, 2, 54),
            ("\n\n\n\n", 81, 3, 81)
        ] {
            try withOwner(text) { owner in
                let proposal = CGSize(width: 300, height: height)
                let plain = owner.cachedMetrics(in: proposal)
                XCTAssertNil(plain.numberOfLines, text.debugDescription)
                XCTAssertEqual(owner.metricsCacheEntryCount, 1)
                let counted = owner.textSizeCacheMetrics(in: proposal)
                XCTAssertEqual(counted.0, count, text.debugDescription)
                XCTAssertEqual(counted.1.height, measuredHeight, text.debugDescription)
                XCTAssertEqual(owner.metricsCacheEntryCount, 2)
                let complete = owner.metrics(in: proposal, layoutMargins: nil)
                XCTAssertEqual(complete.numberOfLines, count)
                XCTAssertFalse(complete.hasTruncatedRanges)
                XCTAssertEqual(complete, plain)
                XCTAssertNil(owner.cachedMetrics(in: proposal).numberOfLines)
                XCTAssertEqual(owner.metricsCacheEntryCount, 2)
            }
        }
        for (limit, count, height): (Int, UInt, CGFloat) in [(1, 1, 33), (2, 2, 87), (3, 3, 93)] {
            try withOwner("\n\n\n\n", configure: { $0.lineLimit = limit; $0.lineSpacing = 6 }) { owner in
                let result = owner.metrics(in: CGSize(width: 300, height: 99), layoutMargins: nil)
                XCTAssertEqual(result.numberOfLines, count)
                XCTAssertEqual(result.size.height, height)
                XCTAssertFalse(result.hasTruncatedRanges)
            }
        }
    }

    // ASSERTIONS textStringDrawingMetricsCacheReuseObserved textStringDrawingFullMetricsPayloadObserved
    func testOverlappingCacheIntervalsReturnTheFirstCompleteEligibleValue() throws {
        try withOwner("A") { owner in
            let first = owner.cachedMetrics(in: CGSize(width: 100, height: 81))
            let second = owner.cachedMetrics(in: CGSize(width: 300, height: 120))
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.requestedWidth, 100)
            XCTAssertEqual(second.requestedWidth, 300)
            let overlap = CGSize(width: 50, height: 54)
            XCTAssertEqual(owner.cachedMetrics(in: overlap).requestedWidth, 100)
            XCTAssertEqual(owner.cachedMetrics(in: first.size).requestedWidth, 100)
            XCTAssertEqual(owner.metricsCacheEntryCount, 2)
            let counted = owner.metrics(in: overlap, layoutMargins: nil)
            XCTAssertEqual(counted.numberOfLines, 1)
            XCTAssertEqual(counted.requestedWidth, 50)
            XCTAssertEqual(owner.metricsCacheEntryCount, 3)
            XCTAssertEqual(owner.cachedMetrics(in: overlap).requestedWidth, 100)
            XCTAssertNil(owner.cachedMetrics(in: overlap).numberOfLines)
            XCTAssertEqual(owner.metrics(in: first.size, layoutMargins: nil).requestedWidth, 50)
            XCTAssertEqual(owner.metricsCacheEntryCount, 3)
        }
    }

    // ASSERTIONS textStringDrawingFullMetricsPayloadObserved textStringDrawingMarginPublicationObserved
    // ASSERTIONS textStringDrawingCountConsumerObserved
    func testCompleteMetricsPreserveRequestedWidthAndBaselineAdjustment() throws {
        let margins = EdgeInsets(top: 0.1, leading: 2.25, bottom: 3.5, trailing: 4.125)
        for width: CGFloat in [300, 6.375] {
            try withOwner("A") { owner in
                let proposal = CGSize(width: width, height: 81)
                let result = owner.metrics(in: proposal, layoutMargins: margins)
                XCTAssertEqual(result.requestedWidth, width - 6.375)
                XCTAssertEqual(result.size.height, 30.6)
                XCTAssertEqual(result.firstBaseline, 21)
                XCTAssertEqual(result.lastBaseline, 21)
                XCTAssertEqual(result.baselineAdjustment, -0.1, accuracy: 1e-12)
                XCTAssertEqual(result.numberOfLines, 1)
                // A hit returns the whole stored payload, including its original margins.
                let repeated = owner.metrics(in: proposal, layoutMargins: nil)
                XCTAssertEqual(repeated.baselineAdjustment, result.baselineAdjustment)
                XCTAssertEqual(repeated.requestedWidth, result.requestedWidth)
                XCTAssertEqual(repeated.size, result.size)
                XCTAssertEqual(owner.metricsCacheEntryCount, 1)
            }
        }
        try withOwner("A", configure: { $0.bodyHeadOutdent = 6 }) { owner in
            let proposal = CGSize(width: 300, height: 81)
            let result = owner.cachedMetrics(in: proposal)
            XCTAssertEqual(result.requestedWidth, 306)
            XCTAssertEqual(result.numberOfLines, 1)
            XCTAssertEqual(owner.textSizeCacheMetrics(in: proposal).0, 1)
            XCTAssertEqual(owner.metricsCacheEntryCount, 1)
        }
    }

    // ASSERTIONS textStringDrawingTruncationRangeCreationObserved textStringDrawingCountAndTruncationProducersObserved
    func testOnlyAcceptedTruncationCandidatesPublishRanges() throws {
        for mode: Text.TruncationMode in [.head, .middle, .tail] {
            for width: CGFloat in [0, 1, 15, 25, 50] {
                try withOwner("ABCDEFGHIJK", configure: { $0.lineLimit = 1; $0.truncationMode = mode }) { owner in
                    let result = owner.metrics(in: CGSize(width: width, height: 81), layoutMargins: nil)
                    XCTAssertEqual(result.hasTruncatedRanges, width >= 25)
                    XCTAssertEqual(result.numberOfLines, 1)
                    let source = try XCTUnwrap(owner.resolvedText)
                    let layout = source.makeGlyphLayout(maxWidth: Int(width * source.scaleFactor),
                        maximumHeight: 81 * source.scaleFactor, lineLimit: 1, truncationMode: mode)
                    let expected: Range<Int> = width == 25 ? 0..<11
                        : mode == .head ? 0..<8 : mode == .middle ? 1..<10 : 2..<11
                    XCTAssertEqual(layout.truncatedRanges, width >= 25 ? [expected] : [])
                }
            }
            for text in ["A\nB", "A\r\nB", "A\u{2028}B"] {
                try withOwner(text, configure: { $0.lineLimit = 1; $0.truncationMode = mode }) { owner in
                    XCTAssertFalse(owner.metrics(in: CGSize(width: 50, height: 14),
                        layoutMargins: nil).hasTruncatedRanges, "\(text.debugDescription) \(mode)")
                    let source = try XCTUnwrap(owner.resolvedText)
                    let layout = source.makeGlyphLayout(maxWidth: Int(50 * source.scaleFactor),
                        maximumHeight: 14 * source.scaleFactor, lineLimit: 1, truncationMode: mode)
                    XCTAssertEqual(layout.lines.flatMap(\.glyphs).map { $0.scalar.value },
                                   mode == .tail ? [0x41, 0x2026] : [0x41])
                    XCTAssertFalse(layout.lines.contains { $0.isTruncated })
                    XCTAssertTrue(layout.truncatedRanges.isEmpty)
                }
            }
            try withOwner(String(repeating: "e\u{0301}", count: 5), configure: {
                $0.lineLimit = 1; $0.truncationMode = mode
            }) { owner in
                let result = owner.metrics(in: CGSize(width: 25, height: 81), layoutMargins: nil)
                XCTAssertTrue(result.hasTruncatedRanges)
                let source = try XCTUnwrap(owner.resolvedText)
                XCTAssertEqual(source.makeGlyphLayout(maxWidth: Int(25 * source.scaleFactor),
                    maximumHeight: 81 * source.scaleFactor, lineLimit: 1,
                    truncationMode: mode).truncatedRanges, [0..<10])
            }
        }
    }

    // ASSERTIONS textStringDrawingMultilineFittingObserved textStringDrawingFullMetricsPayloadObserved
    // ASSERTIONS textStringDrawingCountAndTruncationProducersObserved
    func testFittingPublishesTheFinalCountScaleAndTruncation() throws {
        for (minimum, scale, count, height, truncated): (CGFloat, CGFloat, UInt, CGFloat, Bool) in [
            (0.25, 0.578125, 2, 30, false), (0.6, 0.6, 1, 16, true)
        ] {
            try withOwner("A A A A A A", configure: { $0.minimumScaleFactor = minimum }) { owner in
                let proposal = CGSize(width: 50, height: 30)
                let plain = owner.cachedMetrics(in: proposal)
                let result = owner.metrics(in: proposal, layoutMargins: nil)
                XCTAssertEqual(result.scale, scale)
                XCTAssertEqual(result.numberOfLines, count)
                XCTAssertEqual(result.size.height, height)
                XCTAssertEqual(result.hasTruncatedRanges, truncated)
                XCTAssertEqual(result.requestedWidth, 50)
                XCTAssertEqual(result, plain)
                XCTAssertNil(plain.numberOfLines)
                let source = try XCTUnwrap(owner.drawingSource(in: proposal))
                XCTAssertEqual(source.uniformFont?.pointSize, minimum == 0.25 ? 13.25 : 13.75)
                XCTAssertEqual(owner.resolvedText?.uniformFont?.pointSize, 23)
                XCTAssertEqual(owner.metricsCacheEntryCount, 2)
            }
        }
    }

    // ASSERTIONS textStringDrawingKitCacheOwnershipObserved textStringDrawingMetricsCacheReuseObserved
    func testPreparedLayoutSurvivesConstraintAndCountMissesAndDrawing() throws {
        for text in ["A", "A\n", "A A A A A A"] {
            try withOwner(text) { owner in
                XCTAssertNil(owner.preparedLayout)
                let large = CGSize(width: 300, height: 81)
                _ = owner.cachedMetrics(in: large)
                let prepared = try XCTUnwrap(owner.preparedLayout)
                let count = owner.metricsCacheEntryCount
                _ = owner.metrics(in: large, layoutMargins: nil)
                XCTAssertEqual(owner.metricsCacheEntryCount, count + 1)
                XCTAssertTrue(owner.preparedLayout === prepared)
                _ = owner.cachedMetrics(in: CGSize(width: 50, height: 60))
                _ = owner.cachedMetrics(in: CGSize(width: 400, height: 120))
                let beforeDraw = owner.metricsCacheEntryCount
                let drawing = try XCTUnwrap(owner.drawingGlyphs(in: large))
                XCTAssertFalse(drawing.lines.flatMap(\.glyphs).isEmpty)
                XCTAssertEqual(owner.metricsCacheEntryCount, beforeDraw)
                XCTAssertTrue(owner.preparedLayout === prepared)
                let independent = ResolvedStyledText.StringDrawing(resolvedText: owner.resolvedText)
                XCTAssertNil(independent.preparedLayout)
                XCTAssertEqual(independent.metricsCacheEntryCount, 0)
                _ = independent.cachedMetrics(in: large)
                XCTAssertFalse(independent.preparedLayout === prepared)
                XCTAssertTrue(owner.preparedLayout === prepared)
            }
        }
        for text in ["", "\n\n"] {
            try withOwner(text) { owner in
                _ = owner.metrics(in: CGSize(width: 300, height: 81), layoutMargins: nil)
                _ = owner.drawingGlyphs(in: CGSize(width: 300, height: 81))
                XCTAssertEqual(owner.metricsCacheEntryCount, 1)
                XCTAssertNil(owner.preparedLayout)
            }
        }
    }

    // ASSERTIONS textStringDrawingCacheInvalidationObserved textStringDrawingScaleOverrideReconstructionObserved
    func testOverrideRebuildsOriginalFontsAndResetsEvenForEqualAssignments() throws {
        for (text, halfHeight): (String, CGFloat) in [("A", 14), ("A\n", 28), ("\n\n", 42), ("", 14)] {
            try withOwner(text) { owner in
                let size = CGSize(width: 300, height: 81)
                let original = owner.metrics(in: size, layoutMargins: nil)
                let storage = owner.storage
                for scale: CGFloat? in [0.5, 0.5, 0.333, 0.75, 1, nil] {
                    weak var oldLayout = owner.preparedLayout
                    XCTAssertGreaterThan(owner.metricsCacheEntryCount, 0)
                    owner.scaleFactorOverride = scale
                    XCTAssertEqual(owner.metricsCacheEntryCount, 0)
                    XCTAssertNil(owner.preparedLayout)
                    XCTAssertNil(oldLayout)
                    XCTAssertTrue(owner.storage === storage)
                    let result = owner.metrics(in: size, layoutMargins: nil)
                    XCTAssertEqual(result.scale, 1)
                    if scale == 0.5 { XCTAssertEqual(result.size.height, halfHeight) }
                    if scale == 1 || scale == nil { XCTAssertEqual(result, original) }
                    XCTAssertEqual(owner.drawingScale(size: size), scale ?? 1)
                    let source = try XCTUnwrap(owner.drawingSource(in: size))
                    if !text.isEmpty {
                        XCTAssertEqual(source.uniformFont?.pointSize,
                            scale == 0.5 ? 11.5 : scale == 0.333 ? 7.75 : scale == 0.75 ? 17.25 : 23)
                        XCTAssertEqual(owner.resolvedText?.uniformFont?.pointSize, 23)
                    }
                }
            }
        }
    }

    // ASSERTIONS textStringDrawingScaleOverrideReconstructionObserved textStringDrawingScaledDrawingCacheGateObserved
    func testOverrideDisablesFittingAndManagerResetRemainsIndependent() throws {
        try withOwner("A A A A A A", configure: { $0.minimumScaleFactor = 0.25 }) { owner in
            let size = CGSize(width: 50, height: 30)
            let original = owner.metrics(in: size, layoutMargins: nil)
            XCTAssertEqual(original.scale, 0.578125)
            XCTAssertNil(owner.preparedLayout)
            _ = owner.drawingGlyphs(in: size)
            XCTAssertNil(owner.preparedLayout)
            let manager = ResolvedStyledText.TextLayoutManager(resolvedText: owner.resolvedText)
            let managerMetrics = manager.cachedLayoutMetrics(in: size)
            manager.scaleFactorOverride = 0.5
            XCTAssertEqual(manager.metricsCacheEntryCount, 1)
            XCTAssertEqual(manager.cachedLayoutMetrics(in: size), managerMetrics)
            owner.scaleFactorOverride = 0.5
            let small = CGSize(width: 20, height: 10)
            let fixed = owner.metrics(in: small, layoutMargins: nil)
            XCTAssertEqual(fixed.scale, 1)
            XCTAssertEqual(fixed.size.height, 14)
            XCTAssertNotNil(owner.preparedLayout)
            XCTAssertEqual(owner.drawingScale(size: small), 0.5)
            owner.scaleFactorOverride = nil
            XCTAssertEqual(owner.metrics(in: size, layoutMargins: nil), original)
            XCTAssertNil(owner.preparedLayout)
            _ = owner.metrics(in: CGSize(width: 300, height: 81), layoutMargins: nil)
            XCTAssertNil(owner.preparedLayout)
        }
    }

    // ASSERTIONS textStringDrawingScaleOverrideReconstructionObserved
    func testMixedFontOverridePreservesRunAttributesAndOriginalStorage() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let text = Text(verbatim: "A").baselineOffset(3).kerning(1.7)
            + Text(verbatim: "B").font(.file(file, size: 15)).tracking(2.3)
        try withOwner(text) { owner in
            let size = CGSize(width: 300, height: 81)
            let original = owner.storage
            for (scale, sizes): (CGFloat?, [CGFloat]) in [(0.333, [7.75, 5]), (0.75, [17.25, 11.25]), (nil, [23, 15])] {
                owner.scaleFactorOverride = scale
                let source = try XCTUnwrap(owner.drawingSource(in: size))
                let attributes = source.runs.compactMap { run -> _ResolvedTextRunAttributes? in
                    if case let .styledText(_, _, _, attributes) = run { return attributes }
                    return nil
                }
                XCTAssertEqual(attributes.compactMap { $0.fontResource?.pointSize }, sizes)
                XCTAssertEqual(attributes[0].baselineOffset, 3)
                XCTAssertEqual(attributes[0].kern, 1.7)
                XCTAssertEqual(attributes[1].tracking, 2.3)
                XCTAssertTrue(owner.storage === original)
            }
        }
    }

    // ASSERTIONS textManagerIdealCacheIsolationObserved textManagerSpacingIdealLifecycleObserved
    func testManagerSpacingKeepsOrdinaryMeasurementsSeparate() throws {
        for text in ["", "A", "A\nB"] {
            for order in 0..<3 {
                try withManager(Text(verbatim: text)) { manager in
                    let request = CGSize(width: 50, height: 30)
                    let ideal = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
                    if order == 1 { _ = manager.metrics(in: request, layoutMargins: nil) }
                    if order == 2 { _ = manager.metrics(in: ideal, layoutMargins: nil) }
                    let originalCount = manager.metricsCacheEntryCount
                    let spacing = manager.spacing()
                    XCTAssertEqual(manager.metricsCacheEntryCount, originalCount)
                    XCTAssertEqual(manager.spacing(), spacing)
                    XCTAssertEqual(manager.metricsCacheEntryCount, originalCount)

                    let measured = manager.metrics(in: request, layoutMargins: nil)
                    let measuredCount = manager.metricsCacheEntryCount
                    XCTAssertEqual(manager.spacing(), spacing)
                    XCTAssertEqual(manager.metricsCacheEntryCount, measuredCount)
                    XCTAssertEqual(manager.metrics(in: request, layoutMargins: nil), measured)
                    manager.scaleFactorOverride = 0.5
                    XCTAssertEqual(manager.spacing(), spacing)
                    manager.scaleFactorOverride = nil
                    XCTAssertEqual(manager.spacing(), spacing)
                    XCTAssertEqual(manager.metricsCacheEntryCount, measuredCount)
                }
            }
        }
    }

    // ASSERTIONS textManagerSpacingUnitScaleObserved textManagerSpacingIdealLifecycleObserved
    func testManagerIdealMetricsStayAtUnitScaleAndSurviveReset() throws {
        for text in ["", "A", "\n", "A\n", "A\nB", "A A A A A A"] {
            try withManager(Text(verbatim: text), configure: { $0.minimumScaleFactor = 0.25 }) { manager in
                XCTAssertNil(manager.cache.ideal)
                manager.scaleFactorOverride = 0.5
                let spacing = manager.spacing()
                let ideal = try XCTUnwrap(manager.cache.ideal)
                XCTAssertEqual(ideal.scale, 1)
                XCTAssertEqual(ideal.requestedWidth, .infinity)
                XCTAssertNotNil(ideal.numberOfLines)
                XCTAssertTrue(manager.cache.entries.isEmpty)

                let measured = manager.metrics(in: CGSize(width: 50, height: 30), layoutMargins: nil)
                XCTAssertEqual(measured.requestedWidth, 50)
                XCTAssertEqual(manager.cache.entries.count, 1)
                XCTAssertEqual(manager.cache.ideal, ideal)
                manager.scaleFactorOverride = nil
                manager.resetCache()
                XCTAssertEqual(manager.spacing(), spacing)
                XCTAssertEqual(manager.cache.ideal, ideal)
                XCTAssertEqual(manager.cache.entries.count, 1)
            }
        }
        let unresolved = ResolvedStyledText.TextLayoutManager()
        XCTAssertTrue(unresolved.spacing().minima.isEmpty)
        XCTAssertNil(unresolved.cache.ideal)
        XCTAssertTrue(unresolved.cache.entries.isEmpty)
    }

    // ASSERTIONS textManagerMeasuredSizeLookupObserved
    func testManagerMeasuredSizeLookupUsesExactDimensionsAndFirstEntry() throws {
        typealias Cache = ResolvedStyledText.TextLayoutManager.Cache
        let metrics = NSAttributedString.Metrics(size: CGSize(width: 20, height: 30), scale: 1,
            firstBaseline: 21, lastBaseline: 21, baselineAdjustment: 0, requestedWidth: 80,
            numberOfLines: 1, hasTruncatedRanges: false)
        var cache = Cache(entries: [], ideal: metrics)
        XCTAssertNil(cache.find(measuredSize: metrics.size))
        cache.entries = [.init(request: CGSize(width: 80, height: 100), metrics: metrics),
                         .init(request: CGSize(width: 120, height: 160), metrics: metrics)]
        XCTAssertEqual(try XCTUnwrap(cache.find(measuredSize: metrics.size)).request, CGSize(width: 80, height: 100))
        XCTAssertNil(cache.find(measuredSize: CGSize(width: 20.25, height: 30)))
        XCTAssertNil(cache.find(measuredSize: CGSize(width: 20, height: 30.25)))
        XCTAssertNil(cache.find(measuredSize: CGSize(width: 80, height: 100)))
        cache.entries.reverse()
        XCTAssertEqual(try XCTUnwrap(cache.find(measuredSize: metrics.size)).request, CGSize(width: 120, height: 160))
    }

    // ASSERTIONS textManagerMeasuredSizeLookupObserved
    // ASSERTIONS textManagerPreparedDrawingRequestObserved
    func testManagerDrawingRestoresTheFirstMeasuredRequestWithoutAddingEntries() throws {
        for alignment: TextAlignment in [.leading, .center, .trailing] {
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                try withManager(Text(verbatim: "A\nBB").baselineOffset(0.2), configure: {
                    $0.multilineTextAlignment = alignment
                    $0.layoutDirection = direction
                }) { manager in
                    let first = manager.metrics(in: CGSize(width: 80, height: 120), layoutMargins: nil)
                    let second = manager.metrics(in: CGSize(width: 120, height: 160), layoutMargins: nil)
                    XCTAssertEqual(first.size, second.size)
                    XCTAssertEqual(manager.cache.entries.count, 2)
                    let rect = CGRect(origin: CGPoint(x: 11, y: 13), size: first.size)
                    let factor: CGFloat = alignment == .center ? 0.5 :
                        ((alignment == .leading) == (direction == .rightToLeft) ? 1 : 0)
                    for _ in 0..<2 {
                        let prepared = try XCTUnwrap(manager.prepareDrawing(in: rect, with: first.size,
                            applyingMarginOffsets: false))
                        XCTAssertEqual(prepared.bounds.width, 80)
                        XCTAssertEqual(prepared.bounds.height, first.size.height)
                        XCTAssertEqual(prepared.bounds.minX, 11 - (80 - first.size.width) * factor)
                        XCTAssertEqual(prepared.bounds.minY, 13 + first.baselineAdjustment, accuracy: 1e-9)
                        XCTAssertEqual(prepared.lines.count, 2)
                        for line in prepared.lines {
                            XCTAssertEqual(line.originX, (80 * prepared.source.scaleFactor - line.width) * factor)
                        }
                        let layout = try XCTUnwrap(manager.makeLayout(in: rect, with: first.size,
                            shading: .color(.black), layoutDirection: direction))
                        XCTAssertEqual(layout.count, 2)
                        for (line, glyphs) in zip(layout, prepared.lines) {
                            XCTAssertEqual(line.origin.x,
                                11 + manager.drawingMargins.leading +
                                    (first.size.width - glyphs.width / prepared.source.scaleFactor) * factor,
                                accuracy: 1e-9)
                        }
                        XCTAssertEqual(manager.cache.entries.count, 2)
                        XCTAssertNil(manager.cache.ideal)
                    }
                    let missedSize = CGSize(width: first.size.width + 0.25, height: first.size.height)
                    let missed = try XCTUnwrap(manager.prepareDrawing(in: rect, with: missedSize,
                        applyingMarginOffsets: false))
                    XCTAssertEqual(missed.bounds.width, missedSize.width)
                    XCTAssertEqual(missed.bounds.minX, 11)
                    XCTAssertEqual(manager.cache.entries.count, 2)
                }
            }
        }
    }

    // ASSERTIONS textManagerPreparedDrawingRequestObserved
    func testManagerDrawingDoesNotSelectIdealOrRestoreAnInfiniteRequest() throws {
        try withManager(Text(verbatim: "A\nBB")) { manager in
            _ = manager.spacing()
            let ideal = try XCTUnwrap(manager.cache.ideal)
            let rect = CGRect(origin: .zero, size: ideal.size)
            let cold = try XCTUnwrap(manager.prepareDrawing(in: rect, with: ideal.size, applyingMarginOffsets: true))
            XCTAssertEqual(cold.bounds.size, ideal.size)
            XCTAssertEqual(cold.bounds.origin.x, manager.drawingMargins.leading)
            XCTAssertTrue(manager.cache.entries.isEmpty)
            let ordinary = manager.metrics(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity), layoutMargins: nil)
            let prepared = try XCTUnwrap(manager.prepareDrawing(in: rect, with: ordinary.size, applyingMarginOffsets: true))
            XCTAssertEqual(prepared.bounds.size, ordinary.size)
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertEqual(manager.cache.ideal, ideal)
        }
    }

    // ASSERTIONS textManagerMetricsPublicationObserved
    func testManagerRoundsBaselinesAfterApplyingItsOwnMargins() throws {
        try withManager(Text(verbatim: "A").baselineOffset(0.2)) { manager in
            let size = CGSize(width: 7, height: 81)
            XCTAssertEqual(manager.size(in: size), CGSize(width: 7, height: 27.5))
            XCTAssertEqual(manager.firstBaseline(in: size), 21)
            XCTAssertEqual(manager.lastBaseline(in: size), 21)
        }
        try withManager(Text(verbatim: "A").baselineOffset(0.2)) { manager in
            manager.layoutMargins = EdgeInsets(top: 0.1, leading: 2.25, bottom: 3.5, trailing: 4.125)
            let size = CGSize(width: 6.375, height: 81)
            XCTAssertEqual(manager.size(in: size), CGSize(width: 6.875, height: 31.1))
            XCTAssertEqual(manager.firstBaseline(in: size), 21.5)
            XCTAssertEqual(manager.lastBaseline(in: size), 21.5)
        }
    }

    // ASSERTIONS textManagerMetricsCacheAndCountObserved textManagerLayoutInfoObserved
    func testManagerPublishesCountsWithItsFirstMeasurement() throws {
        for (text, count, height, first, last): (String, UInt, CGFloat, CGFloat, CGFloat) in [
            ("", 0, 14, 0, 0), ("A", 1, 27, 21, 21), ("\n", 2, 28, 21, 25),
            ("\n\n", 3, 55, 21, 52), ("A\n", 2, 54, 21, 48), ("A\nB", 2, 54, 21, 48)
        ] {
            try withManager(Text(verbatim: text)) { manager in
                let request = CGSize(width: 300, height: 81)
                let measured = manager.size(in: request)
                XCTAssertEqual(measured.height, height, text.debugDescription)
                XCTAssertEqual(manager.metricsCacheEntryCount, 1)
                let counted = manager.textSizeCacheMetrics(in: request)
                XCTAssertEqual(counted.0, count, text.debugDescription)
                XCTAssertEqual(counted.1, measured)
                let complete = manager.metrics(in: request, layoutMargins: nil)
                XCTAssertEqual(complete.numberOfLines, count)
                XCTAssertEqual(complete.firstBaseline, first)
                XCTAssertEqual(complete.lastBaseline, last)
                XCTAssertEqual(complete.baselineAdjustment, 0)
                XCTAssertEqual(complete.scale, 1)
                XCTAssertEqual(complete.requestedWidth, 300)
                XCTAssertFalse(complete.hasTruncatedRanges)
                XCTAssertEqual(manager.metricsCacheEntryCount, 1)
                manager.scaleFactorOverride = 0.5
                XCTAssertEqual(manager.textSizeCacheMetrics(in: request).0, count)
                manager.scaleFactorOverride = nil
                XCTAssertEqual(manager.metricsCacheEntryCount, 1)
            }
        }
    }

    // ASSERTIONS textManagerMetricsCacheAndCountObserved textManagerMetricsPublicationObserved
    func testManagerReusesCompleteFirstIntervalAndIgnoresSuppliedMargins() throws {
        try withManager(Text(verbatim: "A").baselineOffset(0.2)) { manager in
            let firstRequest = CGSize(width: 100, height: 81)
            let ignored = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            let first = manager.metrics(in: firstRequest, layoutMargins: ignored)
            XCTAssertEqual(first.numberOfLines, 1)
            XCTAssertEqual(first.firstBaseline, 21)
            XCTAssertEqual(first.baselineAdjustment, -0.2, accuracy: 1e-12)
            XCTAssertEqual(first.requestedWidth, 100)
            XCTAssertEqual(first.size.height, 27.5)
            let second = manager.metrics(in: CGSize(width: 300, height: 120), layoutMargins: nil)
            XCTAssertEqual(second.requestedWidth, 300)
            let overlap = manager.metrics(in: CGSize(width: 50, height: 54), layoutMargins: ignored)
            XCTAssertEqual(overlap.requestedWidth, 100)
            XCTAssertEqual(overlap.baselineAdjustment, first.baselineAdjustment)
            XCTAssertEqual(manager.metrics(in: first.size, layoutMargins: nil).requestedWidth, 100)
            XCTAssertEqual(manager.metricsCacheEntryCount, 2)
        }
    }

    // ASSERTIONS textManagerLayoutInfoObserved textManagerMetricsCacheAndCountObserved
    func testManagerCountsExtraFragmentsAndUnlaidParagraphs() throws {
        for (text, height, limit, count, truncated): (String, CGFloat, Int?, UInt, Bool) in [
            ("", 14, 1, 0, false), ("\n", 14, 1, 2, false),
            ("\n\n", 0, nil, 1, true), ("\n\n", 14, 2, 1, true),
            ("\n\n", 54, 1, 1, true), ("\n\n", 54, 2, 3, false),
            ("A\n", 0, nil, 1, false), ("A\n", 14, nil, 2, false),
            ("A\n", 14, 1, 1, false), ("A\n", 54, 2, 2, false),
            ("A\nB", 0, nil, 1, true), ("A\nB", 14, 2, 1, true),
            ("A\nB", 54, 1, 1, true), ("A\nB", 54, 2, 2, false)
        ] {
            try withManager(Text(verbatim: text), configure: { $0.lineLimit = limit }) { manager in
                let request = CGSize(width: 300, height: height)
                let complete = manager.metrics(in: request, layoutMargins: nil)
                XCTAssertEqual(complete.numberOfLines, count, "\(text.debugDescription), \(height), \(String(describing: limit))")
                XCTAssertEqual(complete.hasTruncatedRanges, truncated, text.debugDescription)
                XCTAssertEqual(manager.textSizeCacheMetrics(in: request).0, count)
                XCTAssertEqual(manager.metricsCacheEntryCount, 1)
            }
        }
        for width: CGFloat in [0, 0.01, 1, 50] {
            for (text, truncated): (String, Bool) in [("A\n", false), ("A\nB", true), ("A A A A A A", width == 50)] {
                try withManager(Text(verbatim: text), configure: { $0.lineLimit = 1 }) { manager in
                    let complete = manager.metrics(in: CGSize(width: width, height: 81), layoutMargins: nil)
                    XCTAssertEqual(complete.numberOfLines, 1)
                    XCTAssertEqual(complete.hasTruncatedRanges, truncated, "\(text.debugDescription), \(width)")
                    if width <= 1 { XCTAssertEqual(complete.size.width, width == 1 ? 1 : 0.5) }
                }
            }
        }
        try withManager(Text(verbatim: "A")) { manager in
            XCTAssertEqual(manager.sizeThatFits(.zero), .zero)
            XCTAssertEqual(manager.metricsCacheEntryCount, 0)
            let count = manager.textSizeCacheMetrics(in: .zero)
            XCTAssertEqual(count.0, 1)
            XCTAssertEqual(count.1, CGSize(width: 0.5, height: 27))
            XCTAssertEqual(manager.metricsCacheEntryCount, 1)
        }
    }

    // ASSERTIONS textManagerBackendConfigurationReuseObserved
    // ASSERTIONS textManagerPreparedLayoutReuseObserved
    func testManagerBackendKeepsOnlyTheCurrentLayoutConfiguration() {
        let cache = ResolvedStyledText.TextLayoutManager.GlyphLayoutCache()
        var calls = 0
        func request(_ size: CGSize = CGSize(width: 80, height: 120),
                     limit: Int? = nil, mode: Text.TruncationMode = .tail) -> Int {
            cache.layout(in: size, lineLimit: limit, truncationMode: mode) {
                calls += 1
                return .init(lines: [], lineCount: calls, forcedClusterBreak: true,
                             truncatedRanges: [2..<7], hasUnlaidText: true)
            }.lineCount
        }
        XCTAssertEqual(request(), 1)
        XCTAssertEqual(request(), 1)
        XCTAssertEqual(request(CGSize(width: 80.25, height: 120)), 2)
        XCTAssertEqual(request(CGSize(width: 80.25, height: 120)), 2)
        XCTAssertEqual(request(), 3)
        XCTAssertEqual(request(CGSize(width: 80, height: 121)), 4)
        XCTAssertEqual(request(limit: 1), 5)
        XCTAssertEqual(request(limit: 1), 5)
        XCTAssertEqual(request(limit: 2), 6)
        XCTAssertEqual(request(limit: 2, mode: .head), 7)
        XCTAssertEqual(request(limit: 2, mode: .head), 7)
        XCTAssertEqual(request(limit: 2, mode: .middle), 8)
        let cached = cache.layout(in: CGSize(width: 80, height: 120), lineLimit: 2, truncationMode: .middle) {
            XCTFail("An unchanged backend configuration must reuse its complete layout")
            return .init(lines: [], lineCount: 0, forcedClusterBreak: false,
                         truncatedRanges: [], hasUnlaidText: false)
        }
        XCTAssertTrue(cached.forcedClusterBreak)
        XCTAssertTrue(cached.hasUnlaidText)
        XCTAssertEqual(cached.truncatedRanges, [2..<7])
        cache.purgeResources(reason: .lowMemory)
        XCTAssertEqual(request(limit: 2, mode: .middle), 9)
        cache.purgeResources(reason: .appTermination)
        XCTAssertEqual(request(), 0)
        XCTAssertEqual(calls, 9)
    }

    // ASSERTIONS textManagerBackendConfigurationReuseObserved
    // ASSERTIONS textManagerPreparedDrawingRequestObserved
    func testManagerDrawingSharesBackendStateWithoutChangingScalarCachesOrCachedPositions() throws {
        try withManager(Text(verbatim: "A\nBB"), configure: { $0.multilineTextAlignment = .center }) { manager in
            let metrics = manager.metrics(in: CGSize(width: 80, height: 120), layoutMargins: nil)
            let rect = CGRect(origin: .zero, size: metrics.size)
            let first = try XCTUnwrap(manager.prepareDrawing(in: rect, with: metrics.size,
                applyingMarginOffsets: true))
            let raw = manager.glyphLayoutCache.layout(in: CGSize(width: 80, height: metrics.size.height),
                lineLimit: nil, truncationMode: .tail) {
                XCTFail("Drawing must publish its backend layout on the retained owner")
                return .init(lines: [], lineCount: 0, forcedClusterBreak: false,
                             truncatedRanges: [], hasUnlaidText: false)
            }
            XCTAssertEqual(raw.lines.count, first.lines.count)
            XCTAssertTrue(raw.lines.allSatisfy { $0.originX == 0 })
            XCTAssertTrue(first.lines.contains { $0.originX != 0 })
            manager.resetCache()
            let second = try XCTUnwrap(manager.prepareDrawing(in: rect, with: metrics.size,
                applyingMarginOffsets: true))
            XCTAssertEqual(first.lines.map(\.originX), second.lines.map(\.originX))
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertNil(manager.cache.ideal)
            manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
            let rebuilt = try XCTUnwrap(manager.prepareDrawing(in: rect, with: metrics.size,
                applyingMarginOffsets: true))
            XCTAssertEqual(first.lines.map(\.width), rebuilt.lines.map(\.width))
            XCTAssertEqual(first.lines.map(\.baseline), rebuilt.lines.map(\.baseline))
            XCTAssertEqual(manager.cache.entries.count, 1)
        }
    }

    // ASSERTIONS textManagerMixedFitting27Observed textManagerMixedDrawing27Observed
    func testManagerFitsMixedFontRunsAndPreparesTheSelectedSizes() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let text = Text(verbatim: "AAA AAA ")
            + Text(verbatim: "BBB BBB").font(.file(file, size: 31)).foregroundColor(.red)
        func sizes(_ source: ResolvedTextSource) -> [CGFloat] {
            source.runs.compactMap {
                guard case let .styledText(_, _, _, attributes) = $0 else { return nil }
                return attributes.fontResource?.pointSize
            }
        }
        for (width, height, minimum, limit, selected, expectedSize, truncated):
            (CGFloat, CGFloat, CGFloat, Int, CGFloat, CGSize, Bool) in [
                (80, 60, 0.25, 1, 0.35546875, CGSize(width: 80, height: 13), false),
                (80, 18, 0.5, 1, 0.5, CGSize(width: 71, height: 18), true),
                (300, 60, 1, 1, 1, CGSize(width: 225.5, height: 37), false),
                (120, 60, 0.25, 2, 0.958984375, CGSize(width: 119, height: 60), false)
            ] {
            try withManager(text, configure: {
                $0.lineLimit = limit
                $0.minimumScaleFactor = minimum
            }) { manager in
                let original = try XCTUnwrap(manager.resolvedText)
                let storage = manager.storage
                XCTAssertNil(original.uniformFont)
                _ = manager.spacing()
                let ideal = manager.cache.ideal
                let metrics = manager.metrics(in: CGSize(width: width, height: height), layoutMargins: nil)
                XCTAssertEqual(metrics.scale, selected)
                XCTAssertEqual(metrics.size, expectedSize)
                XCTAssertEqual(metrics.numberOfLines, UInt(limit))
                XCTAssertEqual(metrics.hasTruncatedRanges, truncated)
                let prepared = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: metrics.size,
                    applyingMarginOffsets: true))
                XCTAssertEqual(sizes(prepared.source), [23 * selected, 31 * selected])
                XCTAssertEqual(sizes(original), [23, 31])
                XCTAssertTrue(manager.storage === storage)
                XCTAssertEqual(manager.cache.entries.count, 1)
                XCTAssertEqual(manager.cache.ideal, ideal)
                let layout = try XCTUnwrap(manager.makeLayout(in: .zero, with: metrics.size,
                    shading: .color(.black), layoutDirection: .leftToRight))
                XCTAssertEqual(layout.isTruncated, truncated)
                manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
                let rebuilt = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: metrics.size,
                    applyingMarginOffsets: true))
                XCTAssertEqual(sizes(rebuilt.source), sizes(prepared.source))
                XCTAssertEqual(rebuilt.lines.map(\.width), prepared.lines.map(\.width))
                XCTAssertEqual(manager.cache.entries.count, 1)
            }
        }
    }

    // ASSERTIONS textStringMixedSearch27Observed textStringMixedFontCopy27Observed
    func testStringDrawingFitsMixedRunsWithQuarterPointFonts() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        func text(_ sizes: [CGFloat], offset: Bool) -> Text {
            var second = Text(verbatim: "BBB BBB").font(.file(file, size: sizes[1])).foregroundColor(.red)
            if offset { second = second.baselineOffset(3).kerning(1.5) }
            return Text(verbatim: "AAA AAA ").font(.file(file, size: sizes[0])) + second
        }
        func attributes(_ source: ResolvedTextSource) -> [_ResolvedTextRunAttributes] {
            source.runs.compactMap {
                guard case let .styledText(_, _, _, attributes) = $0 else { return nil }
                return attributes
            }
        }
        for offset in [false, true] {
            for (width, height, minimum, limit, factor, expectedHeight): (CGFloat, CGFloat, CGFloat, Int, CGFloat, CGFloat) in [
                (80, 60, 0.25, 1, offset ? 0.30859375 : 0.349609375, offset ? 14 : 13),
                (80, 18, 0.5, 1, 0.5, offset ? 21 : 18),
                (120, 60, 0.25, 2, offset ? 0.8828125 : 0.958984375, offset ? 59 : 60)
            ] {
                let request = CGSize(width: width, height: height)
                let sizes: [CGFloat] = [23, 31].map { ($0 * factor * 4).rounded() * 0.25 }
                var reference: NSAttributedString.Metrics?
                try withOwner(text(sizes, offset: offset), configure: { $0.lineLimit = limit }) {
                    reference = $0.metrics(in: request, layoutMargins: nil)
                }
                try withOwner(text([23, 31], offset: offset), configure: {
                    $0.lineLimit = limit; $0.minimumScaleFactor = minimum
                }) { owner in
                    let original = try XCTUnwrap(owner.resolvedText)
                    let metrics = owner.metrics(in: request, layoutMargins: nil)
                    XCTAssertEqual(metrics.scale, factor)
                    XCTAssertEqual(metrics.size.height, expectedHeight)
                    XCTAssertEqual(metrics.size, reference?.size)
                    XCTAssertEqual(metrics.firstBaseline, reference?.firstBaseline)
                    XCTAssertEqual(metrics.lastBaseline, reference?.lastBaseline)
                    XCTAssertEqual(metrics.numberOfLines, UInt(limit))
                    XCTAssertEqual(metrics.hasTruncatedRanges, minimum == 0.5)
                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics)
                    XCTAssertEqual(owner.metricsCacheEntryCount, 1)
                    XCTAssertNil(owner.preparedLayout)
                    let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: request,
                        applyingMarginOffsets: true))
                    let drawn = attributes(prepared.source)
                    XCTAssertEqual(drawn.compactMap { $0.fontResource?.pointSize }, sizes)
                    XCTAssertEqual(drawn[1].baselineOffset, offset ? 3 : nil)
                    XCTAssertEqual(drawn[1].kern, offset ? 1.5 : nil)
                    XCTAssertEqual(drawn[1].foregroundColor, attributes(original)[1].foregroundColor)
                    XCTAssertEqual(attributes(original).compactMap { $0.fontResource?.pointSize }, [23, 31])

                    owner.scaleFactorOverride = 0.63
                    let explicit = owner.metrics(in: request, layoutMargins: nil)
                    XCTAssertEqual(explicit.scale, 1)
                    XCTAssertEqual(attributes(try XCTUnwrap(owner.drawingSource(in: request)))
                        .compactMap { $0.fontResource?.pointSize }, [14.5, 19.5])
                    owner.scaleFactorOverride = nil
                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics)
                    XCTAssertEqual(owner.metricsCacheEntryCount, 1)
                }
            }
        }
    }

    // ASSERTIONS textManagerMixedFitting27Observed textManagerMixedScaledStorage27Observed
    func testMixedFittingPreservesRunAttributesAndReusesOriginalFontRequests() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let text = Text(verbatim: "AAA AAA ")
            + Text(verbatim: "BBB BBB").font(.file(file, size: 31)).baselineOffset(3).kerning(1.5)
        func attributes(_ source: ResolvedTextSource) -> [_ResolvedTextRunAttributes] {
            source.runs.compactMap {
                guard case let .styledText(_, _, _, attributes) = $0 else { return nil }
                return attributes
            }
        }
        try withManager(text, configure: { $0.lineLimit = 1; $0.minimumScaleFactor = 0.25 }) { manager in
            let original = try XCTUnwrap(manager.resolvedText)
            let metrics = manager.metrics(in: CGSize(width: 80, height: 60), layoutMargins: nil)
            XCTAssertEqual(metrics.scale, 0.30859375)
            XCTAssertEqual(metrics.size, CGSize(width: 80, height: 14))
            let prepared = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: metrics.size,
                applyingMarginOffsets: true))
            XCTAssertEqual(attributes(prepared.source).compactMap { $0.fontResource?.pointSize },
                           [23 * metrics.scale, 31 * metrics.scale])
            let cache = manager.glyphLayoutCache
            let first = attributes(cache.source(at: 0.63, original: original))
            XCTAssertEqual(first.compactMap { $0.fontResource?.pointSize }, [14.49, 19.53])
            for scale: CGFloat in [0.63, 1, 0.63] {
                let current = attributes(cache.source(at: scale, original: original))
                XCTAssertEqual(current[1].baselineOffset, 3)
                XCTAssertEqual(current[1].kern, 1.5)
                let reference = scale == 1 ? attributes(original) : first
                for (value, reference) in zip(current, reference) {
                    XCTAssertTrue(value.fontResource === reference.fontResource)
                }
            }
            XCTAssertEqual(attributes(original).compactMap { $0.fontResource?.pointSize }, [23, 31])
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertEqual(manager.cache.entries[0].metrics.scale, metrics.scale)
        }
    }

    // ASSERTIONS textManagerFittingCandidateSelectionObserved
    // ASSERTIONS textManagerFittingPreparedDrawingObserved
    func testManagerFitsUniformTextAndDrawsTheSelectedUnroundedFontSize() throws {
        try withManager(Text(verbatim: "A A A A A A A A"), configure: {
            $0.lineLimit = 1
            $0.minimumScaleFactor = 0.25
        }) { manager in
            let request = CGSize(width: 80, height: 54)
            let metrics = manager.metrics(in: request, layoutMargins: nil)
            XCTAssertGreaterThan(metrics.scale, 0.25)
            XCTAssertLessThan(metrics.scale, 1)
            XCTAssertFalse(metrics.hasTruncatedRanges)
            XCTAssertLessThanOrEqual(metrics.size.width, request.width)
            XCTAssertEqual(metrics.numberOfLines, 1)
            let repeated = manager.metrics(in: request, layoutMargins: nil)
            XCTAssertEqual(repeated.scale, metrics.scale)
            XCTAssertEqual(manager.cache.entries.count, 1)

            let prepared = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: metrics.size,
                applyingMarginOffsets: true))
            let font = try XCTUnwrap(prepared.source.uniformFont)
            XCTAssertEqual(font.pointSize, 23 * metrics.scale, accuracy: 0.000001)
            XCTAssertNotEqual(font.pointSize, (font.pointSize * 4).rounded() * 0.25)
            XCTAssertEqual(manager.resolvedText?.uniformFont?.pointSize, 23)
            XCTAssertEqual(manager.cache.entries.count, 1)
            let layout = try XCTUnwrap(manager.makeLayout(in: .zero, with: metrics.size,
                shading: .color(.black), layoutDirection: .leftToRight))
            XCTAssertFalse(layout.isTruncated)
            XCTAssertEqual(layout.count, 1)
            manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
            let rebuilt = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: metrics.size,
                applyingMarginOffsets: true))
            XCTAssertEqual(rebuilt.source.uniformFont?.pointSize, font.pointSize)
            XCTAssertEqual(rebuilt.lines.map(\.width), prepared.lines.map(\.width))
            XCTAssertEqual(manager.cache.entries.count, 1)
        }
    }

    // ASSERTIONS textManagerFittingCandidateSelectionObserved
    func testManagerMinimumScaleFallbackAndExplicitLineHeightFitting() throws {
        try withManager(Text(verbatim: "A A A A A A A A"), configure: {
            $0.lineLimit = 1
            $0.minimumScaleFactor = 0.75
        }) { manager in
            for height: CGFloat in [14, 54] {
                let metrics = manager.metrics(in: CGSize(width: 20, height: height), layoutMargins: nil)
                XCTAssertEqual(metrics.scale, 0.75)
                XCTAssertTrue(metrics.hasTruncatedRanges)
            }
            // Clipping that cannot fit a truncation token does not publish a truncated range.
            let clipped = manager.metrics(in: CGSize(width: 8, height: 14), layoutMargins: nil)
            XCTAssertEqual(clipped.scale, 0.75)
            XCTAssertFalse(clipped.hasTruncatedRanges)
            let tall = manager.metrics(in: CGSize(width: 8, height: 54), layoutMargins: nil)
            XCTAssertEqual(tall.scale, 1)
            XCTAssertFalse(tall.hasTruncatedRanges)
        }
        try withManager(Text(verbatim: "A\nB"), configure: { $0.minimumScaleFactor = 0.25 }) { manager in
            let metrics = manager.metrics(in: CGSize(width: 80, height: 24), layoutMargins: nil)
            XCTAssertGreaterThan(metrics.scale, 0.25)
            XCTAssertLessThan(metrics.scale, 1)
            XCTAssertEqual(metrics.numberOfLines, 2)
            XCTAssertFalse(metrics.hasTruncatedRanges)
            XCTAssertLessThanOrEqual(metrics.size.height, 24)
        }
        try withManager(Text(verbatim: "A"), configure: { $0.minimumScaleFactor = 0.25 }) { manager in
            let metrics = manager.metrics(in: CGSize(width: 80, height: 54), layoutMargins: nil)
            XCTAssertEqual(metrics.scale, 1)
            XCTAssertFalse(metrics.hasTruncatedRanges)
        }
        for minimum: CGFloat in [1, 0.25] {
            for height: CGFloat in [-1, 0, 0.01, 8, 13.75, 14] {
                try withManager(Text(verbatim: ""), configure: { $0.minimumScaleFactor = minimum }) { manager in
                    let metrics = manager.metrics(in: CGSize(width: 80, height: height), layoutMargins: nil)
                    XCTAssertEqual(metrics.scale, height < 14 ? minimum : 1)
                    let expectedHeight = height > 0 ? ceil(min(height, 14) * 2) / 2 : 14
                    XCTAssertEqual(metrics.size, CGSize(width: 0, height: expectedHeight))
                    XCTAssertEqual(metrics.numberOfLines, 0)
                    XCTAssertEqual(metrics.firstBaseline, 0)
                    XCTAssertFalse(metrics.hasTruncatedRanges)
                }
            }
        }
    }

    // ASSERTIONS textManagerFittingPreparedDrawingObserved
    // ASSERTIONS textManagerSpacingUnitScaleObserved
    func testManagerFittingPreservesItsIndependentUnitScaleIdealAndNoOpReset() throws {
        try withManager(Text(verbatim: "A A A A A A A A"), configure: {
            $0.lineLimit = 1
            $0.minimumScaleFactor = 0.25
        }) { manager in
            _ = manager.spacing()
            let ideal = try XCTUnwrap(manager.cache.ideal)
            let metrics = manager.metrics(in: CGSize(width: 80, height: 54), layoutMargins: nil)
            XCTAssertLessThan(metrics.scale, 1)
            _ = manager.prepareDrawing(in: .zero, with: metrics.size, applyingMarginOffsets: true)
            manager.resetCache()
            _ = manager.spacing()
            XCTAssertEqual(manager.cache.ideal?.scale, 1)
            XCTAssertEqual(manager.cache.ideal?.size, ideal.size)
            XCTAssertEqual(manager.cache.ideal?.firstBaseline, ideal.firstBaseline)
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertEqual(manager.cache.entries[0].metrics.scale, metrics.scale)
        }
    }

    // ASSERTIONS textManagerScaledStorageLifecycleObserved
    func testManagerRetainsTheLastScaledSourceAcrossUnitScaleRestoration() throws {
        try withManager(Text(verbatim: "A")) { manager in
            let source = try XCTUnwrap(manager.resolvedText)
            let cache = manager.glyphLayoutCache
            let half = try XCTUnwrap(cache.source(at: 0.5, original: source).uniformFont)
            XCTAssertEqual(half.pointSize, 11.5)
            XCTAssertTrue(cache.source(at: 0.5, original: source).uniformFont === half)
            let fractional = try XCTUnwrap(cache.source(at: 0.63, original: source).uniformFont)
            XCTAssertEqual(fractional.pointSize, 14.49, accuracy: 0.000001)
            XCTAssertTrue(cache.source(at: 1, original: source).uniformFont === source.uniformFont)
            XCTAssertTrue(cache.source(at: 0.63, original: source).uniformFont === fractional)
            let halfAgain = try XCTUnwrap(cache.source(at: 0.5, original: source).uniformFont)
            XCTAssertEqual(halfAgain.pointSize, 11.5)
            XCTAssertFalse(halfAgain === half)
            cache.purgeResources(reason: .lowMemory)
            XCTAssertFalse(cache.source(at: 0.5, original: source).uniformFont === halfAgain)
            cache.purgeResources(reason: .appTermination)
            XCTAssertTrue(cache.source(at: 0.5, original: source).uniformFont === source.uniformFont)
        }
    }

    // ASSERTIONS textManagerSizeProposalFlagsObserved
    func testManagerSizePreservesUnspecifiedMinorAxisAndPhysicalDimensions() throws {
        typealias Size = ResolvedStyledText.TextLayoutManager.Size
        try withManager(Text(verbatim: "A")) { manager in
            for vertical in [false, true] {
                manager.layoutProperties.writingMode = vertical ? .verticalRightToLeft : .horizontalTopToBottom
                XCTAssertEqual(manager.majorAxis, vertical ? .horizontal : .vertical)
                for width: CGFloat? in [nil, .infinity, 80] {
                    for height: CGFloat? in [nil, .infinity, 14] {
                        let size = Size(_ProposedSize(width: width, height: height), majorAxis: manager.majorAxis)
                        XCTAssertEqual(size.physicalSize, CGSize(width: width ?? .infinity, height: height ?? .infinity))
                        XCTAssertEqual(size.layoutWidth, (vertical ? height : width) ?? .infinity)
                        XCTAssertEqual(size.layoutHeight, (vertical ? width : height) ?? .infinity)
                        XCTAssertEqual(size.flags.contains(.minorAxisIsUnspecified), (vertical ? height : width) == nil)
                        let explicit = Size(size.physicalSize, majorAxis: manager.majorAxis)
                        XCTAssertTrue(explicit.flags.isEmpty)
                        XCTAssertEqual(explicit.physicalSize, size.physicalSize)
                    }
                }
            }
        }
    }

    // ASSERTIONS textManagerMetricsSizeStructureObserved
    // ASSERTIONS textManagerComputeMetricsStructureObserved
    // ASSERTIONS textManagerFlexibleMinorAxisObserved
    func testManagerComputeMetricsKeepsAvailableRequestAndFlexibleExtentSeparateFromCaches() throws {
        typealias Size = ResolvedStyledText.TextLayoutManager.Size
        try withManager(Text(verbatim: "A A A A A A A A"), configure: { $0.lineLimit = 1 }) { manager in
            manager.layoutMargins = EdgeInsets(top: 0.2, leading: 1.1, bottom: 0.3, trailing: 2.2)
            let request = Size(CGSize(width: 200, height: 54), majorAxis: manager.majorAxis,
                flags: .minorAxisIsUnspecified)
            let fixed = manager.computeMetrics(scale: 1, requestedSize: request, minorAxisIsFlexible: false)
            let flexible = manager.computeMetrics(scale: 1, requestedSize: request, minorAxisIsFlexible: true)
            for value in [fixed, flexible] {
                XCTAssertEqual(value.requestedSize.layoutWidth, 196.7, accuracy: 0.000001)
                XCTAssertEqual(value.requestedSize.layoutHeight, 53.5, accuracy: 0.000001)
                XCTAssertEqual(value.requestedSize.majorAxis, .vertical)
                XCTAssertEqual(value.requestedSize.flags, .minorAxisIsUnspecified)
                XCTAssertEqual(value.base.requestedWidth, value.requestedSize.layoutWidth)
                XCTAssertEqual(value.base.scale, 1)
                XCTAssertEqual(value.base.numberOfLines, 1)
                XCTAssertTrue(value.flags.isEmpty)
                XCTAssertFalse(value.base.hasTruncatedRanges)
                XCTAssertNil(value.layout)
            }
            // Extent is rounded before margins are restored; it can exceed the original request.
            XCTAssertEqual(flexible.base.size.width, 200.3, accuracy: 0.000001)
            XCTAssertGreaterThan(flexible.base.size.width, fixed.base.size.width)
            XCTAssertEqual(flexible.base.size.height, fixed.base.size.height)
            XCTAssertEqual(flexible.base.firstBaseline, fixed.base.firstBaseline)
            XCTAssertEqual(flexible.base.lastBaseline, fixed.base.lastBaseline)
            XCTAssertEqual(flexible.base.baselineAdjustment, fixed.base.baselineAdjustment)
            XCTAssertTrue(manager.cache.entries.isEmpty)
            XCTAssertNil(manager.cache.ideal)

            let scalar = manager.metrics(in: request, layoutMargins: nil)
            XCTAssertEqual(scalar.size, fixed.base.size)
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertEqual(manager.cache.entries[0].request, CGSize(width: 200, height: 54))
            _ = manager.spacing()
            let ideal = try XCTUnwrap(manager.cache.ideal)
            _ = manager.computeMetrics(scale: 0.63, requestedSize: request, minorAxisIsFlexible: true)
            XCTAssertEqual(manager.cache.entries.count, 1)
            XCTAssertEqual(manager.cache.entries[0].metrics.size, scalar.size)
            XCTAssertEqual(manager.cache.ideal?.size, ideal.size)
            XCTAssertEqual(manager.cache.ideal?.scale, 1)
        }
    }

    // ASSERTIONS textManagerComputeMetricsStructureObserved
    func testManagerComputedTruncationFlagsReachTheLayoutAndSurviveBackendPurge() throws {
        typealias Size = ResolvedStyledText.TextLayoutManager.Size
        try withManager(Text(verbatim: "A A A A A A A A"), configure: { $0.lineLimit = 1 }) { manager in
            let size = CGSize(width: 80, height: 54)
            let request = Size(size, majorAxis: manager.majorAxis)
            let metrics = manager.computeMetrics(scale: 1, requestedSize: request, minorAxisIsFlexible: false)
            XCTAssertTrue(metrics.base.hasTruncatedRanges)
            XCTAssertEqual(metrics.flags, .isTruncated)
            XCTAssertNil(metrics.layout)
            let layout = try XCTUnwrap(manager.makeLayout(in: .zero, with: size,
                shading: .color(.black), layoutDirection: .leftToRight))
            XCTAssertEqual(layout.isTruncated, metrics.flags.contains(.isTruncated))
            XCTAssertTrue(manager.cache.entries.isEmpty)
            manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
            let rebuilt = manager.computeMetrics(scale: 1, requestedSize: request, minorAxisIsFlexible: false)
            XCTAssertEqual(rebuilt.flags, metrics.flags)
            XCTAssertEqual(rebuilt.base.size, metrics.base.size)
            XCTAssertEqual(rebuilt.base.numberOfLines, metrics.base.numberOfLines)
            XCTAssertTrue(manager.cache.entries.isEmpty)
        }
    }

    // ASSERTIONS textLayoutLineArrayValueSemanticsObserved
    // ASSERTIONS textLayoutLogicalLineCountObserved
    func testLayoutPreservesLineValuesSeparatelyFromItsLogicalLineCount() throws {
        try withManager(Text(verbatim: "AB")) { manager in
            let original = try XCTUnwrap(manager.makeLayout(in: .zero,
                with: CGSize(width: 100, height: 54), shading: .color(.black), layoutDirection: .leftToRight))
            let first = try XCTUnwrap(original.first)
            var second = first
            second.origin.x += first.typographicBounds.width
            second.drawingOptions = .disablesSubpixelQuantization
            let layout = Text.Layout(lines: [first, second], isTruncated: true, numberOfLines: 1)
            XCTAssertEqual(layout.count, 2)
            XCTAssertEqual(layout.endIndex, 2)
            XCTAssertEqual(layout[0], first)
            XCTAssertEqual(layout[1], second)
            XCTAssertEqual(layout[1].drawingOptions, .disablesSubpixelQuantization)
            XCTAssertEqual(layout[1][0].typographicBounds.origin.x,
                first[0].typographicBounds.origin.x + first.typographicBounds.width)
            XCTAssertEqual(layout[1][0].characterIndices, first[0].characterIndices)
            let logicalCount = Mirror(reflecting: layout).children.first { $0.label == "numberOfLines" }?.value
            XCTAssertEqual(logicalCount as? Int, 1)

            var independent: [Text.Layout.Line] = []
            independent.reserveCapacity(8)
            independent.append(contentsOf: layout)
            XCTAssertEqual(layout, Text.Layout(lines: independent, isTruncated: true, numberOfLines: 1))
            XCTAssertNotEqual(layout, Text.Layout(lines: independent, isTruncated: true, numberOfLines: 2))
            XCTAssertNotEqual(layout, Text.Layout(lines: independent, isTruncated: false, numberOfLines: 1))
            independent[0].origin.y += 3.25
            XCTAssertNotEqual(layout, Text.Layout(lines: independent, isTruncated: true, numberOfLines: 1))
            XCTAssertEqual(layout[0], first)
            XCTAssertEqual(original[0], first)
        }
    }

    // ASSERTIONS textSeparatorParagraphOwners27Observed textStringSeparatorFitting27Observed textManagerSeparatorFitting27Observed
    func testMultilineSeparatorFittingPreservesEachOwnersFontCopies() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        func fontSizes(_ source: ResolvedTextSource) -> [CGFloat] {
            source.runs.compactMap {
                guard case let .styledText(_, _, _, attributes) = $0 else { return nil }
                return attributes.fontResource?.pointSize
            }
        }
        for separator in ["\n", "\u{2028}"] {
            for mixed in [false, true] {
                let originalSizes: [CGFloat] = [23, mixed ? 31 : 23]
                let text = Text(verbatim: "AAA AAA" + separator)
                    + Text(verbatim: "BBB BBB").font(.file(file, size: originalSizes[1]))
                for minimum: CGFloat in [0.5, 0.25] {
                    try withOwner(text, configure: { $0.lineLimit = 2; $0.minimumScaleFactor = minimum }) { source in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: source.layoutProperties,
                            layoutMargins: source.layoutMargins, resolvedText: source.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, source), (true, manager)] {
                            let label = "separator=\(separator.debugDescription) mixed=\(mixed) custom=\(custom) minimum=\(minimum)"
                            let request = CGSize(width: 120, height: 60)
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            let expectedScale: CGFloat = !mixed ? 1 : minimum == 0.25
                                ? 0.958984375 : custom ? 0.953125 : 0.9609375
                            XCTAssertEqual(metrics.scale, expectedScale, label)
                            let expectedSize = !mixed ? CGSize(width: 96, height: 54)
                                : custom && minimum == 0.5 ? CGSize(width: 118, height: 59)
                                : CGSize(width: 119, height: 60)
                            XCTAssertEqual(metrics.size, expectedSize, label)
                            XCTAssertEqual(metrics.firstBaseline, mixed ? 20 : 21, label)
                            XCTAssertEqual(metrics.lastBaseline, !mixed ? 48 : custom && minimum == 0.5 ? 52 : 53, label)
                            XCTAssertEqual(metrics.numberOfLines, 2, label)
                            XCTAssertFalse(metrics.hasTruncatedRanges, label)
                            let original = try XCTUnwrap(owner.resolvedText)
                            let storage = owner.storage
                            let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            XCTAssertEqual(fontSizes(prepared.source), originalSizes.map {
                                let size = $0 * expectedScale
                                return custom ? size : (size * 4).rounded() * 0.25
                            }, label)
                            XCTAssertEqual(fontSizes(original), originalSizes, label)
                            XCTAssertTrue(owner.storage === storage, label)
                            XCTAssertEqual(prepared.lines.count, 2, label)
                            XCTAssertEqual(prepared.lines.map { $0.paragraphIndex }, separator == "\n" ? [0, 1] : [0, 0], label)
                            XCTAssertTrue(prepared.lines.allSatisfy { !$0.glyphs.contains(where: \.isTruncationToken) }, label)
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            if custom {
                                XCTAssertEqual(manager.cache.entries.count, 1, label)
                                manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
                            } else {
                                XCTAssertEqual(source.metricsCacheEntryCount, 1, label)
                                source.resetCache()
                            }
                            let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: request,
                                applyingMarginOffsets: true))
                            XCTAssertEqual(fontSizes(rebuilt.source), fontSizes(prepared.source), label)
                            XCTAssertEqual(rebuilt.lines.map(\.width), prepared.lines.map(\.width), label)
                        }
                    }
                }
            }
        }
    }

    func testMultilineParagraphMeasurementRetainsItsDrawingProposal() throws {
        // ASSERTIONS textParagraphPublication27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for separator in ["\n", "\u{2028}"] {
            for mixed in [false, true] {
                let text = Text(verbatim: "AAA AAA" + separator)
                    + Text(verbatim: "BBB BBB").font(.file(file, size: mixed ? 31 : 23))
                var cases: [(width: CGFloat, height: CGFloat, limit: Int)] =
                    [27, 53, 54, 60, 62, 63, 64, 81].map { (120, $0, 2) }
                if mixed { cases += [(124, 60, 2), (124, 64, 2), (120, 60, 1), (120, 60, 3)] }
                for input in cases {
                    try withOwner(text, configure: { $0.lineLimit = input.limit; $0.minimumScaleFactor = 1 }) { source in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: source.layoutProperties,
                            layoutMargins: source.layoutMargins, resolvedText: source.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, source), (true, manager)] {
                            let label = "separator=\(separator.debugDescription) mixed=\(mixed) custom=\(custom) input=\(input)"
                            let twoLines = input.limit != 1 && (!mixed ? input.height >= 54
                                : input.height >= 64 || (custom && separator == "\n" && input.width == 124))
                            let removed = twoLines && mixed && input.width == 120
                            let width: CGFloat = twoLines ? (mixed ? (removed ? 106 : 124) : 96)
                                : custom && mixed && separator == "\n" && input.height >= 54 && input.limit > 1 ? 96 : 111.5
                            let expectedSize = CGSize(width: width, height: twoLines ? (mixed ? 64 : 54) : 27)
                            let request = CGSize(width: input.width, height: input.height)
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(metrics.size, expectedSize, label)
                            XCTAssertEqual(metrics.scale, 1, label)
                            XCTAssertEqual(metrics.firstBaseline, 21, label)
                            XCTAssertEqual(metrics.lastBaseline, twoLines ? (mixed ? 56 : 48) : 21, label)
                            XCTAssertEqual(metrics.numberOfLines, twoLines ? 2 : 1, label)
                            XCTAssertEqual(metrics.hasTruncatedRanges, removed || (custom && separator == "\n" && !twoLines), label)
                            let storage = owner.storage
                            let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            let widths: [CGFloat] = twoLines
                                ? [95.728515625, mixed ? (removed ? 105.6845703125 : 123.576171875) : 91.685546875]
                                : [111.1142578125]
                            XCTAssertEqual(prepared.lines.map { $0.width / prepared.source.scaleFactor }, widths, label)
                            XCTAssertEqual(prepared.lines.last?.glyphs.contains(where: \.isTruncationToken), removed || !twoLines, label)
                            XCTAssertTrue(owner.storage === storage, label)
                            XCTAssertEqual(prepared.source.runs.compactMap { run -> CGFloat? in
                                guard case let .styledText(_, _, _, attributes) = run else { return nil }
                                return attributes.fontResource?.pointSize
                            }, [23, mixed ? 31 : 23], label)
                            let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                shading: .color(.black), layoutDirection: .leftToRight))
                            if custom { XCTAssertEqual(layout.isTruncated, removed, label) }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            if custom {
                                XCTAssertEqual(manager.cache.entries.count, 1, label)
                                manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
                            } else {
                                XCTAssertEqual(source.metricsCacheEntryCount, 1, label)
                                source.resetCache()
                            }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            XCTAssertEqual(rebuilt.lines.map(\.width), prepared.lines.map(\.width), label)
                        }
                    }
                }
            }
        }
    }

    func testSingleLineSeparatorFittingSeparatesUnlaidTextFromPublicTruncation() throws {
        // ASSERTIONS textSingleLineSeparatorFitting27Observed
        // ASSERTIONS textManagerSeparatorRangeConsumers27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for separator in ["\n", "\u{2028}"] {
            for mixed in [false, true] {
                let originalSizes: [CGFloat] = [23, mixed ? 31 : 23]
                let text = Text(verbatim: "AAA AAA" + separator)
                    + Text(verbatim: "BBB BBB").font(.file(file, size: originalSizes[1]))
                for minimum: CGFloat in [0.5, 0.25] {
                    try withOwner(text, configure: { $0.lineLimit = 1; $0.minimumScaleFactor = minimum }) { source in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: source.layoutProperties,
                            layoutMargins: source.layoutMargins, resolvedText: source.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, source), (true, manager)] {
                            let label = "separator=\(separator.debugDescription) mixed=\(mixed) custom=\(custom) minimum=\(minimum)"
                            let request = CGSize(width: 80, height: 60)
                            let unlaid = custom && separator == "\n"
                            let expectedScale: CGFloat = unlaid ? minimum : 0.71875
                            let expectedSize = !unlaid ? CGSize(width: 80, height: 19)
                                : minimum == 0.5 ? CGSize(width: 56, height: 14) : CGSize(width: 28, height: 6)
                            let baseline: CGFloat = !unlaid ? 15 : minimum == 0.5 ? 11 : 5
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(metrics.scale, expectedScale, label)
                            XCTAssertEqual(metrics.size, expectedSize, label)
                            XCTAssertEqual(metrics.firstBaseline, baseline, label)
                            XCTAssertEqual(metrics.lastBaseline, baseline, label)
                            XCTAssertEqual(metrics.numberOfLines, 1, label)
                            XCTAssertEqual(metrics.hasTruncatedRanges, unlaid, label)
                            let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            let sizes = prepared.source.runs.compactMap { run -> CGFloat? in
                                guard case let .styledText(_, _, _, attributes) = run else { return nil }
                                return attributes.fontResource?.pointSize
                            }
                            XCTAssertEqual(sizes, originalSizes.map {
                                let size = $0 * expectedScale
                                return custom ? size : (size * 4).rounded() * 0.25
                            }, label)
                            XCTAssertEqual(prepared.lines.count, 1, label)
                            XCTAssertTrue(prepared.lines[0].glyphs.contains(where: \.isTruncationToken), label)
                            let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                shading: .color(.black), layoutDirection: .leftToRight))
                            XCTAssertFalse(layout.isTruncated, label)
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            if custom {
                                XCTAssertEqual(manager.cache.entries.count, 1, label)
                                manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
                            } else {
                                XCTAssertEqual(source.metricsCacheEntryCount, 1, label)
                                source.resetCache()
                            }
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                            let rebuilt = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                shading: .color(.black), layoutDirection: .leftToRight))
                            XCTAssertEqual(rebuilt.isTruncated, layout.isTruncated, label)
                            XCTAssertEqual(rebuilt.map(\.typographicBounds.rect), layout.map(\.typographicBounds.rect), label)
                        }
                    }
                }
            }
        }
    }

    func testTerminalWhitespaceKeepsFragmentExtentSeparateFromGlyphWidth() throws {
        // ASSERTIONS textTerminalSpacePublication27Observed
        // ASSERTIONS textFractionalTokenAdmission27Observed
        // ASSERTIONS textTailTokenEpsilon27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for scale: CGFloat in [1, 2] {
            for separator in ["\n", "\u{2028}"] {
                for mixed in [false, true] {
                    for spaces in 0...2 {
                        let body = "AAA AAA" + String(repeating: " ", count: spaces)
                        let text = Text(verbatim: body + separator)
                            + Text(verbatim: "BBB BBB").font(.file(file, size: mixed ? 31 : 23))
                        var widths: [CGFloat] = mixed && separator == "\u{2028}"
                            ? [112, 116, 117, 120, 122.5, 123, 124, 134] : [120, 124, 134]
                        let fractionalWidths: [[CGFloat]] = [
                            [116.5, 122.5],
                            [116.5, 116.818359375, 116.8193359375, 116.8203125, 117],
                            [122.5, 122.5234375, 122.5244140625, 122.525390625, 123]
                        ]
                        widths = Array(Set(widths + fractionalWidths[spaces])).sorted()
                        if spaces > 0 {
                            let tokenWidth: CGFloat = spaces == 1 ? 116.8193359375 : 122.5244140625
                            widths += [0.0011, 0.001, 0.0002, 0.0001].map { tokenWidth - $0 }
                        }
                        for width in widths {
                            try withOwner(text, configure: {
                                $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                            }) { ordinary in
                                let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                    layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                                for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                    let label = "scale=\(scale) separator=\(separator.debugDescription) mixed=\(mixed) spaces=\(spaces) width=\(width) custom=\(custom)"
                                    let insertedWidth: CGFloat = [111.1142578125, 116.8193359375, 122.5244140625][spaces]
                                    let removed = insertedWidth > width + (custom ? 0.001 : 0.0002)
                                    let glyphWidth: CGFloat = removed ? 111.1142578125 : insertedWidth
                                    let retainedExtent: CGFloat = insertedWidth > width ? glyphWidth
                                        : [111.1142578125, 122.5244140625, 133.9345703125][spaces]
                                    let fragmentWidth = min(width, retainedExtent)
                                    let published = ceil((custom ? fragmentWidth : glyphWidth) * scale) / scale
                                    let request = CGSize(width: width, height: 60)
                                    let metrics = owner.metrics(in: request, layoutMargins: nil)
                                    XCTAssertEqual(metrics.size, CGSize(width: published, height: 27), label)
                                    XCTAssertEqual(metrics.scale, 1, label)
                                    XCTAssertEqual(metrics.firstBaseline, 21, label)
                                    XCTAssertEqual(metrics.lastBaseline, 21, label)
                                    XCTAssertEqual(metrics.numberOfLines, 1, label)
                                    XCTAssertEqual(metrics.hasTruncatedRanges, removed || (custom && separator == "\n"), label)
                                    let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                        applyingMarginOffsets: true))
                                    XCTAssertEqual(prepared.lines.map { $0.width / prepared.source.scaleFactor }, [glyphWidth], label)
                                    let visible = (removed ? "AAA AAA" : body) + "…"
                                    XCTAssertEqual(prepared.lines.first?.glyphs.map(\.scalar), Array(visible.unicodeScalars), label)
                                    let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                        shading: .color(.black), layoutDirection: .leftToRight))
                                    if custom {
                                        XCTAssertEqual(layout.first?.typographicBounds.width, fragmentWidth, label)
                                        XCTAssertEqual(layout.isTruncated, removed, label)
                                    }
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    XCTAssertEqual(owner.metricsCacheEntryCount, 1, label)
                                    if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                    else { ordinary.resetCache() }
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    let rebuilt = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                        shading: .color(.black), layoutDirection: .leftToRight))
                                    XCTAssertEqual(rebuilt.map(\.typographicBounds.rect), layout.map(\.typographicBounds.rect), label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTruncationRetainsTheOriginalLineMetrics() throws {
        // ASSERTIONS textTailLineMetricRetention27Observed
        // ASSERTIONS textTailTokenOriginalLineMetrics27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        // Single-line requests and height-limited wrapping have distinct metric inputs.
        let cases: [(String, CGFloat, CGFloat, Int, CGFloat, CGFloat, CGFloat)] = [
            ("mixed", 66, 60, 1, 37, 29, 29),
            ("mixed", 80, 60, 1, 37, 29, 29),
            ("mixed", 80, 40, 2, 27, 21, 21),
            ("mixed", 66, 100, 2, 64, 21, 56),
            ("uniform", 66, 60, 1, 27, 21, 21),
            ("mixed-lf", 66, 60, 1, 27, 21, 21),
            ("mixed-line", 66, 60, 1, 27, 21, 21),
            ("mixed-lf", 80, 40, 2, 27, 21, 21),
            ("mixed-line", 80, 40, 2, 27, 21, 21),
            ("prefix-lf", 66, 100, 2, 54, 21, 48),
            ("prefix-line", 66, 100, 2, 54, 21, 48),
            ("later-lf", 66, 60, 1, 27, 21, 21),
            ("later-line", 66, 60, 1, 27, 21, 21)
        ]
        for scale: CGFloat in [1, 2] {
            for (sample, width, height, limit, expectedHeight, first, last) in cases {
                let separator = sample.hasSuffix("lf") ? "\n" : "\u{2028}"
                let prefix = sample.hasPrefix("prefix") ? "AAA" + separator + "AAA "
                    : sample.hasPrefix("later") ? "AAA AAA" + separator : "AAA "
                var value = Text(verbatim: prefix).font(.file(file, size: 23))
                    + Text(verbatim: "BBB BBB").font(.file(file, size: sample == "uniform" ? 23 : 31))
                if sample.hasPrefix("mixed-") {
                    value = value + Text(verbatim: separator).font(.file(file, size: 31))
                        + Text(verbatim: "CCC").font(.file(file, size: 17))
                }
                try withOwner(value, configure: {
                    $0.lineLimit = limit; $0.minimumScaleFactor = 1; $0.displayScale = scale
                }) { ordinary in
                    let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                        layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                    for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                        let label = "\(sample) width=\(width) height=\(height) limit=\(limit) custom=\(custom) scale=\(scale)"
                        let fullFragment = custom && limit == 1 && sample.hasPrefix("mixed-")
                        let measuredHeight: CGFloat = fullFragment ? 37 : expectedHeight
                        let firstBaseline: CGFloat = fullFragment ? 29 : first
                        let lastBaseline: CGFloat = fullFragment ? 29 : last
                        let request = CGSize(width: width, height: height)
                        let metrics = owner.metrics(in: request, layoutMargins: nil)
                        XCTAssertEqual(metrics.size.height, measuredHeight, label)
                        XCTAssertEqual(metrics.firstBaseline, firstBaseline, label)
                        XCTAssertEqual(metrics.lastBaseline, lastBaseline, label)
                        XCTAssertEqual(metrics.scale, 1, label)
                        let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                            applyingMarginOffsets: true))
                        XCTAssertEqual(prepared.lines.first!.baseline / prepared.source.scaleFactor, firstBaseline, label)
                        XCTAssertEqual(prepared.lines.last!.baseline / prepared.source.scaleFactor, lastBaseline, label)
                        XCTAssertEqual(prepared.lines.last!.maxY / prepared.source.scaleFactor, measuredHeight, label)
                        if custom {
                            let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                shading: .color(.black), layoutDirection: .leftToRight))
                            XCTAssertEqual(layout.first!.typographicBounds.ascent, firstBaseline, label)
                            XCTAssertEqual(layout.last!.typographicBounds.ascent + layout.last!.typographicBounds.descent,
                                measuredHeight - (prepared.lines.last!.originY / prepared.source.scaleFactor), label)
                        }
                        XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                        if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                        else { ordinary.resetCache() }
                        XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                    }
                }
            }
        }
    }

    func testLineRunAndSliceDecorationGeometry() throws {
        // ASSERTIONS textDecorationGrouping27Observed
        // ASSERTIONS textDecorationMetricQuantization27Observed
        // ASSERTIONS textDecorationSelection27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.geometry)
        XCTAssertEqual(fixtures.count, 88)
        for fixture in fixtures { try checkDecorationGeometry(fixture) }
    }

    func testTailTokenDecorationGeometry() throws {
        // ASSERTIONS textTailDecorationSpans27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.tails)
        XCTAssertEqual(fixtures.count, 63)
        for fixture in fixtures { try checkDecorationGeometry(fixture) }
    }

    func testSignedOffsetDecorationFragmentsAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationBaselineOffset27Observed
        // ASSERTIONS textDecorationBaselineFragments27Observed
        // ASSERTIONS textDecorationOutlineProducer27Observed
        // ASSERTIONS textDecorationGapEmission27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.offsets)
        XCTAssertEqual(fixtures.count, 120)
        for fixture in fixtures { try checkDecorationGeometry(fixture) }
    }

    func testSpacingDecorationFragmentsAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationSpacingProducer27Observed
        // ASSERTIONS textDecorationSpacingSelection27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.spacing)
        XCTAssertEqual(fixtures.count, 332)
        for fixture in fixtures { try checkDecorationGeometry(fixture) }
    }

    func testExplicitDecorationColorsAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationExplicitColor27Observed
        // ASSERTIONS textDecorationColorSelection27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.colors)
        XCTAssertEqual(fixtures.count, 162)
        for fixture in fixtures {
            try checkDecorationGeometry(fixture)
            try checkDecorationGeometry(fixture, attributed: true)
        }
    }

    func testPatternedDecorationsAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationPatternProducer27Observed
        // ASSERTIONS textDecorationPatternSelection27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.patterns)
        XCTAssertEqual(fixtures.count, 248)
        for fixture in fixtures {
            try checkDecorationGeometry(fixture)
            try checkDecorationGeometry(fixture, attributed: true)
        }
    }

    func testMultilineDecorationGeometryAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationMultilineGroups27Observed
        // ASSERTIONS textDecorationMultilineOrder27Observed
        // ASSERTIONS textDecorationMultilineSelection27Observed
        let fixtures = try TextDecorationMultilineFixture.decode()
        XCTAssertEqual(fixtures.count, 32)
        try checkDecorationLines(fixtures)
    }

    func testAlignedMultilineDecorationGeometryAndLineSpacing() throws {
        // ASSERTIONS textDecorationLinePlacement27Observed
        // ASSERTIONS textDecorationLineSpacing27Observed
        // ASSERTIONS textDecorationAlignedPhase27Observed
        let fixtures = try TextDecorationPlacementFixture.decode()
        XCTAssertEqual(fixtures.count, 84)
        for fixture in fixtures {
            let alignment: TextAlignment = switch fixture.alignment {
            case "leading": .leading
            case "center": .center
            case "trailing": .trailing
            default: preconditionFailure("Unknown text alignment")
            }
            try checkDecorationLines([fixture.drawing], alignment: alignment, lineSpacing: fixture.lineSpacing)
        }
    }

    func testReceivingTransformsPreserveDecorationCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationTransformMetrics27Observed
        // ASSERTIONS textDecorationTransformPhase27Observed
        // ASSERTIONS textDecorationTransformDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decode()
        XCTAssertEqual(fixtures.count, 36)
        try checkDecorationTransforms(fixtures)
    }

    func testOrientedTransformsPreserveDecorationCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationOrientedMetrics27Observed
        // ASSERTIONS textDecorationOrientedPhase27Observed
        // ASSERTIONS textDecorationOrientedDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeOriented()
        XCTAssertEqual(fixtures.count, 42)
        try checkDecorationTransforms(fixtures)
    }

    func testTransformedOutlineGapsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationGapTransformGeometry27Observed
        // ASSERTIONS textDecorationGapTransformPhase27Observed
        // ASSERTIONS textDecorationGapTransformDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeGapTransforms()
        XCTAssertEqual(fixtures.count, 32)
        try checkDecorationTransforms(fixtures)
    }

    func testMultilineOutlineGapsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationGapMultilineGeometry27Observed
        // ASSERTIONS textDecorationGapMultilineSelection27Observed
        // ASSERTIONS textDecorationGapMultilineDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeMultilineGaps()
        XCTAssertEqual(fixtures.count, 64)
        try checkDecorationTransforms(fixtures)
    }

    func testSpacedOutlineGapsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationGapSpacingGeometry27Observed
        // ASSERTIONS textDecorationGapSpacingSelection27Observed
        // ASSERTIONS textDecorationGapSpacingDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeSpacedGaps()
        XCTAssertEqual(fixtures.count, 64)
        try checkDecorationTransforms(fixtures)
    }

    func testDescenderGapsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderGeometry27Observed
        // ASSERTIONS textDecorationDescenderSelection27Observed
        // ASSERTIONS textDecorationDescenderDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenders()
        XCTAssertEqual(fixtures.count, 64)
        try checkDecorationTransforms(fixtures)
    }

    func testSignedDescenderOffsetsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderOffsetGeometry27Observed
        // ASSERTIONS textDecorationDescenderOffsetDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenderOffsets()
        XCTAssertEqual(fixtures.count, 8)
        try checkDecorationTransforms(fixtures)
    }

    func testScopedDescenderOffsetsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderScopeGeometry27Observed
        // ASSERTIONS textDecorationDescenderScopeDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenderScopes()
        XCTAssertEqual(fixtures.count, 16)
        try checkDecorationTransforms(fixtures)
    }

    func testScopedDescenderSelectionsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderScopedSelection27Observed
        // ASSERTIONS textDecorationDescenderScopedSelectionDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenderSelections()
        XCTAssertEqual(fixtures.count, 64)
        try checkDecorationTransforms(fixtures)
    }

    func testScopedDescenderOrientationsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderOrientedGeometry27Observed
        // ASSERTIONS textDecorationDescenderOrientedDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenderOrientations()
        XCTAssertEqual(fixtures.count, 64)
        try checkDecorationTransforms(fixtures)
    }

    func testOrientedDescenderSelectionsPreserveCoordinatesAndPhase() throws {
        // ASSERTIONS textDecorationDescenderOrientedSelection27Observed
        // ASSERTIONS textDecorationDescenderOrientedSelectionDrawing27Observed
        let fixtures = try TextDecorationTransformFixture.decodeDescenderOrientedSelections()
        XCTAssertEqual(fixtures.count, 256)
        try checkDecorationTransforms(fixtures)
    }

    private func checkDecorationTransforms(_ fixtures: [TextDecorationTransformFixture]) throws {
        for fixture in fixtures {
            let t = fixture.transform
            try checkDecorationLines([fixture.drawing], alignment: fixture.alignment == "center" ? .center : .leading,
                lineSpacing: fixture.lineSpacing,
                canvasTransform: CGAffineTransform(a: t[0], b: t[1], c: t[2], d: t[3], tx: t[4], ty: t[5]))
        }
    }

    private func checkDecorationLines(_ fixtures: [TextDecorationMultilineFixture],
                                      alignment: TextAlignment = .leading,
                                      lineSpacing: CGFloat = 0,
                                      canvasTransform: CGAffineTransform? = nil) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        func check(_ actual: [CGFloat], _ expected: [CGFloat], _ label: String, accuracy: CGFloat = 1e-9) {
            XCTAssertEqual(actual.count, expected.count, label)
            for (a, b) in zip(actual, expected) { XCTAssertEqual(a, b, accuracy: accuracy, label) }
        }
        func components(_ color: VUI.Color.Resolved) -> [CGFloat] {
            [color.linearRed, color.linearGreen, color.linearBlue, color.opacity].map(CGFloat.init)
        }
        for fixture in fixtures {
            let parts = fixture.sample.split(separator: ":").map(String.init)
            let multiline = parts[11].hasPrefix("two-")
            let separator = parts[11].hasPrefix("two-lf") ? "\n" : "\u{2028}"
            let second = parts[11].hasSuffix("-tail") ? "BBB BBB BBB BBB"
                : parts[11].hasSuffix("-short") ? "BBB" : "BBB BBB"
            func color(_ name: String) -> VUI.Color? {
                switch name {
                case "none": nil
                case "green": .green
                case "blue": .blue
                default: preconditionFailure("Unknown decoration color")
                }
            }
            func pattern(_ name: String) -> Text.LineStyle.Pattern {
                switch name {
                case "solid": .solid
                case "dash": .dash
                case "dashDot": .dashDot
                default: preconditionFailure("Unknown decoration pattern")
                }
            }
            for attributed in [false, true] {
                func run(_ string: String, first: Bool) -> Text {
                    let font = VUI.Font.file(file, size: CGFloat(Double(parts[first ? 3 : 4])!))
                    let foreground: VUI.Color = parts[2] == "split" && !first ? .blue : .red
                    let offset = CGFloat(Double(parts[6])!), spacing = CGFloat(Double(parts[9])!)
                    let hasOffset = parts[7] == "both" || parts[7] == (first ? "first" : "second")
                    let underline = Text.LineStyle(pattern: pattern(parts[14]), color: color(parts[12]))
                    let strike = Text.LineStyle(pattern: pattern(parts[parts[1] == "combined" ? 18 : 14]),
                                                color: color(parts[parts[1] == "combined" ? 16 : 12]))
                    if attributed {
                        var value = AttributedString(string)
                        value.font = font; value.foregroundColor = foreground
                        if hasOffset { value[AttributeScopes.CoreAttributes.BaselineOffsetAttribute.self] = offset }
                        if parts[8] == "kern" {
                            value[AttributeScopes.CoreAttributes.KerningAttribute.self] = spacing
                        } else {
                            value[AttributeScopes.CoreAttributes.TrackingAttribute.self] = spacing
                        }
                        if parts[1] != "strikethrough" { value.underlineStyle = underline }
                        if parts[1] != "underline" { value.strikethroughStyle = strike }
                        return Text(value)
                    }
                    var value = Text(verbatim: string).font(font).foregroundColor(foreground)
                    if hasOffset { value = value.baselineOffset(offset) }
                    value = parts[8] == "kern" ? value.kerning(spacing) : value.tracking(spacing)
                    if parts[1] != "strikethrough" { value = value.underline(pattern: underline.pattern, color: underline.color) }
                    if parts[1] != "underline" { value = value.strikethrough(pattern: strike.pattern, color: strike.color) }
                    return value
                }
                var text = run("AAA ", first: true) + run("BBB BBB", first: false)
                if parts[11] == "descenders" {
                    text = run("gypq ", first: true) + run("gj", first: false)
                } else if multiline {
                    text = run("AAA ", first: true) + run("BBB BBB" + separator, first: false)
                        + run("AAA ", first: true) + run(second, first: false)
                }
                try withOwner(text, configure: {
                    $0.lineLimit = multiline ? 2 : 1; $0.minimumScaleFactor = 1; $0.displayScale = fixture.scale
                    $0.multilineTextAlignment = alignment; $0.lineSpacing = lineSpacing
                }) { ordinary in
                    let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                        layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                    for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                        let expected = custom ? fixture.custom : fixture.ordinary
                        let label = "\(fixture.sample) \(fixture.draw) scale=\(fixture.scale) custom=\(custom) attributed=\(attributed) alignment=\(alignment) lineSpacing=\(lineSpacing) transform=\(String(describing: canvasTransform))"
                        let request = CGSize(width: fixture.width, height: fixture.height)
                        let metrics = owner.metrics(in: request, layoutMargins: nil)
                        check([metrics.size.width, metrics.size.height, metrics.firstBaseline, metrics.lastBaseline], expected.metrics, label)
                        let canvas = !custom && canvasTransform != nil
                        let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero,
                            with: canvas ? request : metrics.size, applyingMarginOffsets: !canvas))
                        XCTAssertEqual(prepared.lines.count, expected.lines.count, label)
                        let firstLine = try XCTUnwrap(prepared.lines.first)
                        for (line, native) in zip(prepared.lines, expected.lines) {
                            check([(line.originX - firstLine.originX) / prepared.source.scaleFactor,
                                   (line.baseline - firstLine.baseline) / prepared.source.scaleFactor],
                                  [native.origin[0] - expected.lines[0].origin[0],
                                   native.origin[1] - expected.lines[0].origin[1]], label)
                            if canvas {
                                check([line.originX / prepared.source.scaleFactor + prepared.bounds.minX,
                                       line.baseline / prepared.source.scaleFactor + prepared.bounds.minY], native.origin, label)
                            }
                            XCTAssertEqual(line.glyphs.count, native.glyphs.count, label)
                            var position = CGPoint.zero
                            for (index, pair) in zip(line.glyphs, native.glyphs).enumerated() {
                                let (glyph, values) = pair
                                if index != 0 { position += glyph.kerning }
                                let unit = 1 / prepared.source.scaleFactor
                                check([CGFloat(try XCTUnwrap(glyph.glyphIndex)), CGFloat(glyph.characterIndex),
                                       (position.x + glyph.positionOffset.x) * unit,
                                       (position.y + glyph.positionOffset.y + glyph.baselineOffset) * unit,
                                       glyph.advance.width * unit],
                                      [values[0], values[1] + CGFloat(native.sourceOffset), values[2], values[3], values[4]], label)
                                position.x += glyph.advance.width
                            }
                        }
                        let viewport = CGRect(x: 0, y: 0, width: 256, height: 160)
                        var context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                            inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                                contentScaleFactor: fixture.scale, resourceCommandQueue: nil))
                        context.transform = canvasTransform ?? .identity
                        var strokes: [TextDecorationMultilineFixture.Stroke] = []
                        if custom {
                            let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                shading: .color(.black), layoutDirection: .leftToRight))
                            XCTAssertEqual(layout.count, expected.lines.count, label)
                            let firstOrigin = try XCTUnwrap(layout.first).origin
                            for (rawLine, native) in zip(layout, expected.lines) {
                                var line = rawLine
                                check([line.origin.x - firstOrigin.x, line.origin.y - firstOrigin.y],
                                      [native.origin[0] - expected.lines[0].origin[0], native.origin[1] - expected.lines[0].origin[1]], label)
                                line.origin = CGPoint(x: native.origin[0], y: native.origin[1])
                                var collections: [Text.Layout.Decorations] = []
                                if fixture.draw == "line" {
                                    collections.append(.init(line: line, scale: context.userToDeviceScale))
                                    context.draw(line)
                                } else {
                                    for run in line {
                                        if fixture.draw == "runs" {
                                            collections.append(.init(run: run, scale: context.userToDeviceScale))
                                            context.draw(run)
                                        } else {
                                            let lower = ["whole", "prefix"].contains(fixture.draw) ? 0 : min(1, run.endIndex)
                                            let upper = fixture.draw == "empty" ? lower : ["prefix", "middle"].contains(fixture.draw)
                                                ? max(lower, run.endIndex - 1) : run.endIndex
                                            let slice = run[lower..<upper]
                                            collections.append(.init(slice: slice, scale: context.userToDeviceScale))
                                            context.draw(slice)
                                        }
                                    }
                                }
                                let expectedCollections = try XCTUnwrap(native.collections)
                                XCTAssertEqual(collections.count, expectedCollections.count, label)
                                for (collection, segments) in zip(collections, expectedCollections) {
                                    XCTAssertEqual(collection.segments.count, segments.count, label)
                                    for (segment, native) in zip(collection.segments, segments) {
                                        XCTAssertEqual(segment.runs, native.runs[0]..<native.runs[1], label)
                                        XCTAssertEqual(segment.thickness, native.width, accuracy: 1e-9, label)
                                        check(segment.dashes, native.dashes, label)
                                        check(components(segment.color), native.color, label, accuracy: 1e-6)
                                        check(segment.fragments.flatMap { [$0.start.x, $0.start.y, $0.end.x, $0.end.y] },
                                              native.fragments.flatMap { $0 }, label)
                                        strokes += native.fragments.map { .init(width: native.width, points: $0,
                                            color: native.color, dashes: native.dashes, phase: $0[0]) }
                                    }
                                }
                            }
                        } else {
                            let drawing = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
                            for (line, native) in zip(prepared.lines, expected.lines) {
                                let scale = prepared.source.scaleFactor
                                strokes += try XCTUnwrap(native.strokes).map { stroke in
                                    var value = stroke
                                    value.points = [stroke.points[0] + line.originX / scale, stroke.points[1] + line.baseline / scale,
                                                    stroke.points[2] + line.originX / scale, stroke.points[3] + line.baseline / scale]
                                    return value
                                }
                            }
                            XCTAssertEqual(drawing.decorations.count, strokes.count, label)
                            if canvas {
                                let resolved = GraphicsContext.ResolvedText(resolved: owner, shared: context.storage.shared)
                                XCTAssertEqual(resolved.measure(in: request), metrics.size, label)
                                context.draw(resolved, in: CGRect(origin: .zero, size: request))
                            } else {
                                context.draw(drawing, in: CGRect(origin: .zero, size: metrics.size), shading: .color(.black), clipBounds: false)
                            }
                        }
                        var order: [String] = []
                        var strokeIndex = 0
                        for item in try XCTUnwrap(context.recording).moveContents().items {
                            XCTAssertEqual(item.state.transform, canvasTransform ?? .identity, label)
                            guard case let .text(drawing, shading) = item.contents else { continue }
                            switch drawing.contents {
                            case .glyphs, .vectorGlyphs:
                                if order.last != "glyphs" { order.append("glyphs") }
                            case let .decoration(decoration):
                                order.append("decoration")
                                guard strokeIndex < strokes.count else { XCTFail(label); continue }
                                let stroke = strokes[strokeIndex]; strokeIndex += 1
                                check([decoration.lineWidth, decoration.start.x, decoration.start.y,
                                       decoration.end.x, decoration.end.y].map { $0 * drawing.scale },
                                      [stroke.width] + stroke.points, label)
                                check(try XCTUnwrap(decoration.dashes).map { $0 * drawing.scale }, stroke.dashes, label)
                                XCTAssertEqual(decoration.dashPhase * drawing.scale, stroke.phase, accuracy: 1e-9, label)
                                XCTAssertEqual(shading.properties.count, 1, label)
                                guard case let .color(color) = try XCTUnwrap(shading.properties.first) else { XCTFail(label); continue }
                                check(components(color.resolve(in: .init())), stroke.color, label, accuracy: 1e-6)
                            default: XCTFail("Unexpected text component: \(label)")
                            }
                        }
                        XCTAssertEqual(strokeIndex, strokes.count, label)
                        XCTAssertEqual(order, expected.order, label)
                    }
                }
            }
        }
    }

    func testMultilineDecorationsFollowEachLinesGlyphs() throws {
        // ASSERTIONS textDecorationMultilineOrder27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for separator in ["\n", "\u{2028}"] {
            func run(_ string: String, size: CGFloat) -> Text {
                Text(verbatim: string).font(.file(file, size: size))
                    .foregroundColor(.red).underline().strikethrough()
            }
            let text = run("AAA ", size: 23) + run("BBB BBB" + separator, size: 31)
                + run("AAA ", size: 23) + run("BBB BBB", size: 31)
            try withOwner(text, configure: {
                $0.displayScale = 2; $0.lineLimit = 2; $0.minimumScaleFactor = 1
            }) { owner in
                let metrics = owner.metrics(in: CGSize(width: 240, height: 120), layoutMargins: nil)
                XCTAssertEqual(metrics.size, CGSize(width: 174.5, height: 74))
                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size, applyingMarginOffsets: true))
                XCTAssertEqual(prepared.lines.count, 2)
                let drawing = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
                let viewport = CGRect(x: 0, y: 0, width: 256, height: 140)
                let context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                    inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                        contentScaleFactor: 2, resourceCommandQueue: nil))
                context.draw(drawing, in: CGRect(origin: .zero, size: metrics.size), shading: .color(.black), clipBounds: false)
                var order: [String] = []
                for item in try XCTUnwrap(context.recording).moveContents().items {
                    guard case let .text(drawing, _) = item.contents else { continue }
                    switch drawing.contents {
                    case .glyphs, .vectorGlyphs:
                        if order.last != "glyphs" { order.append("glyphs") }
                    case .decoration: order.append("decoration")
                    default: XCTFail("Unexpected text component")
                    }
                }
                XCTAssertEqual(order, ["glyphs", "decoration", "decoration", "decoration",
                                       "glyphs", "decoration", "decoration", "decoration"])
            }
        }
    }

    func testCombinedDecorationsAndSelectedSubranges() throws {
        // ASSERTIONS textDecorationCombinedAttributes27Observed
        // ASSERTIONS textDecorationCombinedOrder27Observed
        // ASSERTIONS textRunSliceZeroLengthDrawing27Observed
        let fixtures = try TextDecorationFixture.decode(TextDecorationFixture.combined)
        XCTAssertEqual(fixtures.count, 116)
        for fixture in fixtures {
            try checkDecorationGeometry(fixture)
            try checkDecorationGeometry(fixture, attributed: true)
        }
    }

    func testZeroLengthRunSliceDrawsSuffixGlyphsAndKeepsDecorationBounds() throws {
        // ASSERTIONS textRunSliceZeroLengthDrawing27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let text = Text(verbatim: "AAA").font(.file(file, size: 23)).underline(pattern: .dot)
            + Text(verbatim: "BBB").font(.file(file, size: 31)).strikethrough(pattern: .dash)
        try withOwner(text.baselineOffset(3).tracking(2)) { owner in
            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: owner.layoutProperties,
                layoutMargins: owner.layoutMargins, resolvedText: owner.resolvedText)
            let size = manager.metrics(in: CGSize(width: 240, height: 60), layoutMargins: nil).size
            let layout = try XCTUnwrap(manager.makeLayout(in: .zero, with: size,
                shading: .color(.black), layoutDirection: .leftToRight))
            let line = try XCTUnwrap(layout.first)
            func recordedGlyphs(_ slice: Text.Layout.RunSlice) throws -> [(VUI.Path, GraphicsContext.TextDrawing)] {
                let viewport = CGRect(x: 0, y: 0, width: 256, height: 100)
                let context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                    inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                        contentScaleFactor: 1, resourceCommandQueue: nil))
                context.draw(slice)
                return try XCTUnwrap(context.recording).moveContents().items.compactMap { item in
                    guard case let .text(drawing, _) = item.contents,
                          case let .vectorGlyphs(paths) = drawing.contents else { return nil }
                    var path = VUI.Path()
                    for glyph in paths { path.addPath(glyph) }
                    return (path, drawing)
                }
            }
            for run in line {
                for lower in [run.startIndex, run.startIndex + 1, run.endIndex] {
                    let empty = run[lower..<lower]
                    XCTAssertTrue(empty.isEmpty)
                    XCTAssertEqual(empty.typographicBounds.rect.size, .zero)
                    if lower < run.endIndex {
                        XCTAssertTrue(Text.Layout.Decorations(slice: empty, scale: 1).segments.allSatisfy { $0.fragments.isEmpty })
                    }
                    let actual = try recordedGlyphs(empty)
                    let expected = try recordedGlyphs(run[lower..<run.endIndex])
                    XCTAssertEqual(actual.count, lower == run.endIndex ? 0 : 1)
                    XCTAssertEqual(actual.count, expected.count)
                    for ((path, drawing), (expectedPath, expectedDrawing)) in zip(actual, expected) {
                        XCTAssertEqual(path, expectedPath)
                        XCTAssertEqual(drawing.origin, expectedDrawing.origin)
                        XCTAssertEqual(drawing.frame, expectedDrawing.frame)
                        XCTAssertEqual(drawing.scale, expectedDrawing.scale)
                    }
                }
            }
        }
    }

    private func checkDecorationGeometry(_ fixture: TextDecorationFixture, attributed: Bool = false) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let parts = fixture.sample.split(separator: ":").map(String.init)
        let geometry = parts[0] == "geometry"
        let kind = parts[1], style = parts[2]
        let sizes: [CGFloat] = geometry ? [CGFloat(Double(parts[3])!), CGFloat(Double(parts[4])!)] : [23, 31]
        let plain = geometry && parts.count > 11 && parts[11] == "plain"
        let separator = plain ? "" : geometry || parts[3] == "line" ? "\u{2028}" : parts[3] == "lf" ? "\n" : ""
        func decorationColor(first: Bool, strike: Bool = false) -> VUI.Color? {
            guard parts.count > 13 else { return nil }
            switch parts[(kind == "combined" && strike ? 16 : 12) + (first ? 0 : 1)] {
            case "none": return nil
            case "red": return .red
            case "green": return .green
            case "blue": return .blue
            default: preconditionFailure("Unknown decoration color")
            }
        }
        func decorationPattern(first: Bool, strike: Bool = false) -> Text.LineStyle.Pattern {
            guard parts.count > 15 else { return .solid }
            switch parts[(kind == "combined" && strike ? 18 : 14) + (first ? 0 : 1)] {
            case "solid": return .solid
            case "dot": return .dot
            case "dash": return .dash
            case "dashDot": return .dashDot
            case "dashDotDot": return .dashDotDot
            default: preconditionFailure("Unknown decoration pattern")
            }
        }
        func run(_ string: String, first: Bool) -> Text {
            let size = sizes[style == "reverse" ? (first ? 1 : 0) : (first ? 0 : 1)]
            let color: VUI.Color = (geometry ? style == "split" : true) && !first ? .blue : .red
            if attributed {
                precondition([14, 16, 21].contains(parts.count) && parts[7] == "both" && parts[10] == "both")
                var value = AttributedString(string)
                value.font = VUI.Font.file(file, size: size)
                value.foregroundColor = color
                value[AttributeScopes.CoreAttributes.BaselineOffsetAttribute.self] = CGFloat(Double(parts[6])!)
                value[AttributeScopes.CoreAttributes.TrackingAttribute.self] = CGFloat(Double(parts[9])!)
                let lineStyle = Text.LineStyle(pattern: decorationPattern(first: first), color: decorationColor(first: first))
                if parts[5] == "both" || parts[5] == (first ? "first" : "second") {
                    if kind == "underline" || kind == "combined" { value.underlineStyle = lineStyle }
                    else { value.strikethroughStyle = lineStyle }
                }
                if kind == "combined", parts[20] == "both" || parts[20] == (first ? "first" : "second") {
                    value.strikethroughStyle = .init(pattern: decorationPattern(first: first, strike: true),
                        color: decorationColor(first: first, strike: true))
                }
                return Text(value)
            }
            var value = Text(verbatim: string).font(.file(file, size: size)).foregroundColor(color)
            let decorationScope = geometry && parts.count > 5 ? parts[5] : style == "off" ? "first" : "both"
            if geometry && parts.count > 6 {
                let scope = parts.count > 7 ? parts[7] : decorationScope
                if scope == "both" || scope == (first ? "first" : "second") {
                    value = value.baselineOffset(CGFloat(Double(parts[6])!))
                }
            }
            if geometry && parts.count > 10 && (parts[10] == "both" || parts[10] == (first ? "first" : "second")) {
                let amount = CGFloat(Double(parts[9])!)
                value = parts[8] == "tracking" ? value.tracking(amount) : value.kerning(amount)
            }
            let enabled = geometry ? decorationScope == "both" || decorationScope == (first ? "first" : "second") : kind != "none" &&
                (style == "both" || (style == "first") == first)
            if enabled {
                value = kind == "underline" || kind == "combined"
                    ? value.underline(pattern: decorationPattern(first: first), color: decorationColor(first: first))
                    : value.strikethrough(pattern: decorationPattern(first: first), color: decorationColor(first: first))
            }
            if kind == "combined", parts[20] == "both" || parts[20] == (first ? "first" : "second") {
                value = value.strikethrough(pattern: decorationPattern(first: first, strike: true),
                    color: decorationColor(first: first, strike: true))
            }
            return value
        }
        func components(_ color: VUI.Color.Resolved) -> [CGFloat] {
            [color.linearRed, color.linearGreen, color.linearBlue, color.opacity].map(CGFloat.init)
        }
        func checkColors(_ actual: [[CGFloat]], _ expected: [[CGFloat]], _ label: String) {
            XCTAssertEqual(actual.count, expected.count, label)
            for (a, b) in zip(actual, expected) {
                XCTAssertEqual(a.count, b.count, label)
                for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-6, label) }
            }
        }
        func recordedColors(_ items: [RBDisplayList.Item], _ label: String) throws -> [[CGFloat]] {
            try items.compactMap { item in
                guard case let .text(drawing, shading) = item.contents,
                      case .decoration = drawing.contents else { return nil }
                XCTAssertEqual(shading.properties.count, 1, label)
                guard case let .color(color) = try XCTUnwrap(shading.properties.first) else {
                    XCTFail("Expected explicit decoration color: \(label)")
                    return nil
                }
                return components(color.resolve(in: .init()))
            }
        }
        func recordedOrder(_ items: [RBDisplayList.Item]) -> [String] {
            var order: [String] = []
            for item in items {
                guard case let .text(drawing, _) = item.contents else { continue }
                let stage: String
                switch drawing.contents {
                case .decoration: stage = "decoration"
                case .glyphs, .vectorGlyphs: stage = "glyphs"
                default: continue
                }
                if stage != "glyphs" || order.last != stage { order.append(stage) }
            }
            return order
        }
        func recordedDecorations(_ items: [RBDisplayList.Item]) -> [(ResolvedTextSource.Drawing.Decoration, CGFloat)] {
            items.compactMap { item in
                guard case let .text(drawing, _) = item.contents,
                      case let .decoration(decoration) = drawing.contents else { return nil }
                return (decoration, drawing.scale)
            }
        }
        var text = run("AAA ", first: true) + run("BBB BBB" + separator, first: false)
        if !separator.isEmpty { text = text + Text(verbatim: "CCC").font(.file(file, size: 17)).foregroundColor(.green) }
        try withOwner(text, configure: {
            $0.displayScale = fixture.scale; $0.minimumScaleFactor = 1; $0.lineLimit = 1
        }) { ordinary in
            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
            let request = CGSize(width: fixture.width, height: fixture.height)
            for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                let label = "\(fixture.sample) \(fixture.draw) scale=\(fixture.scale) custom=\(custom) attributed=\(attributed) width=\(fixture.width)"
                let metrics = owner.metrics(in: request, layoutMargins: nil)
                let size = metrics.size
                if let expected = custom ? fixture.customMetrics : fixture.ordinaryMetrics {
                    let actual = [size.width, size.height, metrics.firstBaseline, metrics.lastBaseline]
                    XCTAssertEqual(actual, expected, label)
                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                }
                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: size, applyingMarginOffsets: true))
                XCTAssertEqual(prepared.lines.count, 1, label)
                if let expected = custom ? fixture.customGlyphs : fixture.ordinaryGlyphs {
                    let glyphs = try XCTUnwrap(prepared.lines.first).glyphs
                    let unit = 1 / prepared.source.scaleFactor
                    XCTAssertEqual(glyphs.count, expected.count, label)
                    var position = CGPoint.zero
                    for (index, pair) in zip(glyphs, expected).enumerated() {
                        let (glyph, values) = pair
                        if index != 0 { position += glyph.kerning }
                        let actual = [CGFloat(try XCTUnwrap(glyph.glyphIndex)), CGFloat(glyph.characterIndex),
                            (position.x + glyph.positionOffset.x) * unit,
                            (position.y + glyph.positionOffset.y + glyph.baselineOffset) * unit,
                            glyph.advance.width * unit]
                        for (a, b) in zip(actual, values) { XCTAssertEqual(a, b, accuracy: 1e-9, label) }
                        position.x += glyph.advance.width
                    }
                }
                if custom {
                    let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: size,
                        shading: .color(.black), layoutDirection: .leftToRight))
                    var line = try XCTUnwrap(layout.first)
                    line.origin = CGPoint(x: fixture.origin[0], y: fixture.origin[1])
                    let actual: [Text.Layout.Decorations]
                    if fixture.draw == "line" {
                        actual = [.init(line: line, scale: fixture.scale)]
                    } else {
                        actual = line.map { run in
                            if fixture.draw == "runs" { return .init(run: run, scale: fixture.scale) }
                            let lower = ["whole", "prefix"].contains(fixture.draw) ? 0 : min(1, run.endIndex)
                            let upper = fixture.draw == "empty" ? lower : ["prefix", "middle"].contains(fixture.draw)
                                ? max(lower, run.endIndex - 1) : run.endIndex
                            return .init(slice: run[lower..<upper], scale: fixture.scale)
                        }
                    }
                    let viewport = CGRect(x: 0, y: 0, width: 256, height: 100)
                    let context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                        inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                            contentScaleFactor: fixture.scale, resourceCommandQueue: nil))
                    if fixture.draw == "line" { context.draw(line) }
                    else {
                        for run in line {
                            if fixture.draw == "runs" { context.draw(run) }
                            else {
                                let lower = ["whole", "prefix"].contains(fixture.draw) ? 0 : min(1, run.endIndex)
                                let upper = fixture.draw == "empty" ? lower : ["prefix", "middle"].contains(fixture.draw)
                                    ? max(lower, run.endIndex - 1) : run.endIndex
                                context.draw(run[lower..<upper])
                            }
                        }
                    }
                    let commands = try XCTUnwrap(context.recording).moveContents().items
                    if let expected = fixture.customOrder {
                        XCTAssertEqual(recordedOrder(commands), expected, label)
                    }
                    var submitted: [[CGFloat]] = []
                    var sawDecoration = false
                    for command in commands {
                        if case let .text(drawing, _) = command.contents {
                            if case let .decoration(decoration) = drawing.contents {
                                submitted.append([decoration.lineWidth, decoration.start.x, decoration.start.y,
                                    decoration.end.x, decoration.end.y])
                                sawDecoration = true
                            } else if fixture.draw == "line" {
                                XCTAssertFalse(sawDecoration, "Glyphs must precede line decorations: \(label)")
                            }
                        }
                    }
                    let expectedPaths = fixture.custom.flatMap { $0 }.flatMap { values in
                        stride(from: 3, to: values.count, by: 4).map { [values[2]] + Array(values[$0..<$0 + 4]) }
                    }
                    XCTAssertEqual(submitted.count, expectedPaths.count, label)
                    for (path, expected) in zip(submitted, expectedPaths) {
                        for (a, b) in zip(path, expected) { XCTAssertEqual(a, b, accuracy: 1e-9, label) }
                    }
                    XCTAssertEqual(actual.count, fixture.custom.count, label)
                    for (collection, expected) in zip(actual, fixture.custom) {
                        XCTAssertEqual(collection.segments.count, expected.count, label)
                        for (segment, values) in zip(collection.segments, expected) {
                            XCTAssertEqual(segment.runs, Int(values[0])..<Int(values[1]), label)
                            XCTAssertEqual(segment.thickness, values[2], accuracy: 1e-9, label)
                            if fixture.customDashes == nil {
                                XCTAssertTrue(segment.dashes.isEmpty, label)
                            }
                            let coordinates = segment.fragments.flatMap { [$0.start.x, $0.start.y, $0.end.x, $0.end.y] }
                            XCTAssertEqual(coordinates.count, values.count - 3, label)
                            for (a, b) in zip(coordinates, values.dropFirst(3)) { XCTAssertEqual(a, b, accuracy: 1e-9, label) }
                        }
                    }
                    if let colors = fixture.customColors {
                        XCTAssertEqual(actual.count, colors.count, label)
                        for (collection, expected) in zip(actual, colors) {
                            checkColors(collection.segments.map { components($0.color) }, expected, label)
                        }
                        let expected = zip(fixture.custom, colors).flatMap { segments, colors in
                            zip(segments, colors).flatMap { segment, color in
                                Array(repeating: color, count: (segment.count - 3) / 4)
                            }
                        }
                        checkColors(try recordedColors(commands, label), expected, label)
                    }
                    if let dashes = fixture.customDashes {
                        XCTAssertEqual(actual.map { $0.segments.map(\.dashes) }, dashes, label)
                        let expected = zip(fixture.custom, dashes).flatMap { segments, dashes in
                            zip(segments, dashes).flatMap { segment, dash in
                                stride(from: 3, to: segment.count, by: 4).map { (dash, segment[$0]) }
                            }
                        }
                        let records = recordedDecorations(commands)
                        XCTAssertEqual(records.count, expected.count, label)
                        for ((record, scale), (dash, phase)) in zip(records, expected) {
                            XCTAssertEqual(scale, 1, label)
                            XCTAssertEqual(record.dashes, dash, label)
                            XCTAssertEqual(record.dashPhase, phase, accuracy: 1e-9, label)
                        }
                    }
                } else {
                    let drawing = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
                    let line = try XCTUnwrap(prepared.lines.first)
                    let scale = prepared.source.scaleFactor
                    XCTAssertEqual(drawing.decorations.count, fixture.ordinary.count, label)
                    for (decoration, expected) in zip(drawing.decorations, fixture.ordinary) {
                        let values = [decoration.lineWidth / scale,
                            (decoration.start.x - line.originX) / scale, (decoration.start.y - line.baseline) / scale,
                            (decoration.end.x - line.originX) / scale, (decoration.end.y - line.baseline) / scale]
                        for (a, b) in zip(values, expected) { XCTAssertEqual(a, b, accuracy: 1e-9, label) }
                    }
                    if let colors = fixture.ordinaryColors {
                        let actual = try drawing.decorations.map {
                            components(try XCTUnwrap($0.foregroundColor).resolve(in: .init()))
                        }
                        checkColors(actual, colors, label)
                        let viewport = CGRect(x: 0, y: 0, width: 256, height: 100)
                        let context = GraphicsContext(recording: RBDisplayList(viewport: viewport), environment: .init(),
                            inputs: .init(sceneResources: SceneResources(), viewport: viewport,
                                contentScaleFactor: fixture.scale, resourceCommandQueue: nil))
                        context.draw(drawing, in: CGRect(origin: .zero, size: size), shading: .color(.black), clipBounds: false)
                        let commands = try XCTUnwrap(context.recording).moveContents().items
                        if kind == "combined" {
                            XCTAssertEqual(recordedOrder(commands),
                                ["glyphs"] + Array(repeating: "decoration", count: drawing.decorations.count), label)
                        }
                        checkColors(try recordedColors(commands, label), colors, label)
                        if let dashes = fixture.ordinaryDashes, let phases = fixture.ordinaryPhases {
                            XCTAssertEqual(drawing.decorations.count, dashes.count, label)
                            for (decoration, dash) in zip(drawing.decorations, dashes) {
                                XCTAssertEqual(decoration.dashes?.map { $0 / scale }, dash, label)
                            }
                            let records = recordedDecorations(commands)
                            XCTAssertEqual(records.count, phases.count, label)
                            for ((record, drawingScale), phase) in zip(records, phases) {
                                XCTAssertEqual(record.dashPhase * drawingScale, phase, accuracy: 1e-9, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTokensPreserveDecorationAttributesAndSourceRanges() throws {
        // ASSERTIONS textTailDecorationAttributes27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let body = Array("AAA BBB BBB".unicodeScalars)
        for scale: CGFloat in [1, 2] {
            for kind in ["none", "underline", "strikethrough"] {
                for scope in (kind == "none" ? ["both"] : ["first", "second", "both"]) {
                    func run(_ string: String, first: Bool) -> Text {
                        let value = Text(verbatim: string).font(.file(file, size: first ? 23 : 31))
                            .foregroundColor(first ? .red : .blue)
                        guard kind != "none", scope == "both" || (scope == "first") == first else { return value }
                        return kind == "underline" ? value.underline() : value.strikethrough()
                    }
                    for separator in ["", "\n", "\u{2028}"] {
                        var value = run("AAA ", first: true) + run("BBB BBB", first: false)
                        if !separator.isEmpty {
                            value = value + run(separator, first: false)
                                + Text(verbatim: "CCC").font(.file(file, size: 17))
                        }
                        for width: CGFloat in [80, 190, 240] {
                            try withOwner(value, configure: {
                                $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                            }) { ordinary in
                                let original = try XCTUnwrap(ordinary.resolvedText).unwrappedGlyphLines().flatMap(\.glyphs).map(\.style)
                                let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                    layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                                for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                    let label = "\(kind) \(scope) \(separator.debugDescription) width=\(width) scale=\(scale) custom=\(custom)"
                                    let short = width == 80
                                    let noToken = separator.isEmpty && !short
                                    let kept = short ? 3 : 11
                                    let firstToken = short ? custom : width == 190
                                    let tokenSize: CGFloat = firstToken ? 23 : 31
                                    let wrapped = short && !custom && !separator.isEmpty
                                    let baseline: CGFloat = wrapped ? 21 : 29
                                    let descent: CGFloat = wrapped ? 6 : 8
                                    let rawWidth = body.prefix(kept).enumerated().reduce(CGFloat.zero) { total, element in
                                        let units: CGFloat = element.element == "A" ? 1336 : element.element == "B" ? 1276 : 508
                                        return total + units * (element.offset < 4 ? 23 : 31) / 2048
                                    } + (noToken ? 0 : 1370 * tokenSize / 2048)
                                    let request = CGSize(width: width, height: 60)
                                    let metrics = owner.metrics(in: request, layoutMargins: nil)
                                    XCTAssertEqual(metrics.size, CGSize(width: ceil(rawWidth * scale) / scale,
                                        height: baseline + descent), label)
                                    XCTAssertEqual(metrics.firstBaseline, baseline, label)
                                    XCTAssertEqual(metrics.lastBaseline, baseline, label)
                                    XCTAssertEqual(metrics.scale, 1, label)
                                    XCTAssertEqual(metrics.numberOfLines, 1, label)
                                    XCTAssertEqual(metrics.hasTruncatedRanges, short || (custom && separator == "\n"), label)
                                    let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                        applyingMarginOffsets: true))
                                    let line = try XCTUnwrap(prepared.lines.first)
                                    let drawingScale = prepared.source.scaleFactor
                                    XCTAssertEqual(line.baseline / drawingScale, baseline, label)
                                    XCTAssertEqual(line.height / drawingScale, baseline + descent, label)
                                    XCTAssertEqual(line.glyphs.map(\.scalar), Array(body.prefix(kept)) + (noToken ? [] : Array("…".unicodeScalars)), label)
                                    XCTAssertEqual(line.glyphs.map(\.characterIndex), Array(0..<(kept + (noToken ? 0 : 1))), label)
                                    XCTAssertEqual(line.width / drawingScale, rawWidth, label)
                                    for (index, glyph) in line.glyphs.enumerated() {
                                        let first = index == kept ? firstToken : index < 4
                                        let enabled = kind != "none" && (scope == "both" || (scope == "first") == first)
                                        XCTAssertEqual(glyph.style.underlineStyle,
                                            enabled && kind == "underline" ? Text.LineStyle() : nil, label)
                                        XCTAssertEqual(glyph.style.strikethroughStyle,
                                            enabled && kind == "strikethrough" ? Text.LineStyle() : nil, label)
                                        XCTAssertEqual(glyph.baselineOffset, 0, label)
                                    }
                                    if !noToken {
                                        let token = try XCTUnwrap(line.glyphs.last)
                                        let inherited = try XCTUnwrap(prepared.source.unwrappedGlyphLines().flatMap(\.glyphs)
                                            .first { $0.characterIndex == (firstToken ? 0 : 4) })
                                        XCTAssertTrue(token.isTruncationToken, label)
                                        XCTAssertEqual(token.style.fontResource?.pointSize, tokenSize, label)
                                        XCTAssertEqual(token.style.underlineStyle, inherited.style.underlineStyle, label)
                                        XCTAssertEqual(token.style.strikethroughStyle, inherited.style.strikethroughStyle, label)
                                        XCTAssertEqual(token.style.foregroundColor, inherited.style.foregroundColor, label)
                                        XCTAssertEqual(token.advance.width / drawingScale, 1370 * tokenSize / 2048, label)
                                    }
                                    let selected = prepared.source.makeGlyphLayout(in: request, layoutProperties: owner.layoutProperties,
                                        truncationTolerance: custom ? 0.001 : 0.0002, layoutScope: custom ? .paragraph : .document)
                                    XCTAssertEqual(selected.truncatedRanges, short ? [3..<11] : [], label)
                                    if custom {
                                        let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                            shading: .color(.black), layoutDirection: .leftToRight))
                                        let publicLine = try XCTUnwrap(layout.first)
                                        XCTAssertEqual(publicLine.typographicBounds.ascent, baseline, label)
                                        XCTAssertEqual(publicLine.typographicBounds.descent, descent, label)
                                        XCTAssertEqual(publicLine.typographicBounds.width, rawWidth, label)
                                        XCTAssertEqual(layout.isTruncated, short, label)
                                        if !noToken {
                                            XCTAssertEqual(publicLine.last?.typographicBounds.rect.minY,
                                                publicLine.origin.y - tokenSize * 1900 / 2048, label)
                                        }
                                    }
                                    XCTAssertEqual(try XCTUnwrap(owner.resolvedText).unwrappedGlyphLines().flatMap(\.glyphs).map(\.style), original, label)
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                    else { ordinary.resetCache() }
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                        applyingMarginOffsets: true))
                                    XCTAssertEqual(rebuilt.lines.first?.baseline, line.baseline, label)
                                    XCTAssertEqual(rebuilt.lines.first?.glyphs.map(\.style), line.glyphs.map(\.style), label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTokensPreserveBaselineOffsetsAndOriginalLineMetrics() throws {
        // ASSERTIONS textTailBaselineAttributes27Observed
        // ASSERTIONS textTailBaselineMetrics27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let body = Array("AAA BBB BBB".unicodeScalars)
        for scale: CGFloat in [1, 2] {
            for offset: CGFloat in [-3, 0, 3] {
                for scope in ["first", "second", "both"] {
                    let firstOffset: CGFloat = scope == "second" ? 0 : offset
                    let secondOffset: CGFloat = scope == "first" ? 0 : offset
                    func run(_ string: String, first: Bool) -> Text {
                        let value = Text(verbatim: string).font(.file(file, size: first ? 23 : 31))
                            .foregroundColor(first ? .red : .blue)
                        return (first && scope == "second") || (!first && scope == "first")
                            ? value : value.baselineOffset(offset)
                    }
                    for separator in ["", "\n", "\u{2028}"] {
                        var value = run("AAA ", first: true) + run("BBB BBB", first: false)
                        if !separator.isEmpty {
                            value = value + run(separator, first: false)
                                + Text(verbatim: "CCC").font(.file(file, size: 17))
                        }
                        for width: CGFloat in [80, 190, 240] {
                            try withOwner(value, configure: {
                                $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                            }) { ordinary in
                                let original = try XCTUnwrap(ordinary.resolvedText).unwrappedGlyphLines().flatMap(\.glyphs).map(\.baselineOffset)
                                let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                    layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                                for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                    let label = "offset=\(offset) \(scope) \(separator.debugDescription) width=\(width) scale=\(scale) custom=\(custom)"
                                    let short = width == 80
                                    let noToken = separator.isEmpty && !short
                                    let kept = short ? 3 : 11
                                    let firstToken = short ? custom : width == 190
                                    let tokenSize: CGFloat = firstToken ? 23 : 31
                                    let tokenOffset = firstToken ? firstOffset : secondOffset
                                    let wrapped = short && !custom && !separator.isEmpty
                                    let baseline: CGFloat = wrapped ? 21 + max(firstOffset, 0) : 29 + max(secondOffset, 0)
                                    let descent: CGFloat = wrapped ? 6 - min(firstOffset, 0)
                                        : max(6 - min(firstOffset, 0), 8 - min(secondOffset, 0))
                                    let rawWidth = body.prefix(kept).enumerated().reduce(CGFloat.zero) { total, element in
                                        let units: CGFloat = element.element == "A" ? 1336 : element.element == "B" ? 1276 : 508
                                        return total + units * (element.offset < 4 ? 23 : 31) / 2048
                                    } + (noToken ? 0 : 1370 * tokenSize / 2048)
                                    let request = CGSize(width: width, height: 60)
                                    let metrics = owner.metrics(in: request, layoutMargins: nil)
                                    XCTAssertEqual(metrics.size, CGSize(width: ceil(rawWidth * scale) / scale,
                                        height: baseline + descent), label)
                                    XCTAssertEqual(metrics.firstBaseline, baseline, label)
                                    XCTAssertEqual(metrics.lastBaseline, baseline, label)
                                    XCTAssertEqual(metrics.scale, 1, label)
                                    XCTAssertEqual(metrics.numberOfLines, 1, label)
                                    XCTAssertEqual(metrics.hasTruncatedRanges, short || (custom && separator == "\n"), label)
                                    let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                        applyingMarginOffsets: true))
                                    let line = try XCTUnwrap(prepared.lines.first)
                                    let drawingScale = prepared.source.scaleFactor
                                    XCTAssertEqual(line.baseline / drawingScale, baseline, label)
                                    XCTAssertEqual(line.height / drawingScale, baseline + descent, label)
                                    XCTAssertEqual(line.glyphs.map(\.scalar), Array(body.prefix(kept)) + (noToken ? [] : Array("…".unicodeScalars)), label)
                                    XCTAssertEqual(line.glyphs.map(\.characterIndex), Array(0..<(kept + (noToken ? 0 : 1))), label)
                                    XCTAssertEqual(line.width / drawingScale, rawWidth, label)
                                    for (index, glyph) in line.glyphs.enumerated() {
                                        let expectedOffset = index == kept ? tokenOffset : index < 4 ? firstOffset : secondOffset
                                        XCTAssertEqual(glyph.baselineOffset / drawingScale, expectedOffset, label)
                                    }
                                    if !noToken {
                                        let token = try XCTUnwrap(line.glyphs.last)
                                        let inherited = try XCTUnwrap(prepared.source.unwrappedGlyphLines().flatMap(\.glyphs)
                                            .first { $0.characterIndex == (firstToken ? 0 : 4) })
                                        XCTAssertTrue(token.isTruncationToken, label)
                                        XCTAssertEqual(token.style.fontResource?.pointSize, tokenSize, label)
                                        XCTAssertEqual(token.style.baselineOffset, inherited.style.baselineOffset, label)
                                        XCTAssertEqual(token.style.foregroundColor, inherited.style.foregroundColor, label)
                                        XCTAssertEqual(token.advance.width / drawingScale, 1370 * tokenSize / 2048, label)
                                    }
                                    let selected = prepared.source.makeGlyphLayout(in: request, layoutProperties: owner.layoutProperties,
                                        truncationTolerance: custom ? 0.001 : 0.0002, layoutScope: custom ? .paragraph : .document)
                                    XCTAssertEqual(selected.truncatedRanges, short ? [3..<11] : [], label)
                                    if custom {
                                        let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                            shading: .color(.black), layoutDirection: .leftToRight))
                                        let publicLine = try XCTUnwrap(layout.first)
                                        XCTAssertEqual(publicLine.typographicBounds.ascent, baseline, label)
                                        XCTAssertEqual(publicLine.typographicBounds.descent, descent, label)
                                        XCTAssertEqual(publicLine.typographicBounds.width, rawWidth, label)
                                        XCTAssertEqual(layout.isTruncated, short, label)
                                        if !noToken {
                                            XCTAssertEqual(publicLine.last?.typographicBounds.rect.minY,
                                                publicLine.origin.y - tokenOffset - tokenSize * 1900 / 2048, label)
                                        }
                                    }
                                    XCTAssertEqual(try XCTUnwrap(owner.resolvedText).unwrappedGlyphLines().flatMap(\.glyphs).map(\.baselineOffset), original, label)
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                    else { ordinary.resetCache() }
                                    XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                        applyingMarginOffsets: true))
                                    XCTAssertEqual(rebuilt.lines.first?.baseline, line.baseline, label)
                                    XCTAssertEqual(rebuilt.lines.first?.glyphs.map(\.baselineOffset), line.glyphs.map(\.baselineOffset), label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTrackedTailTokenFitsWithItsNetWidthAtFractionalBoundaries() throws {
        // ASSERTIONS textTailAdjustedAdvance27Observed
        // ASSERTIONS textTailTokenSpacing27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for scale: CGFloat in [1, 2] {
            for kind in ["kern", "tracking"] {
                for separator in ["", "\n"] {
                    func run(_ string: String, size: CGFloat) -> Text {
                        let value = Text(verbatim: string).font(.file(file, size: size))
                        return kind == "kern" ? value.kerning(1.5) : value.tracking(1.5)
                    }
                    var value = run("AAA ", size: 23) + run("BBB BBB", size: 31)
                    if !separator.isEmpty { value = value + run(separator, size: 31) + Text(verbatim: "CCC").font(.file(file, size: 17)) }
                    var cases: [(CGFloat, Bool)] = [98.2674546875, 98.2683546875, 98.2685546875].map { ($0, false) }
                    if kind == "tracking" {
                        cases += [189.2919921875, 189.29296875, 189.2939453125].map { ($0, true) }
                    }
                    for (width, bodyBoundary) in cases {
                        try withOwner(value, configure: {
                            $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                        }) { ordinary in
                            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                            for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                let label = "\(kind) \(separator.debugDescription) width=\(width) scale=\(scale) custom=\(custom)"
                                let kept: Int
                                let noToken = bodyBoundary && separator.isEmpty && width >= 189.29296875
                                if bodyBoundary { kept = noToken ? 11 : 9 }
                                else { kept = kind == "tracking" && width >= (custom ? 98.2683546875 : 98.2685546875) ? 5 : 3 }
                                let tokenSize: CGFloat = custom && kept == 3 ? 23 : 31
                                let body = Array("AAA BBB BBB".unicodeScalars.prefix(kept))
                                let rawWidth = body.enumerated().reduce(CGFloat.zero) { total, element in
                                    let units: CGFloat = element.element == "A" ? 1336 : element.element == "B" ? 1276 : 508
                                    return total + units * (element.offset < 4 ? 23 : 31) / 2048 + 1.5
                                } + (noToken ? 0 : 1370 * tokenSize / 2048 + 1.5)
                                let measuredWidth = min(width, rawWidth - (kind == "tracking" && !custom && !separator.isEmpty ? 1.5 : 0))
                                let request = CGSize(width: width, height: 60)
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(metrics.size.width, ceil(measuredWidth * scale) / scale, label)
                                XCTAssertEqual(metrics.size.height, !bodyBoundary && !custom && !separator.isEmpty ? 27 : 37, label)
                                XCTAssertEqual(metrics.firstBaseline, !bodyBoundary && !custom && !separator.isEmpty ? 21 : 29, label)
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size, applyingMarginOffsets: true))
                                let glyphs = try XCTUnwrap(prepared.lines.first).glyphs
                                XCTAssertEqual(glyphs.map(\.scalar), body + (noToken ? [] : Array("…".unicodeScalars)), label)
                                XCTAssertEqual(glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width + $1.kerning.x }
                                    / prepared.source.scaleFactor, rawWidth, label)
                                let selected = prepared.source.makeGlyphLayout(in: request, layoutProperties: owner.layoutProperties,
                                    truncationTolerance: custom ? 0.001 : 0.0002,
                                    layoutScope: custom ? .paragraph : .document)
                                XCTAssertEqual(selected.truncatedRanges, noToken ? [] : [kept..<11], label)
                                if custom {
                                    let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                        shading: .color(.black), layoutDirection: .leftToRight))
                                    XCTAssertEqual(layout.first?.typographicBounds.width, measuredWidth, label)
                                    XCTAssertEqual(layout.isTruncated, !noToken, label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailSpacingSeparatesFittingAndPublishedWidths() throws {
        // ASSERTIONS textTailAdjustedAdvance27Observed
        // ASSERTIONS textTailTokenSpacing27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let body = Array("AAA BBB BBB".unicodeScalars)
        for scale: CGFloat in [1, 2] {
            for kind in ["kern", "tracking"] {
                for spacing: CGFloat in [-1, 0, 1.5] {
                    let scopes = kind == "tracking" && spacing == 1.5 ? ["both", "first", "second"] : ["both"]
                    for scope in scopes {
                        let firstSpacing: CGFloat = scope == "second" ? 0 : spacing
                        let secondSpacing: CGFloat = scope == "first" ? 0 : spacing
                        func run(_ string: String, size: CGFloat, first: Bool) -> Text {
                            let value = Text(verbatim: string).font(.file(file, size: size)).foregroundColor(first ? .red : .blue)
                            let amount = first ? firstSpacing : secondSpacing
                            return kind == "kern" ? value.kerning(amount) : value.tracking(amount)
                        }
                        for separator in ["", "\n", "\u{2028}"] {
                            var value = run("AAA ", size: 23, first: true) + run("BBB BBB", size: 31, first: false)
                            if !separator.isEmpty {
                                value = value + run(separator, size: 31, first: false)
                                    + Text(verbatim: "CCC").font(.file(file, size: 17))
                            }
                            var widths: [CGFloat] = separator.isEmpty && spacing == 1.5 && scope == "both"
                                ? [80, 189, 189.5, 190, 191, 240] : [80, 190, 240]
                            if kind == "tracking" && spacing == 1.5 && !separator.isEmpty {
                                widths.append(scope == "both" ? 208 : scope == "first" ? 198 : 201)
                            }
                            for width in widths {
                                try withOwner(value, configure: {
                                    $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                                }) { ordinary in
                                    let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                        layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                                    for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                        let label = "\(kind)=\(spacing) \(scope) \(separator.debugDescription) width=\(width) scale=\(scale) custom=\(custom)"
                                        let short = width == 80
                                        let replacementOnly = [CGFloat(198), 201, 208].contains(width)
                                        let wholeInsertion = !separator.isEmpty && (width == 240 || spacing < 0)
                                        let noToken = separator.isEmpty && !short &&
                                            (scope != "both" || spacing <= 0 || width == 191 || width == 240 ||
                                             (kind == "tracking" && width >= 189.5))
                                        let kept = short ? 3 : wholeInsertion || replacementOnly || noToken || spacing == 0 ? 11 : scope == "both" ? 9 : 10
                                        let firstToken = short ? custom : replacementOnly || (!wholeInsertion && (spacing == 0 || (scope != "both" && !custom)))
                                        let tokenSize: CGFloat = firstToken ? 23 : 31
                                        let tokenSpacing = firstToken ? firstSpacing : secondSpacing
                                        let rawWidth = body.prefix(kept).enumerated().reduce(CGFloat.zero) { total, element in
                                            let units: CGFloat = element.element == "A" ? 1336 : element.element == "B" ? 1276 : 508
                                            return total + units * (element.offset < 4 ? 23 : 31) / 2048
                                                + (element.offset < 4 ? firstSpacing : secondSpacing)
                                        } + (noToken ? 0 : 1370 * tokenSize / 2048 + tokenSpacing)
                                        var measuredWidth = rawWidth
                                        if kind == "tracking" {
                                            if custom && wholeInsertion { measuredWidth += max(secondSpacing, 0) }
                                            if !custom && !separator.isEmpty && !wholeInsertion && !replacementOnly { measuredWidth -= max(tokenSpacing, 0) }
                                        }
                                        measuredWidth = min(width, measuredWidth)
                                        let request = CGSize(width: width, height: 60)
                                        let metrics = owner.metrics(in: request, layoutMargins: nil)
                                        XCTAssertEqual(metrics.size.width, ceil(measuredWidth * scale) / scale, label)
                                        XCTAssertEqual(metrics.size.height, short && !custom && !separator.isEmpty ? 27 : 37, label)
                                        XCTAssertEqual(metrics.firstBaseline, short && !custom && !separator.isEmpty ? 21 : 29, label)
                                        XCTAssertEqual(metrics.lastBaseline, metrics.firstBaseline, label)
                                        XCTAssertEqual(metrics.scale, 1, label)
                                        XCTAssertEqual(metrics.numberOfLines, 1, label)
                                        XCTAssertEqual(metrics.hasTruncatedRanges, kept < 11 || (custom && separator == "\n"), label)
                                        let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                            applyingMarginOffsets: true))
                                        let line = try XCTUnwrap(prepared.lines.first)
                                        XCTAssertEqual(line.glyphs.map(\.scalar), Array(body.prefix(kept)) + (noToken ? [] : Array("…".unicodeScalars)), label)
                                        XCTAssertEqual(line.glyphs.map(\.characterIndex), Array(0..<(kept + (noToken ? 0 : 1))), label)
                                        XCTAssertEqual(line.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width + $1.kerning.x }
                                            / prepared.source.scaleFactor, rawWidth, label)
                                        if !noToken {
                                            let token = try XCTUnwrap(line.glyphs.last)
                                            XCTAssertTrue(token.isTruncationToken, label)
                                            XCTAssertEqual(token.style.fontResource?.pointSize, tokenSize, label)
                                            let inherited = try XCTUnwrap(prepared.source.unwrappedGlyphLines().flatMap(\.glyphs)
                                                .first { $0.characterIndex == (firstToken ? 0 : 4) })
                                            XCTAssertEqual(token.style.foregroundColor, inherited.style.foregroundColor, label)
                                            XCTAssertEqual(token.advance.width / prepared.source.scaleFactor,
                                                1370 * tokenSize / 2048 + tokenSpacing, label)
                                        }
                                        if custom {
                                            let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                                shading: .color(.black), layoutDirection: .leftToRight))
                                            XCTAssertEqual(layout.first?.typographicBounds.width, measuredWidth, label)
                                            XCTAssertEqual(layout.isTruncated, kept < 11, label)
                                        }
                                        XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                        if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                        else { ordinary.resetCache() }
                                        XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testExplicitLineTailTokensSeparateInsertionFromEmptyRangeLookup() throws {
        // ASSERTIONS textTailEmptyRangeLookup27Observed
        // ASSERTIONS textTailTokenEmptyRangeAttributes27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for scale: CGFloat in [1, 2] {
            for separator in ["\n", "\u{2028}"] {
                for variant in ["uniform", "font", "color", "font-color", "prefix", "one"] {
                    let mixedFont = variant.contains("font") || variant == "prefix"
                    let mixedColor = variant.contains("color") || variant == "prefix"
                    let hasPrefix = variant == "prefix"
                    let one = variant == "one"
                    let secondSize: CGFloat = mixedFont ? 31 : 23
                    let firstColor: VUI.Color = mixedColor ? .red : .black
                    let secondColor: VUI.Color = mixedColor ? .blue : .black
                    var value = Text(verbatim: one ? "A" : "AAA ").font(.file(file, size: 23)).foregroundColor(firstColor)
                    if !one {
                        value = value + Text(verbatim: "BBB BBB").font(.file(file, size: secondSize)).foregroundColor(secondColor)
                    }
                    value = value + Text(verbatim: separator).font(.file(file, size: secondSize)).foregroundColor(secondColor)
                        + Text(verbatim: "CCC").font(.file(file, size: 17))
                    if hasPrefix {
                        value = Text(verbatim: "CCC" + separator).font(.file(file, size: 17)).foregroundColor(.green) + value
                    }
                    // Native controls specify the retained count and each owner's token source.
                    var cases: [(CGFloat, Int, Bool, Bool)] = mixedFont
                        ? [(185, 10, true, false), (190, 11, true, true), (240, 11, false, false)]
                        : [(150, 10, true, false), (160, 11, false, false), (200, 11, false, false)]
                    if one { cases = [(20, 0, true, true), (31, 1, false, false), (40, 1, false, false)] }
                    if variant == "font-color" {
                        cases += [(-0.0011, true, true), (-0.001, true, false), (-0.0002, false, false), (0, false, false)]
                            .map { (195.0302734375 + $0.0, 11, $0.1, $0.2) }
                    }
                    for (width, kept, ordinaryFirst, managerFirst) in cases {
                        try withOwner(value, configure: {
                            $0.lineLimit = hasPrefix ? 2 : 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                        }) { ordinary in
                            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                            for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                let label = "\(variant) \(separator.debugDescription) width=\(width) scale=\(scale) custom=\(custom)"
                                let firstAttributes = custom ? managerFirst : ordinaryFirst
                                let tokenSize: CGFloat = firstAttributes ? 23 : secondSize
                                let body = one ? "A" : "AAA BBB BBB"
                                let visible = Array(body.unicodeScalars.prefix(kept))
                                let rawWidth = visible.enumerated().reduce(CGFloat.zero) { total, value in
                                    let units: CGFloat = value.element == "A" ? 1336 : value.element == "B" ? 1276 : 508
                                    return total + units * (value.offset < 4 ? 23 : secondSize) / 2048
                                } + 1370 * tokenSize / 2048
                                let offset = hasPrefix ? 4 : 0
                                let removed = kept < body.utf16.count
                                let request = CGSize(width: width, height: hasPrefix ? 100 : 60)
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(metrics.size.width, ceil(rawWidth * scale) / scale, label)
                                XCTAssertEqual(metrics.size.height, (mixedFont ? 37 : 27) + (hasPrefix ? 20 : 0), label)
                                XCTAssertEqual(metrics.firstBaseline, hasPrefix ? 16 : (mixedFont ? 29 : 21), label)
                                XCTAssertEqual(metrics.lastBaseline, (mixedFont ? 29 : 21) + (hasPrefix ? 20 : 0), label)
                                XCTAssertEqual(metrics.scale, 1, label)
                                XCTAssertEqual(metrics.numberOfLines, hasPrefix ? 2 : 1, label)
                                XCTAssertEqual(metrics.hasTruncatedRanges, removed || (custom && separator == "\n"), label)
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                let line = try XCTUnwrap(prepared.lines.last)
                                XCTAssertEqual(line.glyphs.map(\.scalar), visible + Array("…".unicodeScalars), label)
                                XCTAssertEqual(line.glyphs.map(\.characterIndex), Array(offset...(offset + kept)), label)
                                XCTAssertEqual(line.width / prepared.source.scaleFactor, rawWidth, label)
                                let token = try XCTUnwrap(line.glyphs.last)
                                XCTAssertTrue(token.isTruncationToken, label)
                                XCTAssertEqual(token.style.fontResource?.pointSize, tokenSize, label)
                                let attributeIndex = offset + (firstAttributes || one ? 0 : 4)
                                let original = prepared.source.unwrappedGlyphLines().flatMap(\.glyphs)
                                let inherited = try XCTUnwrap(original.first { $0.characterIndex == attributeIndex })
                                XCTAssertEqual(token.style.foregroundColor, inherited.style.foregroundColor, label)
                                let selected = prepared.source.makeGlyphLayout(in: request, layoutProperties: owner.layoutProperties,
                                    truncationTolerance: custom ? 0.001 : 0.0002,
                                    layoutScope: custom ? .paragraph : .document)
                                XCTAssertEqual(selected.truncatedRanges,
                                    removed ? [(offset + kept)..<(offset + body.utf16.count)] : [], label)
                                if custom {
                                    let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                        shading: .color(.black), layoutDirection: .leftToRight))
                                    XCTAssertEqual(layout.isTruncated, removed, label)
                                    XCTAssertEqual(layout.last?.typographicBounds.width, min(width, rawWidth), label)
                                }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                else { ordinary.resetCache() }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                XCTAssertEqual(rebuilt.lines.last?.glyphs.last?.style.foregroundColor, token.style.foregroundColor, label)
                                XCTAssertEqual(rebuilt.lines.last?.glyphs.last?.characterIndex, offset + kept, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTokenAttributesFollowTheMeasurementOwnerAcrossRetries() throws {
        // ASSERTIONS textTailTokenAttributes27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for scale: CGFloat in [1, 2] {
            for mixedFont in [false, true] {
                for mixedColor in [false, true] {
                    let secondSize: CGFloat = mixedFont ? 31 : 23
                    let text = Text(verbatim: "AAA ").font(.file(file, size: 23))
                        .foregroundColor(mixedColor ? .red : .black)
                        + Text(verbatim: "BBB BBB").font(.file(file, size: secondSize))
                        .foregroundColor(mixedColor ? .blue : .black)
                    var cases: [(CGFloat, Int, Int)] = mixedFont
                        ? [(50, 2, 3), (60, 2, 3), (66, 3, 3), (80, 3, 5), (92, 5, 6), (130, 7, 7)]
                        : [(50, 2, 3), (60, 2, 3), (66, 3, 5), (80, 3, 6), (92, 5, 6), (130, 9, 10)]
                    let frontier: CGFloat = mixedFont ? 70.03125 : 65.046875
                    cases += [(-0.0011, 3), (-0.001, 3), (-0.0002, 3), (0, 5)].map {
                        (frontier + $0.0, 3, $0.1)
                    }
                    for (width, kept, initial) in cases {
                        try withOwner(text, configure: {
                            $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                        }) { ordinary in
                            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                            for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                let label = "scale=\(scale) mixedFont=\(mixedFont) mixedColor=\(mixedColor) width=\(width) custom=\(custom)"
                                let attributeIndex = custom ? kept : initial
                                let tokenSize: CGFloat = attributeIndex < 4 ? 23 : secondSize
                                let visible = Array("AAA BBB BBB".unicodeScalars.prefix(kept))
                                let rawWidth = visible.enumerated().reduce(CGFloat.zero) { width, value in
                                    let units: CGFloat = value.element == "A" ? 1336 : value.element == "B" ? 1276 : 508
                                    return width + units * (value.offset < 4 ? 23 : secondSize) / 2048
                                } + 1370 * tokenSize / 2048
                                let request = CGSize(width: width, height: 60)
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(metrics.size.width, ceil(rawWidth * scale) / scale, label)
                                XCTAssertEqual(metrics.scale, 1, label)
                                XCTAssertEqual(metrics.numberOfLines, 1, label)
                                XCTAssertTrue(metrics.hasTruncatedRanges, label)
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                let glyphs = try XCTUnwrap(prepared.lines.first).glyphs
                                XCTAssertEqual(glyphs.map(\.scalar), visible + Array("…".unicodeScalars), label)
                                XCTAssertEqual(glyphs.map(\.characterIndex), Array(0...kept), label)
                                let token = try XCTUnwrap(glyphs.last)
                                XCTAssertTrue(token.isTruncationToken, label)
                                XCTAssertEqual(token.style.fontResource?.pointSize, tokenSize, label)
                                let original = prepared.source.unwrappedGlyphLines().flatMap(\.glyphs)
                                let inherited = try XCTUnwrap(original.first { $0.characterIndex == attributeIndex })
                                XCTAssertEqual(token.style.foregroundColor, inherited.style.foregroundColor, label)
                                XCTAssertEqual(prepared.lines[0].width / prepared.source.scaleFactor, rawWidth, label)
                                let selected = prepared.source.makeGlyphLayout(in: request,
                                    layoutProperties: owner.layoutProperties,
                                    truncationTolerance: custom ? 0.001 : 0.0002)
                                XCTAssertEqual(selected.truncatedRanges, [kept..<11], label)
                                let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                if custom {
                                    XCTAssertTrue(layout.isTruncated, label)
                                    XCTAssertEqual(layout.first?.typographicBounds.width, rawWidth, label)
                                }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                XCTAssertEqual(owner.metricsCacheEntryCount, 1, label)
                                if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                else { ordinary.resetCache() }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                XCTAssertEqual(rebuilt.lines[0].glyphs.last?.style.foregroundColor, token.style.foregroundColor, label)
                                XCTAssertEqual(rebuilt.lines[0].glyphs.last?.style.fontResource?.pointSize, tokenSize, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailCharacterFittingUsesTheMeasurementOwnersTolerance() throws {
        // ASSERTIONS textTailCharacterFit27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for scale: CGFloat in [1, 2] {
            for separator in ["\n", "\u{2028}"] {
                let text = Text(verbatim: "AAA AAA" + separator)
                    + Text(verbatim: "BBB BBB").font(.file(file, size: 31))
                for (frontier, upper, lower, lowerWidth): (CGFloat, String, String, CGFloat) in [
                    (60.3974609375, "AAA…", "AA…", 45.3935546875),
                    (81.1064453125, "AAA A…", "AAA…", 60.3974609375)
                ] {
                    let cases: [(CGFloat, Bool, Bool)] = [
                        (floor(frontier), false, false), (ceil(frontier), true, true),
                        (frontier - 0.0011, false, false),
                        ((frontier - 0.001).nextDown, false, false),
                        (frontier - 0.001, false, frontier == 60.3974609375),
                        (frontier - 1 / 1024, false, true),
                        ((frontier - 0.0002).nextDown, false, true),
                        (frontier - 0.0002, frontier == 60.3974609375, true),
                        (frontier - 0.0001, true, true), (frontier, true, true),
                        (frontier + 0.0002, true, true),
                        (frontier + 1 / 1024, true, true), (frontier + 0.001, true, true)
                    ]
                    for (width, ordinaryKeeps, managerKeeps) in cases {
                        try withOwner(text, configure: {
                            $0.lineLimit = 1; $0.minimumScaleFactor = 1; $0.displayScale = scale
                        }) { ordinary in
                            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: ordinary.layoutProperties,
                                layoutMargins: ordinary.layoutMargins, resolvedText: ordinary.resolvedText)
                            for (custom, owner): (Bool, ResolvedStyledText) in [(false, ordinary), (true, manager)] {
                                let label = "scale=\(scale) separator=\(separator.debugDescription) width=\(width) custom=\(custom)"
                                let keeps = custom ? managerKeeps : ordinaryKeeps
                                let visible = keeps ? upper : lower
                                let glyphWidth = keeps ? frontier : lowerWidth
                                let fragmentWidth = min(width, glyphWidth)
                                let request = CGSize(width: width, height: 60)
                                let storage = owner.storage
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(metrics.scale, 1, label)
                                XCTAssertEqual(metrics.size, CGSize(width: ceil(glyphWidth * scale) / scale, height: 27), label)
                                XCTAssertEqual(metrics.firstBaseline, 21, label)
                                XCTAssertEqual(metrics.lastBaseline, 21, label)
                                XCTAssertEqual(metrics.numberOfLines, 1, label)
                                XCTAssertTrue(metrics.hasTruncatedRanges, label)
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                XCTAssertEqual(prepared.lines.map { $0.width / prepared.source.scaleFactor }, [glyphWidth], label)
                                XCTAssertEqual(prepared.lines.first?.glyphs.map(\.scalar), Array(visible.unicodeScalars), label)
                                XCTAssertTrue(prepared.lines.first?.glyphs.last?.isTruncationToken == true, label)
                                XCTAssertTrue(owner.storage === storage, label)
                                XCTAssertEqual(prepared.source.runs.compactMap { run -> CGFloat? in
                                    guard case let .styledText(_, _, _, attributes) = run else { return nil }
                                    return attributes.fontResource?.pointSize
                                }, [23, 31], label)
                                let selected = prepared.source.makeGlyphLayout(in: request,
                                    layoutProperties: owner.layoutProperties,
                                    truncationTolerance: custom ? 0.001 : 0.0002)
                                XCTAssertEqual(selected.truncatedRanges, [(visible.utf16.count - 1)..<7], label)
                                let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                if custom {
                                    XCTAssertEqual(layout.first?.typographicBounds.width, fragmentWidth, label)
                                    XCTAssertTrue(layout.isTruncated, label)
                                }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                XCTAssertEqual(owner.metricsCacheEntryCount, 1, label)
                                if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                else { ordinary.resetCache() }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                let rebuilt = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                XCTAssertEqual(rebuilt.lines.map(\.glyphs).map { $0.map(\.scalar) },
                                    prepared.lines.map(\.glyphs).map { $0.map(\.scalar) }, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTruncationIncludesTrailingSpacesInRemovedRanges() throws {
        // ASSERTIONS textTailTokenWhitespace27Observed
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let samples: [(gap: String, widths: [(CGFloat, CGFloat, Int)])] = [
            (" ", [(60, 45.5, 2), (61, 60.5, 3), (66, 60.5, 3), (67, 60.5, 3),
                   (80, 60.5, 3), (81, 60.5, 3), (82, 81.5, 5), (97, 96.5, 6), (112, 111.5, 7)]),
            ("", [(80, 75.5, 4), (97, 90.5, 5)]),
            ("  ", [(80, 60.5, 3), (97, 87, 6)]),
            ("   ", [(80, 60.5, 3), (97, 93, 7)]),
            ("\u{a0}", [(80, 60.5, 3), (97, 96.5, 6)]),
            ("\u{2009}", [(80, 60.5, 3), (97, 95.5, 6)]),
            ("\u{2003}", [(80, 60.5, 3), (97, 60.5, 3)])
        ]
        for (gap, widths) in samples {
            for separator in gap == " " ? ["\n", "\u{2028}"] : ["\u{2028}"] {
                for mixed in gap == " " ? [false, true] : [true] {
                    let firstLine = "AAA" + gap + "AAA"
                    let text = Text(verbatim: firstLine + separator)
                        + Text(verbatim: "BBB BBB").font(.file(file, size: mixed ? 31 : 23))
                    try withOwner(text, configure: { $0.lineLimit = 1; $0.minimumScaleFactor = 1 }) { source in
                        let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: source.layoutProperties,
                            layoutMargins: source.layoutMargins, resolvedText: source.resolvedText)
                        for (custom, owner): (Bool, ResolvedStyledText) in [(false, source), (true, manager)] {
                            for (width, measuredWidth, keptCount) in widths {
                                let label = "gap=\(gap.debugDescription) separator=\(separator.debugDescription) mixed=\(mixed) custom=\(custom) width=\(width)"
                                let request = CGSize(width: width, height: 60)
                                let removed = keptCount < firstLine.utf16.count
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(metrics.scale, 1, label)
                                XCTAssertEqual(metrics.size, CGSize(width: measuredWidth, height: 27), label)
                                XCTAssertEqual(metrics.firstBaseline, 21, label)
                                XCTAssertEqual(metrics.lastBaseline, 21, label)
                                XCTAssertEqual(metrics.numberOfLines, 1, label)
                                XCTAssertEqual(metrics.hasTruncatedRanges, removed || (custom && separator == "\n"), label)
                                let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                    applyingMarginOffsets: true))
                                XCTAssertEqual(prepared.lines.count, 1, label)
                                let expected = Array(firstLine.unicodeScalars.prefix(keptCount)) + Array("…".unicodeScalars)
                                XCTAssertEqual(prepared.lines[0].glyphs.map(\.scalar), expected, label)
                                XCTAssertTrue(prepared.lines[0].glyphs.last!.isTruncationToken, label)
                                let glyphLayout = prepared.source.makeGlyphLayout(in: metrics.size,
                                    layoutProperties: owner.layoutProperties)
                                XCTAssertEqual(glyphLayout.truncatedRanges,
                                    removed ? [keptCount..<firstLine.utf16.count] : [], label)
                                let layout = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                if custom { XCTAssertEqual(layout.isTruncated, removed, label) }
                                XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil), metrics, label)
                                if custom { manager.glyphLayoutCache.purgeResources(reason: .lowMemory) }
                                else { source.resetCache() }
                                let rebuilt = try XCTUnwrap(owner.makeLayout(in: .zero, with: metrics.size,
                                    shading: .color(.black), layoutDirection: .leftToRight))
                                XCTAssertEqual(rebuilt.isTruncated, layout.isTruncated, label)
                                XCTAssertEqual(rebuilt.map(\.typographicBounds.rect), layout.map(\.typographicBounds.rect), label)
                            }
                        }
                    }
                }
            }
        }
    }

    private func withManager(_ text: Text, configure: (inout EnvironmentValues) -> Void = { _ in },
                             _ body: (ResolvedStyledText.TextLayoutManager) throws -> Void) throws {
        try withOwner(text, configure: configure) { source in
            let manager = ResolvedStyledText.TextLayoutManager(layoutProperties: source.layoutProperties,
                layoutMargins: source.layoutMargins, resolvedText: source.resolvedText)
            try body(manager)
        }
    }

    private func withOwner(_ text: String, configure: (inout EnvironmentValues) -> Void = { _ in },
                           _ body: (ResolvedStyledText.StringDrawing) throws -> Void) throws {
        try withOwner(Text(verbatim: text), configure: configure, body)
    }

    private func withOwner(_ text: Text, configure: (inout EnvironmentValues) -> Void = { _ in },
                           _ body: (ResolvedStyledText.StringDrawing) throws -> Void) throws {
        let previous = appContext
        appContext = MetricsTestAppContext()
        defer { appContext = previous }
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        configure(&environment)
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let inputs = _ViewInputs(
                base: _GraphInputs(
                    time: graph.makeInput(value: Time(seconds: 0)),
                    phase: graph.makeInput(value: _GraphInputs.Phase()),
                    environment: graph.makeInput(value: environment),
                    transaction: graph.makeInput(value: Transaction())),
                customInputs: PropertyList(),
                preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: graph.makeInput(value: PreferenceKeys())),
                transform: graph.makeInput(value: ViewTransform()),
                position: graph.makeInput(value: CGPoint.zero),
                containerPosition: graph.makeInput(value: CGPoint.zero),
                size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
                safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil)
            let outputs = Text._makeView(view: _GraphValue(_attribute: graph.makeInput(value: text)),
                                         inputs: inputs)
            let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
            let engine = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            try body(XCTUnwrap(engine.text as? ResolvedStyledText.StringDrawing))
        }
    }
}

private final class MetricsTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
