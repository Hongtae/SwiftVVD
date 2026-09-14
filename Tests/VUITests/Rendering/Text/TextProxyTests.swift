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
