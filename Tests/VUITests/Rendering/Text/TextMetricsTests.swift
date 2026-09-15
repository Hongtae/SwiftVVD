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

    private func withOwner(_ text: String, configure: (inout EnvironmentValues) -> Void = { _ in },
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
            let outputs = Text._makeView(view: _GraphValue(_attribute: graph.makeInput(value: Text(verbatim: text))),
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
