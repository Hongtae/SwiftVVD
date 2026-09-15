import Foundation
import XCTest
import VVD
@testable import VUI

final class TextDrawingMarginTests: XCTestCase {
    // ASSERTIONS textProxyRetainedLayoutPropertiesObserved
    // ASSERTIONS textProxyRetainedOwnerAndCacheObserved
    func testRendererBoundsRetainStyledSizingThroughDrawingAndReplay() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let controls: [(Int?, CGFloat, CGFloat, Int)] = [
            (nil, 0, 60, 4), (nil, 6, 78, 4), (1, 0, 15, 1),
            (1, 6, 15, 1), (2, 0, 30, 2), (2, 6, 36, 2)
        ]
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for (limit, spacing, height, count) in controls {
                    var environment = EnvironmentValues()
                    environment.font = .file(file, size: 13)
                    environment.defaultFontRenderingMode = mode
                    environment._contentScaleFactor = scale
                    environment.displayScale = 2
                    environment.lineLimit = limit
                    environment.lineSpacing = spacing
                    environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
                    var source = try resolve(Text(verbatim: "Alpha\nBeta\nGamma\nDelta"), environment: environment)
                    source.shading = .color(.black)
                    let properties = TextLayoutProperties(from: environment)
                    let styled = ResolvedStyledText.StringDrawing(layoutProperties: properties, resolvedText: source)
                    let renderer = MarginRenderer(environment: environment, operation: .line)
                    renderer.recordsProxy = true
                    let size = StyledTextLayoutEngine(text: styled, renderer: renderer)
                        .sizeThatFits(.init(width: 100, height: 120))
                    XCTAssertEqual(size.height, height)
                    let item = DisplayList.Content.TextValue(
                        view: StyledTextContentView(text: styled, renderer: renderer), size: size,
                        frame: styled.frame(in: size, renderer: renderer), shading: source.shading,
                        transform: .identity, command: .closure(bounds: nil))
                    let expected = try render(device: device, environment: environment) {
                        $0.draw(source, in: CGRect(origin: .zero, size: size), shading: source.shading, layoutProperties: properties)
                    }
                    XCTAssertTrue(expected.contains { $0 != 0 })
                    for record in [false, true] {
                        let actual = try render(device: device, environment: environment) { context in
                            if record {
                                let recording = context.recordingContext(size: CGSize(width: 128, height: 128))
                                item.draw(in: recording)
                                recording.recording!.draw(in: context)
                            } else { item.draw(in: context) }
                        }
                        XCTAssertEqual(renderer.proxySize?.height, height)
                        XCTAssertEqual(renderer.layoutLineCount, count)
                        XCTAssertEqual(actual, expected, "\(mode) scale=\(scale) limit=\(String(describing: limit)) spacing=\(spacing) replay=\(record)")
                    }
                }
            }
        }
    }

    // ASSERTIONS textParagraphAdmissionBudgetObserved
    // ASSERTIONS textFinalExtraFragmentOverlapObserved
    func testConstrainedParagraphsPreservePreparedAndRendererPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let controls: [(String, CGFloat, Int?, CGFloat)] = [
            ("A\n", 14, nil, 0), ("A\n\n", 56, 1, 0), ("A\n\n", 56, 2, 0),
            ("\r\n\r\n", 56, 1, 0), ("A\n\r\n", 54, nil, 7), ("A\u{2028}\u{2028}", 54, nil, 7)
        ]
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for (string, height, limit, spacing) in controls {
                    var environment = EnvironmentValues()
                    environment.font = .file(file, size: 23)
                    environment.defaultFontRenderingMode = mode
                    environment._contentScaleFactor = scale
                    environment.displayScale = 2
                    environment.lineSpacing = spacing
                    environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
                    var source = try resolve(Text(verbatim: string), environment: environment)
                    source.shading = .color(.black)
                    var properties = TextLayoutProperties()
                    properties.lineLimit = limit
                    let rect = CGRect(x: 0, y: 0, width: 100, height: height)
                    let expected = try render(device: device, environment: environment) {
                        $0.draw(source, in: rect, shading: source.shading, layoutProperties: properties)
                    }
                    XCTAssertEqual(expected.contains { $0 != 0 }, string.hasPrefix("A"))
                    let prepared = source.makeDrawing(in: rect.size, layoutProperties: properties)
                    let cached = try render(device: device, environment: environment) {
                        $0.draw(prepared, in: rect, shading: source.shading, clipBounds: false)
                    }
                    let layout = source.makeLayout(in: rect.size, layoutDirection: .leftToRight, layoutProperties: properties)
                    let renderer = MarginRenderer(environment: environment, operation: .line)
                    let rendered = try render(device: device, environment: environment) { renderer.draw(layout: layout, in: &$0) }
                    XCTAssertEqual(cached, expected, "Prepared \(mode) \(scale) \(string.debugDescription)")
                    XCTAssertEqual(rendered, expected, "Renderer \(mode) \(scale) \(string.debugDescription)")
                }
            }
        }
    }

    // ASSERTIONS textEmptyFragmentDefaultFontObserved
    // ASSERTIONS textEmptyFragmentSeparatorRoutingObserved
    // ASSERTIONS textEmptyFragmentConsumerBoundariesObserved
    func testEmptyFragmentPlacementPreservesPreparedAndRendererPixels() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for leading: VUI.Font.Leading in [.tight, .loose] {
                    for string in ["A\n\n", "A\r\nA\r\n", "A\u{2028}A\u{2028}", "A\u{b}B"] {
                        var environment = EnvironmentValues()
                        environment.font = .body.leading(leading)
                        environment.defaultFontRenderingMode = mode
                        environment._contentScaleFactor = scale
                        environment.displayScale = 2
                        environment.lineSpacing = 7
                        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
                        let source = try resolve(Text(verbatim: string), environment: environment)
                        let item = try value(ResolvedStyledText.StringDrawing(resolvedText: source))
                        let expected = try render(device: device, environment: environment) {
                            $0.draw(source, in: CGRect(origin: .zero, size: item.size))
                        }
                        XCTAssertTrue(expected.contains { $0 != 0 })
                        let prepared = try XCTUnwrap(item.makeDrawing())
                        let immediate = try render(device: device, environment: environment) { item.draw(in: $0) }
                        let cached = try render(device: device, environment: environment) { item.draw(prepared, in: $0) }
                        let renderer = MarginRenderer(environment: environment, operation: .line)
                        let custom = try value(ResolvedStyledText.StringDrawing(resolvedText: source), renderer: renderer)
                        let rendered = try render(device: device, environment: environment) { custom.draw(in: $0) }
                        XCTAssertEqual(immediate, expected, "Immediate \(mode) \(leading) \(scale) \(string.debugDescription)")
                        XCTAssertEqual(cached, expected, "Prepared \(mode) \(leading) \(scale) \(string.debugDescription)")
                        XCTAssertEqual(rendered, expected, "Renderer \(mode) \(leading) \(scale) \(string.debugDescription)")
                    }
                }
            }
        }
    }

    // ASSERTIONS fontStyleLinePlacementObserved
    // ASSERTIONS textComponentFontLanguageAndRatioObserved
    // ASSERTIONS textDrawingFrameCompensationObserved
    func testStyleLeadingPreservesPreparedAndRendererPixelsInBothModes() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for leading: VUI.Font.Leading in [.standard, .tight, .loose] {
                    for language in ["en", "ur"] {
                        var environment = EnvironmentValues()
                        environment.font = .body.leading(leading)
                        environment.defaultFontRenderingMode = mode
                        environment._contentScaleFactor = scale
                        environment.displayScale = 2
                        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: language))
                        let source = try resolve(Text(verbatim: "Ågj\nHg\nA한"), environment: environment)
                        let item = try value(ResolvedStyledText.StringDrawing(resolvedText: source))
                        let expected = try render(device: device, environment: environment) {
                            $0.draw(source, in: CGRect(origin: .zero, size: item.size))
                        }
                        XCTAssertTrue(expected.contains { $0 != 0 })
                        let prepared = try XCTUnwrap(item.makeDrawing())
                        let immediate = try render(device: device, environment: environment) { item.draw(in: $0) }
                        let cached = try render(device: device, environment: environment) { item.draw(prepared, in: $0) }
                        let renderer = MarginRenderer(environment: environment, operation: .line)
                        let custom = try value(ResolvedStyledText.StringDrawing(resolvedText: source), renderer: renderer)
                        let rendered = try render(device: device, environment: environment) { custom.draw(in: $0) }
                        XCTAssertTrue(immediate == expected, "Immediate \(mode) \(leading) \(language) \(scale)")
                        XCTAssertTrue(cached == expected, "Prepared \(mode) \(leading) \(language) \(scale)")
                        XCTAssertTrue(rendered == expected, "Renderer \(mode) \(leading) \(language) \(scale)")
                    }
                }
            }
        }
    }

    private func render(device: GraphicsDeviceContext, environment: EnvironmentValues,
                        content: (inout GraphicsContext) throws -> Void) throws -> [UInt8] {
        let scale = environment._contentScaleFactor
        let extent = CGSize(width: 128, height: 128) * scale
        let queue = try XCTUnwrap(device.renderQueue())
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
            contentScaleFactor: scale, resolution: extent, commandBuffer: buffer))
        context.clear(with: .clear)
        context.translateBy(x: 8, y: 8)
        try content(&context)
        let done = expectation(description: "Text drawing completion")
        buffer.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(buffer.commit())
        wait(for: [done], timeout: 5)
        let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: Int(extent.width * extent.height) * 4))
    }

    private func resolve(_ text: Text, environment: EnvironmentValues) throws -> GraphicsContext.ResolvedText {
        try XCTUnwrap(text._resolve(context: GraphTextResolutionContext(
            environment: environment, sceneResources: SceneResources()), referenceDate: Date(timeIntervalSince1970: 0)))
    }

    private func value(_ text: ResolvedStyledText, renderer: TextRendererBoxBase? = nil) throws -> DisplayList.Content.TextValue {
        let source = try XCTUnwrap(text.resolvedText)
        let size = source.measure()
        return DisplayList.Content.TextValue(
            view: StyledTextContentView(text: text, renderer: renderer), size: size,
            frame: text.frame(in: size, renderer: renderer), shading: .color(.black),
            transform: .identity, command: .closure(bounds: nil))
    }

    // ASSERTIONS textStringDrawingScaleSelectionObserved textStringDrawingScaledFontQuantizationObserved
    // ASSERTIONS textStringDrawingMultilineFittingObserved
    func testFittedTextUsesTheSelectedFontForPreparedDrawingAndReplayInBothModes() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for scale: CGFloat in [1, 2] {
                for (text, limit, minimum, request, selectedSize): (String, Int?, CGFloat, CGSize, CGFloat) in [
                    ("A", 1, 0.25, CGSize(width: 10, height: 81), 15.25),
                    ("A", 1, 0.8, CGSize(width: 10, height: 81), 18.5),
                    ("A A A A A A", nil, 0.25, CGSize(width: 50, height: 30), 13.25),
                    ("A A A A A A", 2, 0.25, CGSize(width: 50, height: 81), 20.25),
                    ("A\nB", nil, 0.25, CGSize(width: 50, height: 30), 13.25),
                    ("A\n", nil, 0.25, CGSize(width: 50, height: 30), 13.25),
                ] {
                    var environment = EnvironmentValues()
                    environment.font = .file(file, size: 23)
                    environment.defaultFontRenderingMode = mode
                    environment._contentScaleFactor = scale
                    environment.displayScale = 2
                    environment.lineLimit = limit
                    environment.minimumScaleFactor = minimum
                    let source = try resolve(Text(verbatim: text), environment: environment)
                    let owner = ResolvedStyledText.StringDrawing(
                        layoutProperties: TextLayoutProperties(from: environment), resolvedText: source)
                    let item = DisplayList.Content.TextValue(
                        view: StyledTextContentView(text: owner, renderer: nil), size: request,
                        frame: owner.frame(in: request, renderer: nil), shading: .color(.black),
                        transform: .identity, command: .closure(bounds: nil))
                    XCTAssertEqual(owner.drawingSource(in: request)?.uniformFont?.pointSize, selectedSize)
                    var referenceEnvironment = environment
                    referenceEnvironment.font = .file(file, size: selectedSize)
                    referenceEnvironment.minimumScaleFactor = 1
                    let reference = try resolve(Text(verbatim: text), environment: referenceEnvironment)
                    let referenceDrawing = reference.makeDrawing(in: request,
                        layoutProperties: TextLayoutProperties(from: referenceEnvironment),
                        origin: CGPoint(x: owner.drawingMargins.leading, y: owner.drawingMargins.top))
                    let expected = try render(device: device, environment: environment) {
                        $0.draw(referenceDrawing, in: item.frame, shading: .color(.black))
                    }
                    XCTAssertTrue(expected.contains { $0 != 0 })
                    let prepared = try XCTUnwrap(item.makeDrawing())
                    for operation in 0..<3 {
                        let actual = try render(device: device, environment: environment) { context in
                            if operation == 0 {
                                item.draw(in: context)
                            } else if operation == 1 {
                                item.draw(prepared, in: context)
                            } else {
                                let recording = context.recordingContext(size: CGSize(width: 128, height: 128))
                                item.draw(in: recording)
                                recording.recording!.draw(in: context)
                            }
                        }
                        XCTAssertTrue(actual == expected,
                            "\(mode) scale=\(scale) minimum=\(minimum) operation=\(operation)")
                    }
                    XCTAssertEqual(source.uniformFont?.pointSize, 23)
                }
            }
        }
    }

    // ASSERTIONS textDrawingFrameCompensationObserved
    // ASSERTIONS textDrawingRendererLocalContextObserved
    // ASSERTIONS textDrawingOutsetSelectionGatesObserved
    // ASSERTIONS textLanguageAwareOutsetBackendObserved
    func testBitmapAndVectorOriginsPreserveCanvasAndRendererPixelsOnGPU() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for pointSize: CGFloat in [13, 15.625, 23] {
                for (displayScale, renderScale): (CGFloat, CGFloat) in [(1, 2), (2, 1), (2, 2)] {
                    var environment = EnvironmentValues()
                    environment.font = .system(size: pointSize)
                    environment.defaultFontRenderingMode = mode
                    environment.displayScale = displayScale
                    environment._contentScaleFactor = renderScale
                    for string in ["Hg\nHg", "Ågj\nHg"] {
                        let source = try resolve(Text(verbatim: string), environment: environment)
                        let styled = ResolvedStyledText.StringDrawing(resolvedText: source)
                        let plain = try value(styled)
                        let expected = try render(device: device, environment: environment) {
                            $0.draw(source, in: CGRect(origin: .zero, size: plain.size))
                        }
                        XCTAssertTrue(expected.contains { $0 != 0 })
                        let prepared = try XCTUnwrap(plain.makeDrawing())
                        for cached in [false, true] {
                            let actual = try render(device: device, environment: environment) {
                                if cached { plain.draw(prepared, in: $0) } else { plain.draw(in: $0) }
                            }
                            XCTAssertTrue(actual == expected, "Prepared text moved at size \(pointSize), display \(displayScale), render \(renderScale)")
                        }
                        var shifted: [UInt8]?
                        for operation in MarginRenderer.Operation.allCases {
                            let renderer = MarginRenderer(environment: environment, operation: operation)
                            let item = try value(styled, renderer: renderer)
                            let actual = try render(device: device, environment: environment) { context in
                                let original = context.transform
                                item.draw(in: context)
                                XCTAssertEqual(context.transform, original)
                            }
                            XCTAssertEqual(renderer.transform, .identity)
                            let extent = CGFloat(Float.greatestFiniteMagnitude)
                            XCTAssertEqual(renderer.clipBounds, CGRect(x: -extent / 2, y: -extent / 2, width: extent, height: extent))
                            XCTAssertEqual(renderer.opacity, 1)
                            XCTAssertEqual(renderer.origin?.y, source.firstBaseline(in: plain.size) + styled.drawingMargins.top)
                            switch operation {
                            case .line, .run, .slice:
                                let differences = actual.indices.filter { actual[$0] != expected[$0] }
                                if case .bitmap = mode, operation == .slice, !differences.isEmpty {
                                    // Separate masks quantize coverage before compositing. Restrict
                                    // the resulting error to overlapping, nonzero alpha samples.
                                    XCTAssertTrue(differences.allSatisfy { $0 % 4 == 3 && abs(Int(actual[$0]) - Int(expected[$0])) <= 2 })
                                    XCTAssertTrue(actual.indices.allSatisfy { (actual[$0] == 0) == (expected[$0] == 0) })
                                    var overlapping = Array(repeating: 0, count: differences.count)
                                    let glyphCount = source.makeGlyphs(maxWidth: .max, maxHeight: .max).reduce(0) { $0 + $1.glyphs.count }
                                    for ordinal in 0..<glyphCount {
                                        let isolated = MarginRenderer(environment: environment, operation: .slice)
                                        isolated.onlyGlyph = ordinal
                                        let selected = try value(styled, renderer: isolated)
                                        let pixels = try render(device: device, environment: environment) { selected.draw(in: $0) }
                                        for index in differences.indices where pixels[differences[index]] > 0 { overlapping[index] += 1 }
                                    }
                                    XCTAssertTrue(overlapping.allSatisfy { $0 >= 2 })
                                } else {
                                    XCTAssertTrue(differences.isEmpty, "Renderer \(operation), \(mode), \(string.debugDescription), size \(pointSize), display \(displayScale), render \(renderScale): \(differences.count) changed bytes")
                                }
                            case .shift: shifted = actual
                            case .translate: XCTAssertTrue(actual == shifted)
                            }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS fontCustomNamedOutsetTraitBoundaryObserved
    // ASSERTIONS textDrawingFrameCompensationObserved
    func testSelectedNamedWeightPreservesBitmapAndVectorDrawingOnGPU() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for renderScale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.font = .custom("NanumSquareNeo-Variable", fixedSize: 23)
                environment.defaultFontRenderingMode = mode
                environment.displayScale = 2
                environment._contentScaleFactor = renderScale
                let source = try resolve(Text(verbatim: "Ågj"), environment: environment)
                for language in ["en", "ur"] {
                    let text = GraphicsContext.ResolvedText(runs: source.runs, scaleFactor: source.scaleFactor,
                        displayScale: 2, preferredLanguages: [language])
                    let styled = ResolvedStyledText.StringDrawing(resolvedText: text)
                    XCTAssertEqual(styled.drawingMargins.leading, language == "en" ? 4.5 : 1)
                    XCTAssertEqual(styled.drawingMargins.trailing, 3)
                    let plain = try value(styled)
                    let expected = try render(device: device, environment: environment) {
                        $0.draw(text, in: CGRect(origin: .zero, size: plain.size))
                    }
                    XCTAssertTrue(expected.contains { $0 != 0 })
                    let prepared = try XCTUnwrap(plain.makeDrawing())
                    let renderer = MarginRenderer(environment: environment, operation: .line)
                    let item = try value(styled, renderer: renderer)
                    let immediate = try render(device: device, environment: environment) { plain.draw(in: $0) }
                    let cached = try render(device: device, environment: environment) { plain.draw(prepared, in: $0) }
                    let custom = try render(device: device, environment: environment) { item.draw(in: $0) }
                    XCTAssertTrue(immediate == expected)
                    XCTAssertTrue(cached == expected)
                    XCTAssertTrue(custom == expected)
                    XCTAssertEqual(renderer.origin?.x, styled.drawingMargins.leading)
                    XCTAssertEqual(renderer.origin?.y, text.firstBaseline(in: plain.size) + styled.drawingMargins.top)
                }
            }
        }
    }

    // ASSERTIONS fontStylisticAlternativeGlyphConsumerObserved
    // ASSERTIONS textStylisticAlternativeCarrierObserved
    func testStylisticSetsReachPreparedAndRendererPixelsInBothModes() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let data = try StylisticFontFixture.make(enabled: true)
        let base = VUI.Font.data(data, size: 23)
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            for renderScale: CGFloat in [1, 2] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = mode
                environment._contentScaleFactor = renderScale
                for (sequence, letters) in [([1], "BB"), ([2], "CC"), ([20], "UB"), ([2, 1], "CC")] {
                    let text = sequence.reduce(Text(verbatim: "AB").font(base)) {
                        $0._stylisticAlternative(.init(rawValue: $1)!)
                    }
                    let source = try resolve(text, environment: environment)
                    let reference = try resolve(Text(verbatim: letters).font(base), environment: environment)
                    let styled = ResolvedStyledText.StringDrawing(resolvedText: source)
                    let plain = try value(styled)
                    let expected = try render(device: device, environment: environment) {
                        try value(ResolvedStyledText.StringDrawing(resolvedText: reference)).draw(in: $0)
                    }
                    XCTAssertTrue(expected.contains { $0 != 0 })
                    let prepared = try XCTUnwrap(plain.makeDrawing())
                    let renderer = MarginRenderer(environment: environment, operation: .line)
                    let custom = try value(styled, renderer: renderer)
                    let immediatePixels = try render(device: device, environment: environment) { plain.draw(in: $0) }
                    let preparedPixels = try render(device: device, environment: environment) { plain.draw(prepared, in: $0) }
                    let rendererPixels = try render(device: device, environment: environment) { custom.draw(in: $0) }
                    XCTAssertTrue(immediatePixels == expected, "Immediate \(mode) \(sequence)")
                    XCTAssertTrue(preparedPixels == expected, "Prepared \(mode) \(sequence)")
                    XCTAssertTrue(rendererPixels == expected, "Renderer \(mode) \(sequence)")
                }
            }
        }
    }

    // ASSERTIONS fontClippingFractionalTextConsumerObserved
    // ASSERTIONS fontClippingFractionalInterpolationObserved
    // ASSERTIONS textDrawingFrameCompensationObserved
    // ASSERTIONS textDrawingRendererLocalContextObserved
    func testFractionalClippingPreservesPreparedAndRendererPixelsOnGPU() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for (kind, size, weightClass, expectedTop): (FractionalClippingFixture.Kind, CGFloat, CGFloat, CGFloat) in [
            (.single, 1024 / 350.5, 650, 0.5),
            (.multiple, 2.6654860046407274, 650, 1),
            (.mapped, 2.8199855150878617, 525, 0.5)
        ] {
            let data = try FractionalClippingFixture.make(kind)
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for renderScale: CGFloat in [1, 2] {
                    var environment = EnvironmentValues()
                    environment.font = .data(data, size: size,
                        weight: .init(value: FontWeightScale.logicalWeight(forClass: weightClass)))
                    environment.defaultFontRenderingMode = mode
                    environment.displayScale = 2
                    environment._contentScaleFactor = renderScale
                    let source = try resolve(Text(verbatim: "Hg\nHg"), environment: environment)
                    let text = GraphicsContext.ResolvedText(runs: source.runs, scaleFactor: source.scaleFactor,
                        displayScale: 2, preferredLanguages: ["en"])
                    let styled = ResolvedStyledText.StringDrawing(resolvedText: text)
                    XCTAssertEqual(styled.drawingMargins.top, expectedTop)
                    let plain = try value(styled)
                    let expected = try render(device: device, environment: environment) {
                        $0.draw(text, in: CGRect(origin: .zero, size: plain.size))
                    }
                    XCTAssertTrue(expected.contains { $0 != 0 })
                    // The display-list frame uses a pixel-aligned scissor, while
                    // the renderer's local context remains unbounded.
                    let clip = plain.frame.applying(CGAffineTransform(scaleX: renderScale, y: renderScale))
                        .integral.applying(CGAffineTransform(scaleX: 1 / renderScale, y: 1 / renderScale))
                    let clipped = try render(device: device, environment: environment) {
                        $0.clip(to: Path(clip))
                        $0.draw(text, in: CGRect(origin: .zero, size: plain.size))
                    }
                    let prepared = try XCTUnwrap(plain.makeDrawing())
                    let renderer = MarginRenderer(environment: environment, operation: .line)
                    let item = try value(styled, renderer: renderer)
                    let immediate = try render(device: device, environment: environment) { plain.draw(in: $0) }
                    let cached = try render(device: device, environment: environment) { plain.draw(prepared, in: $0) }
                    let custom = try render(device: device, environment: environment) { item.draw(in: $0) }
                    let label = "\(kind) \(mode) renderScale=\(renderScale) frame=\(plain.frame)"
                    if kind == .single, case .bitmap = mode {
                        // The tiny bitmap's right-edge coverage exceeds its advance.
                        // Restoring the previous vertical allowance leaves that
                        // independent horizontal clip unchanged.
                        let padded = ResolvedStyledText.StringDrawing(stylePadding: EdgeInsets(top: 0.5, leading: 0, bottom: 0, trailing: 0), resolvedText: text)
                        let previous = try value(padded)
                        XCTAssertEqual(previous.frame.minY, -1)
                        let pixels = try render(device: device, environment: environment) { previous.draw(in: $0) }
                        XCTAssertTrue(pixels == immediate, label)
                    }
                    XCTAssertTrue(immediate == clipped, label)
                    XCTAssertTrue(cached == clipped, label)
                    XCTAssertTrue(custom == expected, label)
                    XCTAssertEqual(prepared.origin.y, expectedTop)
                    XCTAssertEqual(renderer.origin?.y, text.firstBaseline(in: plain.size) + expectedTop)
                }
            }
        }
    }

    // ASSERTIONS textDrawingFrameCompensationObserved
    // ASSERTIONS textDrawingRendererLocalContextObserved
    func testRendererShapesAndRecordedReplayUseTheExpandedFrameOnGPU() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        var environment = EnvironmentValues()
        environment.font = .system(size: 13)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment._contentScaleFactor = 2
        let source = try resolve(Text(verbatim: "Hg"), environment: environment)
        let styled = ResolvedStyledText.StringDrawing(stylePadding: EdgeInsets(top: 2, leading: 3, bottom: 1, trailing: 4), resolvedText: source)
        let renderer = MarginRenderer(environment: environment, operation: .line)
        renderer.drawMarker = true
        let item = try value(styled, renderer: renderer)
        let expected = try render(device: device, environment: environment) { context in
            context.fill(Path(CGRect(x: 20 + item.frame.minX, y: 20 + item.frame.minY, width: 2, height: 2)), with: .color(.red))
        }
        for record in [false, true] {
            let actual = try render(device: device, environment: environment) { context in
                if record {
                    let recording = context.recordingContext(size: CGSize(width: 128, height: 128))
                    item.draw(in: recording)
                    recording.recording!.draw(in: context)
                } else { item.draw(in: context) }
            }
            XCTAssertEqual(renderer.transform, .identity)
            XCTAssertTrue(actual == expected)
        }
    }

    // ASSERTIONS textDrawingFrameCompensationObserved
    func testPreparedOriginMovesBackgroundsAndDecorationsTogetherOnGPU() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            var environment = EnvironmentValues()
            environment.font = .system(size: 13)
            environment.defaultFontRenderingMode = mode
            environment.displayScale = 2
            environment._contentScaleFactor = 2
            var string = AttributedString("Hg\nHg")
            string._setCoreAttributes(_ResolvedTextRunAttributes(backgroundColor: .yellow,
                strikethroughStyle: .init(), underlineStyle: .init()))
            let source = try resolve(Text(string), environment: environment)
            let styled = ResolvedStyledText.StringDrawing(stylePadding: EdgeInsets(top: 2, leading: 3, bottom: 1, trailing: 4), resolvedText: source)
            let item = try value(styled)
            let expected = try render(device: device, environment: environment) {
                $0.draw(source, in: CGRect(origin: .zero, size: item.size))
            }
            let actual = try render(device: device, environment: environment) { item.draw(in: $0) }
            XCTAssertTrue(actual == expected)
        }
    }
}

private final class MarginRenderer: TextRendererBoxBase {
    enum Operation: CaseIterable { case line, run, slice, shift, translate }
    let values: EnvironmentValues
    let operation: Operation
    var origin: CGPoint?
    var transform: CGAffineTransform?
    var clipBounds: CGRect?
    var opacity: Double?
    var drawMarker = false
    var onlyGlyph: Int?
    var recordsProxy = false
    var proxySize: CGSize?
    var layoutLineCount: Int?
    init(environment: EnvironmentValues, operation: Operation) { values = environment; self.operation = operation }
    override var environment: EnvironmentValues { values }
    override var displayPadding: EdgeInsets { EdgeInsets() }
    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect {
        if recordsProxy { proxySize = text.sizeThatFits(.unspecified) }
        return CGRect(origin: .zero, size: size)
    }
    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        layoutLineCount = layout.count
        origin = layout.first?.origin
        transform = context.transform
        clipBounds = context.clipBoundingRect
        opacity = context.opacity
        if drawMarker {
            context.fill(Path(CGRect(x: 20, y: 20, width: 2, height: 2)), with: .color(.red))
            return
        }
        if operation == .translate { context.translateBy(x: 3, y: 5) }
        var ordinal = 0
        for var line in layout {
            if operation == .shift { line.origin.x += 3; line.origin.y += 5 }
            switch operation {
            case .line, .shift, .translate: context.draw(line)
            case .run: for run in line { context.draw(run) }
            case .slice: for run in line { for slice in run {
                if onlyGlyph == nil || onlyGlyph == ordinal { context.draw(slice) }
                ordinal += 1
            } }
            }
        }
    }
}
