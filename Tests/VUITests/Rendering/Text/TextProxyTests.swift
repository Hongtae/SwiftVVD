import Foundation
import XCTest
import VVD
@testable import VUI

final class TextProxyTests: XCTestCase {
    private var previousContext: (any AppContext)?
    private var scene = SceneResources()

    override func setUp() {
        previousContext = appContext
        appContext = ProxyTestAppContext()
        scene = SceneResources()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    // ASSERTIONS textRendererResolutionFeaturesObserved textIntrinsicBackendSelectionObserved
    // ASSERTIONS textProxyRetainedOwnerAndCacheObserved
    func testRealTextHostsCarryRendererFeaturesIntoTheRetainedOwner() throws {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            func engine<Content: View>(_ content: Content, archived: Bool = false) throws -> StyledTextLayoutEngine {
                var inputs = makeInputs(graph: graph, environment: environment)
                if archived { inputs[ArchivedViewInput.self] = .isArchived }
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)), inputs: inputs)
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }

            let text = Text(verbatim: "Alpha\nBeta")
            let bare = try engine(text)
            let capture = ProxyCapture()
            let custom = try engine(text.textRenderer(ProxyRecorder(capture: capture)))
            XCTAssertNotNil(bare.text.resolvedText)
            XCTAssertNotNil(custom.text.resolvedText)
            XCTAssertTrue(bare.text is ResolvedStyledText.StringDrawing)
            XCTAssertTrue(custom.text is ResolvedStyledText.TextLayoutManager)
            XCTAssertNil(bare.renderer)
            XCTAssertNotNil(custom.renderer)
            let rendererFeatures: Text.ResolvedProperties.Features = [.customRenderer, .produceTextLayout]
            XCTAssertEqual(bare.text.features.intersection(rendererFeatures), [])
            XCTAssertEqual(custom.text.features.intersection(rendererFeatures), rendererFeatures)
            XCTAssertTrue(bare.text.features.contains(.useTextSuffix))
            XCTAssertTrue(custom.text.features.contains(.useTextSuffix))

            let proposal = _ProposedSize(width: 100, height: 120)
            XCTAssertEqual(custom.sizeThatFits(proposal), bare.sizeThatFits(proposal))
            let proxy = try XCTUnwrap(capture.proxy)
            let retained = try XCTUnwrap(Mirror(reflecting: proxy).children.first?.value as? ResolvedStyledText)
            XCTAssertTrue(retained === custom.text)
            XCTAssertEqual(retained.features.intersection(rendererFeatures), rendererFeatures)
            XCTAssertFalse(try engine(text, archived: true).text.features.contains(.useTextSuffix))

            for layout in [bare, custom] {
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 1)
                let measured = layout.sizeThatFits(proposal)
                XCTAssertEqual(layout.sizeThatFits(.init(width: 90, height: 110)), measured)
                _ = layout.explicitAlignment(VerticalAlignment.firstTextBaseline.key, at: ViewSize(measured))
                _ = layout.explicitAlignment(VerticalAlignment.lastTextBaseline.key, at: ViewSize(measured))
                _ = layout.text.frame(in: measured, renderer: layout.renderer)
                XCTAssertEqual(layout.sizeThatFits(.zero), .zero)
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 1)
                _ = layout.sizeThatFits(.init(width: 30, height: 120))
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 2)
            }
            // ASSERTIONS textManagerMetricsCacheAndCountObserved
            let complete = custom.text.metrics(in: CGSize(width: 100, height: 120), layoutMargins: nil)
            XCTAssertEqual(complete.numberOfLines, 2)
            XCTAssertFalse(complete.hasTruncatedRanges)
            XCTAssertEqual(custom.text.textSizeCacheMetrics(in: CGSize(width: 100, height: 120)).0, 2)
            XCTAssertEqual(custom.text.metricsCacheEntryCount, 2)
            let independent = try engine(text)
            XCTAssertFalse(independent.text === bare.text)
            XCTAssertEqual(independent.text.metricsCacheEntryCount, 0)
            XCTAssertEqual(independent.sizeThatFits(proposal), bare.sizeThatFits(proposal))
            XCTAssertEqual(independent.text.metricsCacheEntryCount, 1)
            XCTAssertEqual(bare.text.metricsCacheEntryCount, 2)
        }
    }

    private func makeInputs(graph: _AGGraph, environment: EnvironmentValues = EnvironmentValues()) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment),
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: graph.makeInput(value: PreferenceKeys())),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil
        )
    }

    // ASSERTIONS textStringDrawingScaleSelectionObserved textStringDrawingScaledFontQuantizationObserved
    func testSingleLineFontFittingMeasuresResizedGlyphsWithoutChangingTheSource() throws {
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
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            func engine(_ minimum: CGFloat) throws -> StyledTextLayoutEngine {
                environment.minimumScaleFactor = minimum
                environment.lineLimit = 1
                let outputs = Text._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: Text(verbatim: "A"))),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }
            for (minimum, height, baseline, pointSize): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                (0.25, 18, 14, 15.25), (0.6, 18, 14, 15.25),
                (0.8, 22, 17, 18.5), (0.9999, 27, 21, 23)
            ] {
                let layout = try engine(minimum)
                let original = try XCTUnwrap(layout.text.resolvedText)
                let originalLines = original.unwrappedGlyphLines()
                let request = CGSize(width: 10, height: 81)
                let measured = layout.sizeThatFits(_ProposedSize(request))
                XCTAssertEqual(measured.height, height, "minimum=\(minimum)")
                XCTAssertEqual(layout.text.firstBaseline(in: request), baseline)
                XCTAssertEqual(layout.text.lastBaseline(in: request), baseline)
                let selected = try XCTUnwrap(layout.text.drawingSource(in: request))
                XCTAssertEqual(selected.uniformFont?.pointSize, pointSize)
                XCTAssertEqual(original.uniformFont?.pointSize, 23)
                let item = DisplayList.Content.TextValue(
                    view: StyledTextContentView(text: layout.text, renderer: nil), size: request,
                    frame: layout.text.frame(in: request, renderer: nil), shading: .color(.black),
                    transform: .identity, command: .closure(bounds: nil))
                let drawing = try XCTUnwrap(item.makeDrawing())
                let expected = selected.makeDrawing(in: request, layoutProperties: layout.text.layoutProperties)
                XCTAssertFalse(drawing.vectorBatches.isEmpty)
                XCTAssertEqual(drawing.vectorBatches.map { $0.path.boundingRect },
                               expected.vectorBatches.map { $0.path.boundingRect })
                XCTAssertEqual(try XCTUnwrap(item.glyphAtoms()).map(\.bounds),
                    selected.glyphAtoms(in: request, layoutProperties: layout.text.layoutProperties).map {
                        $0.bounds.offsetBy(dx: item.frame.minX + layout.text.drawingMargins.leading,
                                           dy: item.frame.minY + layout.text.drawingMargins.top)
                    })
                if pointSize != 23 {
                    XCTAssertNotEqual(drawing.vectorBatches.map { $0.path.boundingRect },
                        original.makeDrawing(in: request, layoutProperties: layout.text.layoutProperties)
                            .vectorBatches.map { $0.path.boundingRect })
                }
                XCTAssertEqual(layout.sizeThatFits(_ProposedSize(request)), measured)
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 1)
                XCTAssertEqual(original.unwrappedGlyphLines().first?.width, originalLines.first?.width)
                XCTAssertEqual(original.unwrappedGlyphLines().first?.height, originalLines.first?.height)
            }
            let heightConstrained = try engine(0.25)
            let request = CGSize(width: 50, height: 8)
            XCTAssertEqual(heightConstrained.sizeThatFits(_ProposedSize(request)), CGSize(width: 5, height: 8))
            XCTAssertEqual(heightConstrained.text.firstBaseline(in: request), 6)
            XCTAssertEqual(heightConstrained.text.drawingSource(in: request)?.uniformFont?.pointSize, 7)

            for (width, height, baseline, pointSize): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                (7, 13, 10, 10.5), (0, 6, 5, 5.75)
            ] {
                let layout = try engine(0.25)
                let request = CGSize(width: width, height: 81)
                XCTAssertEqual(layout.sizeThatFits(_ProposedSize(request)), CGSize(width: width, height: height))
                XCTAssertEqual(layout.text.firstBaseline(in: request), baseline)
                XCTAssertEqual(layout.text.lastBaseline(in: request), baseline)
                XCTAssertEqual(layout.text.drawingSource(in: request)?.uniformFont?.pointSize, pointSize)
            }

            let nearOne = try engine(0.99999999)
            let ordinary = try engine(1)
            let narrow = CGSize(width: 10, height: 81)
            let natural = try XCTUnwrap(nearOne.text.resolvedText).layoutMetrics(
                in: CGSize(width: 9_000_000, height: 9_000_000))
            XCTAssertEqual(nearOne.sizeThatFits(_ProposedSize(narrow)).width, natural.size.width)
            XCTAssertEqual(ordinary.sizeThatFits(_ProposedSize(narrow)).width, 10)
        }
    }

    // ASSERTIONS textStringDrawingMultilineFittingObserved textStringDrawingScaleSelectionObserved
    // ASSERTIONS textStringDrawingForcedClusterBreakObserved textStringDrawingTrailingWhitespaceBreakObserved
    func testMultilineFontFittingUsesHeightAndLineCountWithResizedParagraphs() throws {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fontURL = root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            func engine(_ text: String, minimum: CGFloat, limit: Int?, pointSize: CGFloat = 23)
                throws -> StyledTextLayoutEngine {
                var environment = EnvironmentValues()
                environment.font = .file(fontURL, size: pointSize)
                environment.defaultFontRenderingMode = .vector()
                environment.displayScale = 2
                environment.minimumScaleFactor = minimum
                environment.lineLimit = limit
                let outputs = Text._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: Text(verbatim: text))),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }
            for (text, limit, minimum, height, expectedHeight, first, last, pointSize):
                (String, Int?, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) in [
                ("A A A A A A", nil, 0.25, 14, 11, 9, 9, 9.5),
                ("A A A A A A", nil, 0.25, 30, 30, 12, 27, 13.25),
                ("A A A A A A", 2, 0.25, 30, 30, 12, 27, 13.25),
                ("A A A A A A", 1, 0.25, 30, 11, 9, 9, 9.5),
                ("A A A A A A", nil, 0.25, 45, 44, 17, 39, 18.75),
                ("A A A A A A", 2, 0.25, 81, 48, 19, 43, 20.25),
                ("A A A A A A", nil, 0.25, 81, 81, 21, 75, 23),
                ("A A A A A A", nil, 0.6, 30, 16, 13, 13, 13.75),
                ("A A A A A A", 2, 0.6, 30, 16, 13, 13, 13.75),
                ("A\nB", nil, 0.25, 30, 30, 12, 27, 13.25),
                ("A\nB", 2, 0.25, 30, 30, 12, 27, 13.25),
                ("A\nB", 1, 0.25, 30, 27, 21, 21, 23),
                ("\n\n", 1, 0.25, 30, 27, 21, 21, 23),
                ("\n\n", nil, 0.25, 30, 30, 8, 20, 9),
                ("\n\n", 2, 0.25, 30, 30, 8, 20, 9),
                ("\n\n", 2, 0.25, 81, 81, 21, 54, 23),
                ("A\n", nil, 0.25, 30, 30, 12, 27, 13.25),
                ("A\n", 2, 0.25, 30, 30, 12, 27, 13.25),
                ("A\n", nil, 0.25, 14, 14, 6, 13, 6),
                ("A\n", nil, 0.25, 54, 54, 21, 48, 23),
                ("AAAAAAAA", nil, 0.25, 30, 11, 9, 9, 9.5),
                ("AAAAAAAA" + String(repeating: " ", count: 504), nil, 0.25, 30, 11, 9, 9, 9.5),
                ("AAAAAAAA" + String(repeating: " ", count: 505), nil, 0.25, 30, 30, 12, 27, 13.25),
            ] {
                let layout = try engine(text, minimum: minimum, limit: limit)
                let size = CGSize(width: 50, height: height)
                let label = "\(text.debugDescription) limit=\(String(describing: limit)) minimum=\(minimum) height=\(height)"
                let measured = layout.sizeThatFits(_ProposedSize(size))
                XCTAssertEqual(measured.height, expectedHeight, label)
                XCTAssertEqual(layout.text.firstBaseline(in: size), first, label)
                XCTAssertEqual(layout.text.lastBaseline(in: size), last, label)
                let selected = try XCTUnwrap(layout.text.drawingSource(in: size))
                XCTAssertEqual(selected.uniformFont?.pointSize, pointSize, label)
                XCTAssertEqual(layout.text.resolvedText?.uniformFont?.pointSize, 23, label)
                let reference = try engine(text, minimum: 1, limit: limit, pointSize: pointSize)
                let expected = try XCTUnwrap(reference.text.resolvedText)
                XCTAssertEqual(selected.makeDrawing(in: size, layoutProperties: layout.text.layoutProperties)
                    .vectorBatches.map { $0.path.boundingRect },
                    expected.makeDrawing(in: size, layoutProperties: reference.text.layoutProperties)
                        .vectorBatches.map { $0.path.boundingRect }, label)
                XCTAssertEqual(layout.sizeThatFits(_ProposedSize(size)), measured)
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 1)
            }
            let trailing = try XCTUnwrap(engine("A\n", minimum: 1, limit: nil).text.resolvedText)
            for (height, count): (CGFloat, Int) in [(14, 1), (54, 2)] {
                let layout = trailing.makeGlyphLayout(maxWidth: 50,
                    maximumHeight: height * trailing.scaleFactor)
                XCTAssertEqual(layout.lineCount, count)
                if height == 14 {
                    XCTAssertEqual(layout.lines.count, 2)
                }
            }
            let words = try XCTUnwrap(engine("A A A A A A", minimum: 1, limit: 1).text.resolvedText)
            let truncated = words.makeGlyphLayout(maxWidth: 50, maximumHeight: 81, lineLimit: 1)
            XCTAssertFalse(truncated.forcedClusterBreak)
            XCTAssertTrue(truncated.lines.contains { $0.isTruncated })
            let word = try XCTUnwrap(engine("AAAAAAAA", minimum: 1, limit: nil).text.resolvedText)
            let wrapped = word.makeGlyphLayout(maxWidth: 50, maximumHeight: 81)
            XCTAssertTrue(wrapped.forcedClusterBreak)
            XCTAssertFalse(wrapped.lines.contains { $0.isTruncated })
        }
    }

    // ASSERTIONS textIntrinsicBackendSelectionObserved textIntrinsicZeroWidthNormalizationObserved
    // ASSERTIONS textStringDrawingEmptyMetricProducerObserved
    func testRealTextHostsMeasureEmptyBaselinesAndNarrowWidthsThroughTheirOwner() throws {
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

        try viewGraph.data.withCurrent {
            func engine<Content: View>(_ content: Content) throws -> StyledTextLayoutEngine {
                let graph = viewGraph.data.graph
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }
            for displayScale: CGFloat in [1, 2, 3] {
                environment.displayScale = displayScale
                for content in ["", "A"] {
                    for custom in [false, true] {
                        for height: CGFloat in [0, 14, 53, 54, 81] {
                            for width: CGFloat in [0, 0.01, 0.5, 1] {
                                let text = Text(verbatim: content)
                                let capture = ProxyCapture()
                                let layout = try custom
                                    ? engine(text.textRenderer(ProxyRecorder(capture: capture)))
                                    : engine(text)
                                let proposal = _ProposedSize(width: width, height: height)
                                let size = layout.sizeThatFits(proposal)
                                let label = "content=\(content.debugDescription) custom=\(custom) scale=\(displayScale) proposal=\(proposal)"
                                if proposal == .zero {
                                    XCTAssertEqual(size, .zero, label)
                                    continue
                                }
                                let expectedWidth: CGFloat = content.isEmpty ? 0
                                    : width == 0 ? (custom ? 1 / displayScale : 0)
                                    : ceil(width * displayScale) / displayScale
                                let expectedHeight: CGFloat = content.isEmpty ? 14 : 27
                                let expectedBaseline: CGFloat = content.isEmpty ? (custom ? 0 : 11) : 21
                                XCTAssertEqual(size, CGSize(width: expectedWidth, height: expectedHeight), label)
                                XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.firstTextBaseline.key,
                                    at: ViewSize(size)), expectedBaseline, label)
                                XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.lastTextBaseline.key,
                                    at: ViewSize(size)), expectedBaseline, label)
                                if displayScale == 2 {
                                    let frame = layout.text.frame(in: size, renderer: layout.renderer)
                                    XCTAssertEqual(frame, CGRect(x: 0, y: content.isEmpty ? 0 : -1,
                                        width: expectedWidth, height: expectedHeight + (content.isEmpty ? 0 : 1.5)), label)
                                }
                                if custom {
                                    let proxy = try XCTUnwrap(capture.proxy)
                                    XCTAssertEqual(proxy.sizeThatFits(ProposedViewSize(proposal)), size, label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textStringDrawingMarginPublicationObserved
    func testStringDrawingPublishesMarginsAfterRawBaselineMeasurement() throws {
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
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            func engine<Content: View>(_ content: Content, margins: EdgeInsets) throws -> StyledTextLayoutEngine {
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                let layout = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
                XCTAssertTrue(layout.text is ResolvedStyledText.StringDrawing)
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 0)
                layout.text.layoutMargins = margins
                return layout
            }
            let request = CGSize(width: 300, height: 81)
            let margins = EdgeInsets(top: 0.1, leading: 2.25, bottom: 3.5, trailing: 4.125)
            let separators = try engine(Text(verbatim: "\n\n"), margins: margins)
            XCTAssertEqual(separators.sizeThatFits(_ProposedSize(request)).width, 6.375, accuracy: 0.000001)
            XCTAssertEqual(separators.sizeThatFits(_ProposedSize(request)).height, 57.6, accuracy: 0.000001)
            XCTAssertEqual(separators.text.firstBaseline(in: request), 21)
            XCTAssertEqual(separators.text.lastBaseline(in: request), 54)
            XCTAssertEqual(separators.text.metricsCacheEntryCount, 1)

            for content in ["A", "A\n"] {
                let plain = try engine(Text(verbatim: content), margins: .init())
                let padded = try engine(Text(verbatim: content), margins: margins)
                let original = plain.sizeThatFits(_ProposedSize(request))
                let measured = padded.sizeThatFits(_ProposedSize(request))
                // Compare the margin contribution independently of font advance precision.
                XCTAssertEqual(measured.width - original.width, 6.375, accuracy: 0.000001)
                XCTAssertEqual(measured.height - original.height, 3.6, accuracy: 0.000001)
                XCTAssertEqual(padded.text.firstBaseline(in: request), 21)
                XCTAssertEqual(padded.text.lastBaseline(in: request), content == "A" ? 21 : 48)
                XCTAssertEqual(padded.text.metricsCacheEntryCount, 1)
            }
            let offset = try engine(Text(verbatim: "A").baselineOffset(0.1), margins: .init())
            XCTAssertEqual(offset.text.firstBaseline(in: request), 21)
            XCTAssertEqual(offset.text.lastBaseline(in: request), 21)

            struct Sample {
                var text: String
                var request = CGSize(width: 300, height: 81)
                var margins = EdgeInsets(top: 0.1, leading: 2.25, bottom: 3.5, trailing: 4.125)
                var spacing: CGFloat = 0
                var offset: CGFloat = 0
                var size: CGSize
                var first: CGFloat
                var last: CGFloat
            }
            let negative = EdgeInsets(top: -0.2, leading: 0.3, bottom: -0.4, trailing: 0.5)
            let fractional = EdgeInsets(top: 0.2, leading: 0.3, bottom: 0.4, trailing: 0.5)
            let samples: [Sample] = [
                .init(text: "", size: .init(width: 6.375, height: 17.6), first: 11, last: 11),
                .init(text: "", margins: negative, size: .init(width: 0.8, height: 13.4), first: 11, last: 11),
                .init(text: "A", request: .init(width: 7.375, height: 81),
                      size: .init(width: 7.375, height: 30.6), first: 21, last: 21),
                .init(text: "A", request: .init(width: 6.375, height: 14),
                      size: .init(width: 6.375, height: 30.6), first: 21, last: 21),
                .init(text: "A", request: .init(width: 7.375, height: 81), margins: negative,
                      size: .init(width: 7.8, height: 26.4), first: 21, last: 21),
                .init(text: "\n", size: .init(width: 6.375, height: 57.6), first: 27, last: 27),
                .init(text: "\n", margins: negative, size: .init(width: 0.8, height: 53.4), first: 27, last: 27),
                .init(text: "\n\n", request: .init(width: 300, height: 54),
                      size: .init(width: 7.375, height: 30.6), first: 21, last: 21),
                .init(text: "\n\n", request: .init(width: 300, height: 54), margins: negative,
                      size: .init(width: 0.8, height: 53.4), first: 21, last: 54),
                .init(text: "\n\n\n", size: .init(width: 7.375, height: 57.6), first: 21, last: 54),
                .init(text: "\n\n\n", margins: negative, size: .init(width: 0.8, height: 80.4), first: 21, last: 81),
                .init(text: "A\n", request: .init(width: 7.375, height: 81),
                      size: .init(width: 7.375, height: 57.6), first: 21, last: 48),
                .init(text: "A\n", request: .init(width: 7.375, height: 81), margins: negative,
                      size: .init(width: 7.8, height: 53.4), first: 21, last: 48),
                .init(text: "\n", margins: fractional, spacing: 0.1,
                      size: .init(width: 0.8, height: 55.1), first: 27.5, last: 27.5),
                .init(text: "\n\n", margins: fractional, spacing: 0.1,
                      size: .init(width: 0.8, height: 55.1), first: 21, last: 54.5),
                .init(text: "A", request: .init(width: 7.375, height: 81), offset: 0.1,
                      size: .init(width: 7.375, height: 31.1), first: 21, last: 21),
                .init(text: "A", request: .init(width: 7.375, height: 81), offset: 0.2,
                      size: .init(width: 7.375, height: 31.1), first: 21.5, last: 21.5),
                .init(text: "A", request: .init(width: 7.375, height: 81), offset: 4.25,
                      size: .init(width: 7.375, height: 35.1), first: 25.5, last: 25.5)
            ]
            for sample in samples {
                let text = Text(verbatim: sample.text).baselineOffset(sample.offset).lineSpacing(sample.spacing)
                let layout = try engine(text, margins: sample.margins)
                let measured = layout.sizeThatFits(_ProposedSize(sample.request))
                let label = "\(sample.text.debugDescription) request=\(sample.request) margins=\(sample.margins) spacing=\(sample.spacing) offset=\(sample.offset)"
                XCTAssertEqual(measured.width, sample.size.width, accuracy: 0.000001, label)
                XCTAssertEqual(measured.height, sample.size.height, accuracy: 0.000001, label)
                XCTAssertEqual(layout.text.firstBaseline(in: sample.request), sample.first, accuracy: 0.000001, label)
                XCTAssertEqual(layout.text.lastBaseline(in: sample.request), sample.last, accuracy: 0.000001, label)
                XCTAssertEqual(layout.text.metricsCacheEntryCount, 1, label)
            }
        }
    }

    // ASSERTIONS textStringDrawingLegacySeparatorProducerObserved textStringDrawingLegacyReflowObserved
    // ASSERTIONS textStringDrawingUsedRectFloorObserved textStringDrawingLegacyBaselinePublicationObserved
    // ASSERTIONS textStringDrawingTrailingCoreTextProducerObserved
    // ASSERTIONS textStringDrawingLegacyPrefixRetryObserved textParagraphClippedContinuationOriginObserved
    // ASSERTIONS textStringDrawingFragmentRoundingObserved
    func testRealTextHostsMeasureSeparatorFragmentsThroughTheirOwner() throws {
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

        try viewGraph.data.withCurrent {
            func engine<Content: View>(_ content: Content) throws -> StyledTextLayoutEngine {
                let graph = viewGraph.data.graph
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }
            let heights: [CGFloat?] = [0, 14, 53, 54, 81, nil]
            var controls: [(String, CGFloat, [[CGFloat]], [[CGFloat]])] = [
                ("\n", 300,
                 [[0, 0, 0, 0], [0, 14, 14, 14], [0, 27, 27, 27],
                  [0, 54, 27, 27], [0, 54, 27, 27], [0, 54, 27, 27]],
                 Array(repeating: [0, 28, 21, 25], count: 6)),
                ("\n\n", 300,
                 [[1, 27, 21, 21], [1, 27, 21, 21], [1, 27, 21, 21],
                  [0, 54, 21, 54], [0, 81, 21, 54], [0, 81, 21, 54]],
                 [[0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21],
                  [0, 55, 21, 52], [0, 55, 21, 52], [0, 55, 21, 52]]),
                ("\n\n\n", 300,
                 [[1, 27, 21, 21], [1, 27, 21, 21], [1, 27, 21, 21],
                  [1, 54, 21, 54], [0, 81, 21, 81], [0, 108, 21, 81]],
                 [[0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21],
                  [0, 54, 21, 48], [0, 82, 21, 79], [0, 82, 21, 79]]),
                ("\r\n", 300,
                 [[0, 0, 0, 0], [0, 14, 14, 14], [0, 27, 27, 27],
                  [0, 54, 27, 27], [0, 54, 27, 27], [0, 54, 27, 27]],
                 [[0, 0, 0, 0], [0, 27, 21, 21], [0, 27, 21, 21],
                  [0, 54, 21, 48], [0, 54, 21, 48], [0, 54, 21, 48]]),
                ("A\n", 1,
                 [[1, 27, 21, 21], [1, 27, 21, 21], [1, 27, 21, 21],
                  [1, 54, 21, 48], [1, 54, 21, 48], [1, 54, 21, 48]],
                 [[1, 27, 21, 21], [1, 27, 21, 21], [1, 27, 21, 21],
                  [1, 54, 21, 48], [1, 54, 21, 48], [1, 54, 21, 48]])
            ]
            for separator in ["\r", "\u{2028}", "\u{2029}"] {
                controls.append((separator, 300, controls[0].2, controls[0].3))
            }
            for (content, width, bareMetrics, customMetrics) in controls {
                for custom in [false, true] {
                    for (index, height) in heights.enumerated() {
                        let text = Text(verbatim: content)
                        let capture = ProxyCapture()
                        let layout = try custom
                            ? engine(text.textRenderer(ProxyRecorder(capture: capture)))
                            : engine(text)
                        let proposal = _ProposedSize(width: width, height: height)
                        let size = layout.sizeThatFits(proposal)
                        let expected = custom ? customMetrics[index] : bareMetrics[index]
                        let label = "content=\(content.debugDescription) custom=\(custom) proposal=\(proposal)"
                        XCTAssertEqual(size, CGSize(width: expected[0], height: expected[1]), label)
                        XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.firstTextBaseline.key,
                            at: ViewSize(size)), expected[2], label)
                        XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.lastTextBaseline.key,
                            at: ViewSize(size)), expected[3], label)
                        // Non-ASCII separators have separate scalar-dependent drawing outsets.
                        if content.unicodeScalars.allSatisfy(\.isASCII) {
                            XCTAssertEqual(layout.text.frame(in: size, renderer: layout.renderer),
                                CGRect(x: 0, y: -1, width: expected[0], height: expected[1] + 1.5), label)
                        }
                        XCTAssertEqual(layout.text.metricsCacheEntryCount, 1, label)
                        if custom {
                            let proxy = try XCTUnwrap(capture.proxy)
                            XCTAssertEqual(proxy.sizeThatFits(ProposedViewSize(proposal)), size, label)
                            if content == "A\n" {
                                let source = try XCTUnwrap(layout.text.resolvedText)
                                let lines = source.makeLayout(in: size, layoutDirection: .leftToRight,
                                    layoutProperties: layout.text.layoutProperties)
                                XCTAssertEqual(lines.count, 2, label)
                                let origins = lines.map(\.origin.y)
                                XCTAssertEqual(origins[1] - origins[0], expected[1] == 27 ? 0 : 27, label)
                            }
                        }
                    }
                }
            }
            for (height, measured, baseline): (CGFloat, CGFloat, CGFloat) in [
                (0.01, 0.5, 0), (0.49, 0.5, 0.5), (14.1, 14.5, 14), (26.9, 27, 27)
            ] {
                let layout = try engine(Text(verbatim: "\n"))
                let size = layout.sizeThatFits(.init(width: 300, height: height))
                XCTAssertEqual(size, CGSize(width: 0, height: measured))
                XCTAssertEqual(layout.text.firstBaseline(in: size), baseline)
                XCTAssertEqual(layout.text.lastBaseline(in: size), baseline)
            }
            for limit in [1, 2] {
                let layout = try engine(Text(verbatim: "\n\n").lineLimit(limit))
                let size = layout.sizeThatFits(.init(width: 300, height: 81))
                XCTAssertEqual(size, limit == 1 ? CGSize(width: 1, height: 27) : CGSize(width: 0, height: 81))
                XCTAssertEqual(layout.text.firstBaseline(in: size), 21)
                XCTAssertEqual(layout.text.lastBaseline(in: size), limit == 1 ? 21 : 54)
            }
            for (pointSize, height, baseline): (CGFloat, CGFloat, CGFloat) in [
                (14, 16, 13), (23, 27, 21), (37, 43, 34)
            ] {
                environment.font = .file(root.appendingPathComponent(
                    "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: pointSize)
                for scale: CGFloat in [1, 2, 3] {
                    environment.displayScale = scale
                    let layout = try engine(Text(verbatim: "\n\n"))
                    let size = layout.sizeThatFits(.init(width: 300, height: 0))
                    XCTAssertEqual(size, CGSize(width: 1, height: height))
                    XCTAssertEqual(layout.text.firstBaseline(in: size), baseline)
                    XCTAssertEqual(layout.text.lastBaseline(in: size), baseline)
                }
            }
        }
    }

    // ASSERTIONS textStringDrawingSeparatorSpacingAdmissionObserved
    // ASSERTIONS textStringDrawingSeparatorRetryRangeObserved
    // ASSERTIONS textStringDrawingStoredUsageInvalidationObserved
    func testSeparatorSpacingRetainsUsageThroughRangeRetry() throws {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        let fontURL = root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        environment.font = .file(fontURL, size: 23)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        try viewGraph.data.withCurrent {
            func engine<Content: View>(_ content: Content) throws -> StyledTextLayoutEngine {
                let graph = viewGraph.data.graph
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)),
                    inputs: makeInputs(graph: graph, environment: environment))
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
            }
            let heights: [CGFloat?] = [0, 14, 33, 53, 54, 66, 81, nil]
            let controls: [(String, [[CGFloat]], [[CGFloat]])] = [
                ("\n", [[0, 0, 0, 0], [0, 14, 14, 14], [0, 33, 33, 33], [0, 33, 33, 33],
                         [0, 33, 33, 33], [0, 60, 33, 33], [0, 60, 33, 33], [0, 60, 33, 33]],
                 Array(repeating: [0, 28, 21, 25], count: 8)),
                ("\n\n", [[1, 27, 21, 21], [1, 27, 21, 21], [1, 33, 21, 21], [1, 33, 21, 21],
                           [1, 54, 21, 54], [0, 66, 21, 66], [0, 66, 21, 66], [0, 93, 21, 66]],
                 [[0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21],
                  [0, 60, 21, 52], [0, 60, 21, 52], [0, 60, 21, 52], [0, 60, 21, 52]]),
                ("\n\n\n", [[1, 27, 21, 21], [1, 27, 21, 21], [1, 33, 21, 21], [1, 33, 21, 21],
                             [1, 54, 21, 54], [1, 60, 21, 60], [1, 60, 21, 60], [0, 126, 21, 99]],
                 [[0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21], [0, 27, 21, 21],
                  [0, 60, 21, 48], [0, 60, 21, 48], [0, 60, 21, 48], [0, 93, 21, 85]])
            ]
            for (content, bare, customMetrics) in controls {
                for custom in [false, true] {
                    for (index, height) in heights.enumerated() {
                        let text = Text(verbatim: content).lineSpacing(6)
                        let capture = ProxyCapture()
                        let layout = try custom ? engine(text.textRenderer(ProxyRecorder(capture: capture))) : engine(text)
                        let proposal = _ProposedSize(width: 300, height: height)
                        let expected = custom ? customMetrics[index] : bare[index]
                        let label = "content=\(content.debugDescription) custom=\(custom) height=\(String(describing: height))"
                        let size = layout.sizeThatFits(proposal)
                        XCTAssertEqual(size, CGSize(width: expected[0], height: expected[1]), label)
                        XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.firstTextBaseline.key, at: ViewSize(size)), expected[2], label)
                        XCTAssertEqual(layout.explicitAlignment(VerticalAlignment.lastTextBaseline.key, at: ViewSize(size)), expected[3], label)
                        XCTAssertEqual(layout.text.frame(in: size, renderer: layout.renderer),
                            CGRect(x: 0, y: -1, width: expected[0], height: expected[1] + 1.5), label)
                        XCTAssertEqual(layout.text.metricsCacheEntryCount, 1, label)
                        if custom {
                            XCTAssertEqual(try XCTUnwrap(capture.proxy).sizeThatFits(ProposedViewSize(proposal)), size, label)
                        }
                    }
                }
            }
            let retries: [(Int, CGFloat, CGFloat, CGFloat?, Int?, [CGFloat])] = [
                (3, 23, 6, 87, nil, [1, 87, 21, 60]),
                (4, 23, 6, 99, nil, [1, 93, 21, 93]),
                (4, 23, 6, nil, 2, [1, 87, 21, 60]),
                (3, 14, 20, 72, nil, [1, 68, 13, 52]),
                (2, 23, 20, 81, nil, [0, 74, 21, 74]),
                (2, 14, 20, 36, nil, [1, 36, 13, 32]),
                (3, 37, 0.5, nil, 2, [1, 129.5, 34, 86.5]),
                (4, 23, 0, 81, nil, [1, 81, 21, 81])
            ]
            for (count, pointSize, spacing, height, limit, expected) in retries {
                environment.font = .file(fontURL, size: pointSize)
                let content = String(repeating: "\n", count: count)
                let layout = try engine(Text(verbatim: content).lineSpacing(spacing).lineLimit(limit))
                let size = layout.sizeThatFits(.init(width: 300, height: height))
                let label = "count=\(count) font=\(pointSize) spacing=\(spacing) height=\(String(describing: height)) limit=\(String(describing: limit))"
                XCTAssertEqual(size, CGSize(width: expected[0], height: expected[1]), label)
                XCTAssertEqual(layout.text.firstBaseline(in: size), expected[2], label)
                XCTAssertEqual(layout.text.lastBaseline(in: size), expected[3], label)
            }
        }
    }

    private func resolve(limit: Int?, spacing: CGFloat) throws -> ResolvedStyledText {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment.lineLimit = limit
        environment.lineSpacing = spacing
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let source = try XCTUnwrap(Text(verbatim: "Alpha\nBeta\nGamma\nDelta")._resolve(context:
            GraphTextResolutionContext(environment: environment, sceneResources: scene),
            referenceDate: Date(timeIntervalSince1970: 0)))
        return ResolvedStyledText.TextLayoutManager(layoutProperties: TextLayoutProperties(from: environment), resolvedText: source)
    }

    private func box<Renderer: TextRenderer>(_ renderer: Renderer) throws -> TextRendererBoxBase {
        let graph = _AGGraph()
        return try _AGGraph.withCurrent(graph) {
            let modifier = _TextRendererViewModifier(renderer: renderer)
            let attribute = graph.makeInput(value: modifier)
            var inputs = _ViewInputs(
                base: _GraphInputs(
                    time: graph.makeInput(value: Time(seconds: 0)),
                    phase: graph.makeInput(value: _GraphInputs.Phase()),
                    environment: graph.makeInput(value: EnvironmentValues()),
                    transaction: graph.makeInput(value: Transaction())
                ),
                customInputs: PropertyList(),
                preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: graph.makeInput(value: PreferenceKeys())),
                transform: graph.makeInput(value: ViewTransform()),
                position: graph.makeInput(value: CGPoint.zero),
                containerPosition: graph.makeInput(value: CGPoint.zero),
                size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
                safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil
            )
            type(of: modifier)._makeViewInputs(modifier: _GraphValue(_attribute: attribute), inputs: &inputs)
            return try XCTUnwrap(inputs[TextRendererInput.self].value)
        }
    }

    // ASSERTIONS textProxyRetainedLayoutPropertiesObserved
    func testInheritedLineLimitAndSpacingReachRendererSizing() throws {
        let controls: [(Int?, CGFloat, CGFloat, Int)] = [
            (nil, 0, 60, 4), (nil, 6, 78, 4), (1, 0, 15, 1),
            (1, 6, 15, 1), (2, 0, 30, 2), (2, 6, 36, 2)
        ]
        for (limit, spacing, height, count) in controls {
            let styled = try resolve(limit: limit, spacing: spacing)
            let capture = ProxyCapture()
            let renderer = try box(ProxyRecorder(capture: capture))
            let engine = StyledTextLayoutEngine(text: styled, renderer: renderer)
            for proposal in [_ProposedSize.unspecified, _ProposedSize(width: 100, height: 120)] {
                let size = engine.sizeThatFits(proposal)
                XCTAssertEqual(size.height, height, "limit=\(String(describing: limit)) spacing=\(spacing)")
                XCTAssertEqual(size, styled.sizeThatFits(proposal))
            }
            let proxy = try XCTUnwrap(capture.proxy)
            let copied = proxy
            XCTAssertEqual(copied.sizeThatFits(.init(width: 100, height: 120)).height, height)
            let source = try XCTUnwrap(styled.resolvedText)
            let layout = source.makeLayout(in: .init(width: 100, height: 120),
                layoutDirection: .leftToRight, layoutProperties: styled.layoutProperties)
            XCTAssertEqual(layout.count, count)
        }
    }

    // ASSERTIONS textProxyRetainedOwnerAndCacheObserved
    func testCopiedProxyRetainsTheStyledOwnerAndReusesItsMetrics() throws {
        let capture = ProxyCapture()
        weak var owner: ResolvedStyledText?
        do {
            let styled = try resolve(limit: 2, spacing: 6)
            owner = styled
            let renderer = try box(ProxyRecorder(capture: capture))
            let engine = StyledTextLayoutEngine(text: styled, renderer: renderer)
            XCTAssertEqual(engine.sizeThatFits(.init(width: 100, height: 120)).height, 36)
            XCTAssertEqual(styled.metricsCacheEntryCount, 1)
        }
        let proxy = try XCTUnwrap(capture.proxy)
        capture.proxy = nil
        let styled = try XCTUnwrap(owner)
        let copied = proxy
        XCTAssertEqual(Mirror(reflecting: copied).children.map { $0.label ?? "_" }, ["text"])
        XCTAssertEqual(copied.sizeThatFits(.init(width: 100, height: 120)).height, 36)
        XCTAssertEqual(copied.sizeThatFits(.init(width: 90, height: 110)).height, 36)
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
        XCTAssertEqual(copied.sizeThatFits(.zero), .zero)
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
        XCTAssertEqual(copied.sizeThatFits(.init(width: 30, height: 120)).height, 36)
        XCTAssertEqual(styled.metricsCacheEntryCount, 2)
    }

    // ASSERTIONS textProxyRetainedLayoutPropertiesObserved
    func testRendererFrameAndDefaultSizingUseTheSameStyledMeasurement() throws {
        let styled = try resolve(limit: 2, spacing: 6)
        let capture = ProxyCapture()
        let renderer = try box(ProxyRecorder(capture: capture))
        let size = CGSize(width: 100, height: 120)
        let frame = styled.frame(in: size, renderer: renderer)
        XCTAssertEqual(capture.measurements.last?.height, 36)
        XCTAssertEqual(frame, styled.frame(in: size, renderer: nil))
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
        let defaults = try box(DefaultProxyRenderer())
        let engine = StyledTextLayoutEngine(text: styled, renderer: defaults)
        XCTAssertEqual(engine.sizeThatFits(.init(size)).height, 36)
        XCTAssertEqual(engine.sizeThatFits(.init(width: 100, height: 0)).height, 15)
        XCTAssertEqual(styled.metricsCacheEntryCount, 2)
    }
}

private final class ProxyCapture {
    var proxy: TextProxy?
    var measurements: [CGSize] = []
}

private struct ProxyRecorder: TextRenderer {
    let capture: ProxyCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        capture.proxy = text
        let size = text.sizeThatFits(proposal)
        capture.measurements.append(size)
        return size
    }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
}

private struct DefaultProxyRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
}

private final class ProxyTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
