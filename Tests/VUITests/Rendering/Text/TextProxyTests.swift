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
        return ResolvedStyledText(layoutProperties: TextLayoutProperties(from: environment), resolvedText: source)
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
            return try XCTUnwrap(inputs[TextRendererInput.self]).value
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
