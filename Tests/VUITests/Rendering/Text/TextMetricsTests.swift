import Foundation
import XCTest
import VVD
@testable import VUI

final class TextMetricsTests: XCTestCase {
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
