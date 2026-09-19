import Foundation
import XCTest
import VVD
@testable import VUI

final class TextForegroundStyleTests: XCTestCase {
    private let size = CGSize(width: 128, height: 80)
    private var gradient: LinearGradient {
        LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    }

    func testInlineFactoryCopiesInheritedStyleAndKeepsValueEquality() throws {
        // ASSERTIONS textInlineStyleProducer27Observed
        let colored: Text = Text(verbatim: "A").foregroundStyle(.red)
        guard case .color(.some(.red)) = colored.modifiers.last else { return XCTFail() }
        let sharedGradient = gradient
        let first: Text = Text(verbatim: "A").foregroundStyle(sharedGradient)
        XCTAssertEqual(first, Text(verbatim: "A").foregroundStyle(sharedGradient))
        XCTAssertNotEqual(first, Text(verbatim: "A").foregroundStyle(gradient))
        XCTAssertNotEqual(first, Text(verbatim: "A").foregroundStyle(gradient.opacity(0.5)))
        guard case let .anyTextModifier(modifier) = first.modifiers.last else { return XCTFail() }
        XCTAssertTrue(modifier is TextForegroundStyleModifier)

        var style = Text.Style()
        style.color = .explicit(AnyShapeStyle(Color.red))
        var environment = EnvironmentValues()
        environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.blue))
        TextForegroundStyleModifier(AnyShapeStyle.opacity(0.4)).modify(style: &style, environment: environment)
        var properties = Text.ResolvedProperties()
        let color = try XCTUnwrap(style.color.resolve(in: environment, with: .allowsKeyColors,
            properties: &properties, includeDefaultAttributes: true))
        var expected = Color.red.resolveHDR(in: environment)
        expected.opacity *= 0.4
        XCTAssertEqual(color, expected)
        XCTAssertTrue(properties.styles.isEmpty)
    }

    func testPaletteFoldsColorsAndDeduplicatesAllStyleFields() throws {
        // ASSERTIONS textIndexedStyleAllocationObserved
        var properties = Text.ResolvedProperties()
        let hdr = VUI.Color.ResolvedHDR(.init(colorSpace: .sRGBLinear,
            red: 0.8, green: 0.2, blue: 0.1, opacity: 0.5), headroom: 2)
        var color = _ShapeStyle_Pack.Style(.color(hdr))
        color.opacity = 0.25
        color._blend = .normal
        var expected = hdr
        expected.opacity = 0.125
        XCTAssertEqual(properties.addCustomStyle(color), expected)
        XCTAssertTrue(properties.styles.isEmpty)
        XCTAssertFalse(properties.features.contains(.keyColor))

        let base = try resolvedStyle(gradient)
        var opacity = base
        opacity.opacity = 0.5
        var normal = base
        normal._blend = .normal
        let shadow = try resolvedStyle(gradient.shadow(.drop(radius: 2)))
        let variants = [base, opacity, normal, shadow]
        for (index, style) in variants.enumerated() {
            let key = properties.addCustomStyle(style)
            XCTAssertEqual(key.linearRed, -1)
            XCTAssertEqual(key.linearGreen, -1)
            XCTAssertEqual(key.linearBlue, Float(index) / 1024)
            XCTAssertEqual(key.opacity, 1)
            XCTAssertNil(key.headroom)
            XCTAssertEqual(properties.addCustomStyle(style), key)
        }
        XCTAssertEqual(properties.styles, variants)
        XCTAssertTrue(properties.features.contains(.keyColor))
    }

    func testPreparationKeepsOriginalTextAndForegroundKeySeparateFromInlinePalette() throws {
        // ASSERTIONS textForegroundPreparation27Observed
        // ASSERTIONS textIndexedStyleAllocationObserved
        try withDevice { _ in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var environment = EnvironmentValues()
                environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(gradient.shadow(.drop(radius: 1))))
                let text = Text("A") + Text("B").foregroundStyle(gradient) + Text("C").foregroundColor(.green)
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true)
                let owner = try XCTUnwrap(helper.resolve(text, with: environment, sizeFitting: false))
                XCTAssertEqual(helper.lastText, text)
                XCTAssertEqual(owner.styles, [try resolvedStyle(gradient)])
                XCTAssertTrue(owner.needsStyledRendering)
                let colors = try XCTUnwrap(owner.resolvedText).runs.compactMap { run -> VUI.Color.ResolvedHDR? in
                    if case let .styledText(_, _, _, attributes) = run {
                        return attributes.foregroundColor?.resolveHDR(in: environment)
                    }
                    return nil
                }
                XCTAssertEqual(colors.map(\.linearBlue).prefix(2), [-1, 0])
                XCTAssertEqual(colors.last, Color.green.resolveHDR(in: environment))
                let layers = owner.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertNotNil(layers.foreground)
                XCTAssertEqual(layers.keyed.map(\.index), [0])
                XCTAssertNotNil(layers.unstyled)
                XCTAssertLessThan(try XCTUnwrap(layers.foreground).boundingRect.maxX,
                    try XCTUnwrap(layers.unstyled).boundingRect.maxX)
            }
        }
    }

    func testSuffixPaletteIsImportedBeforeBodyAndUnusedEntriesDoNotProduceLayers() throws {
        // ASSERTIONS textSuffixPaletteReuseObserved
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { _ in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true,
                    features: .produceTextLayout)
                var environment = EnvironmentValues()
                let suffix = try XCTUnwrap(helper.resolve(Text(" more").foregroundStyle(gradient),
                    with: environment, sizeFitting: false))
                environment[TextSuffixKey.self] = Text.Suffix.truncated(Text(" more")).resolve(text: suffix)
                helper.features = [.useTextSuffix, .produceTextLayout]
                let repeated = try XCTUnwrap(helper.resolve(Text(verbatim: "A").foregroundStyle(gradient),
                    with: environment, sizeFitting: false))
                XCTAssertEqual(repeated.styles, suffix.styles)
                let repeatedLayers = repeated.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertEqual(repeatedLayers.keyed.map(\.index), [0])
                let different = try XCTUnwrap(helper.resolve(Text(verbatim: "A").foregroundStyle(gradient.opacity(0.5)),
                    with: environment, sizeFitting: false))
                XCTAssertEqual(different.styles.count, 2)
                XCTAssertEqual(different.styles.first, suffix.styles.first)
                let layers = different.layers(for: size, renderer: nil, deviceScale: 1,
                    environment: environment, inputs: drawingInputs(host))
                XCTAssertEqual(layers.keyed.map(\.index), [1])
            }
        }
    }

    func testMountedForegroundStylePartitionsInheritedAndExplicitRuns() throws {
        // ASSERTIONS textForegroundPreparation27Observed
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { device in
            let content = AnyView(Text("A") + Text("B").foregroundColor(.green))
                .foregroundStyle(gradient).font(.system(size: 24))
            let host = ForegroundTextHost(content)
            let list = try host.list()
            let drawings = drawingContents(in: list)
            XCTAssertEqual(drawings.filter { !$0.1.alphaOnly }.count, 1)
            XCTAssertEqual(drawings.filter { $0.1.alphaOnly }.count, 1)
            let pixels = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
            let opaque = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 100 }
            XCTAssertTrue(opaque.contains { pixels[$0 + 1] > pixels[$0] && pixels[$0 + 1] > pixels[$0 + 2] })
            XCTAssertTrue(opaque.contains { pixels[$0] > pixels[$0 + 1] || pixels[$0 + 2] > pixels[$0 + 1] })
        }
    }

    func testAlphaOnlyReplayIgnoresRecordedRGBAndPreservesCoverage() throws {
        try withDevice { device in
            let host = ForegroundTextHost(Text("fixture"))
            func list(_ color: VUI.Color) -> DisplayList {
                let context = GraphicsContext(recording: RBDisplayList(viewport: CGRect(origin: .zero, size: size)),
                    environment: .init(), inputs: drawingInputs(host))
                let bounds = CGRect(x: 10, y: 12, width: 20, height: 18)
                context.fill(Path(bounds), with: .color(color.opacity(0.5)))
                let contents = context.recording!.moveContents()
                var list = DisplayList()
                list.items = [DisplayList.Item(content: DisplayList.Content(drawing: contents, origin: .zero,
                    options: .init(flags: [.defaultFlags, .alphaOnly])), frame: bounds,
                    identity: .none, version: .init())]
                return list
            }
            let expected = try pixels(list(.white), device: device, resources: host.rendererHost.sceneResources)
            XCTAssertGreaterThan(expected[(16 * 128 + 16) * 4 + 3], 100)
            for color: VUI.Color in [.black, .red, .blue] {
                XCTAssertEqual(try pixels(list(color), device: device, resources: host.rendererHost.sceneResources), expected)
            }
        }
    }

    func testKeyedMaskKeepsTextPlacementAndFillInBothDrawingModes() throws {
        // ASSERTIONS textKeyedLayerSelectionObserved
        try withDevice { device in
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                let text = Text("Abg").font(.system(size: 22)).italic().underline()
                let direct = ForegroundTextHost(text.foregroundColor(.blue)
                    .environment(\.defaultFontRenderingMode, mode)
                    .frame(width: 128, height: 80, alignment: .bottomTrailing))
                let keyed = ForegroundTextHost(text.foregroundStyle(Color.blue.shadow(.drop(color: .clear, radius: 0)))
                    .environment(\.defaultFontRenderingMode, mode)
                    .frame(width: 128, height: 80, alignment: .bottomTrailing))
                let expected = try pixels(direct.list(), device: device, resources: direct.rendererHost.sceneResources)
                let actual = try pixels(keyed.list(), device: device, resources: keyed.rendererHost.sceneResources)
                // Offscreen color multiplication can round an RGB channel by one byte.
                XCTAssertEqual(stride(from: 3, to: actual.count, by: 4).map { actual[$0] },
                    stride(from: 3, to: expected.count, by: 4).map { expected[$0] })
                XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0) - Int($1)) }.max()!, 1)
            }
        }
    }

    func testCustomRendererRecordsOnceAndStyleLayersUseReversePaletteOrder() throws {
        // ASSERTIONS textKeyedLayerSelectionObserved
        // ASSERTIONS textMixedRecordingPartitionObserved
        try withDevice { device in
            let host = ForegroundTextHost(Text("fixture"))
            try host.graph.data.withCurrent {
                var environment = EnvironmentValues()
                environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.red.shadow(.drop(radius: 0))))
                let text = Text("A") + Text("B").foregroundStyle(gradient) +
                    Text("C").foregroundStyle(gradient.opacity(0.5)) + Text("D").foregroundColor(.green)
                var helper = ResolvedTextHelper(includeDefaultAttributes: true, allowsKeyColors: true,
                    features: [.customRenderer, .produceTextLayout])
                let owner = try XCTUnwrap(helper.resolve(text, with: environment, sizeFitting: false))
                let renderer = ForegroundRecordingRenderer(values: environment)
                let group = _ShapeStyle_InterpolatorGroup()
                var layers = _ShapeStyle_RenderedLayers(group: group)
                var shape = _ShapeStyle_RenderedShape(shape: .text(.init(text: owner, renderer: renderer)),
                    contentSeed: .init(), frame: CGRect(origin: .zero, size: size), options: [],
                    environment: host.graph.data.graph.makeInput(value: environment))
                let outer = try resolvedStyle(Color.red.shadow(.drop(radius: 0)))
                shape.renderItem(name: .foreground,
                    styles: .init(styles: [(.init(.foreground, 0), outer)]), layers: &layers)
                let list = layers.commit(shape: &shape)
                XCTAssertEqual(renderer.draws, 1)
                XCTAssertEqual(group.layers.map(\.id), [.unstyled, .customStyle(1), .customStyle(0), .styled(.foreground, 0)])
                XCTAssertEqual(group.layers[1].style, owner.styles[1])
                XCTAssertEqual(group.layers[2].style, owner.styles[0])
                _ = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
                _ = try pixels(list, device: device, resources: host.rendererHost.sceneResources)
                XCTAssertEqual(renderer.draws, 1)
                guard case .alphaMask = shape.shape else { return XCTFail("The final mask belongs to trailing retirement") }

                let plain = try XCTUnwrap(helper.resolve(Text("plain").foregroundColor(.green),
                    with: environment, sizeFitting: false))
                var replacement = _ShapeStyle_RenderedShape(shape: .text(.init(text: plain, renderer: nil)),
                    contentSeed: .init(), frame: CGRect(origin: .zero, size: size), options: [],
                    environment: host.graph.data.graph.makeInput(value: environment))
                var nextLayers = _ShapeStyle_RenderedLayers(group: group)
                replacement.renderItem(name: .foreground,
                    styles: .init(styles: [(.init(.foreground, 0), outer)]), layers: &nextLayers)
                _ = nextLayers.commit(shape: &replacement)
                XCTAssertFalse(group.layers[0].isRemoved)
                XCTAssertTrue(group.layers.dropFirst().allSatisfy(\.isRemoved))
                XCTAssertEqual(group.cursor, 0)
            }
        }
    }

    // ASSERTIONS textMixedGlyphAdvances27Observed textMixedAdvancePublication27Observed
    func testMixedFontMetricsPreserveEngineAdvancesThroughBothOwners() throws {
        try withDevice { _ in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let data = try Data(contentsOf: file)
            let text = Text(verbatim: "AAA AAA ").font(.file(file, size: 23))
                + Text(verbatim: "BBB BBB").font(.file(file, size: 31))
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for displayScale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for (width, minimum, limit): (CGFloat, CGFloat, Int) in [(300, 1, 1), (120, 0.25, 2)] {
                            let capture = FittingTextCapture()
                            let content = custom
                                ? AnyView(text.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(text)
                            let request = CGSize(width: width, height: 60)
                            let host = ForegroundTextHost(content.lineLimit(limit).minimumScaleFactor(minimum)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: 60, alignment: .topLeading), scale: displayScale)
                            let list = try host.list()
                            let owner: ResolvedStyledText
                            if custom {
                                owner = try XCTUnwrap(capture.owner)
                            } else {
                                owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                            }
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            let prepared = try XCTUnwrap(owner.prepareDrawing(in: .zero, with: metrics.size,
                                applyingMarginOffsets: true))
                            let source = prepared.source
                            var expected: [VVD.Font.ShapedGlyph] = []
                            var points: [CGFloat] = []
                            for run in source.runs {
                                guard case let .styledText(_, content, _, attributes) = run else {
                                    return XCTFail("Mixed text must retain its styled font runs")
                                }
                                let resource = try XCTUnwrap(attributes.fontResource)
                                points.append(resource.pointSize)
                                let font = try XCTUnwrap(VVD.Font(data: data))
                                font.setPointSize(resource.pointSize, dpi: (72, 72))
                                expected += try XCTUnwrap(font.shape(content)).glyphs
                            }
                            XCTAssertEqual(points, [23, 31].map {
                                let size = $0 * metrics.scale
                                return custom ? size : (size * 4).rounded() * 0.25
                            })
                            let glyphs = source.unwrappedGlyphLines().flatMap(\.glyphs)
                            XCTAssertEqual(glyphs.map(\.glyphIndex), expected.map { Optional($0.index) })
                            XCTAssertEqual(glyphs.map { $0.advance.width / source.scaleFactor }, expected.map(\.advance.width))
                            XCTAssertTrue(glyphs.allSatisfy { $0.kerning == .zero && $0.positionOffset == .zero })
                            let unwrapped = try XCTUnwrap(source.unwrappedGlyphLines().first)
                            XCTAssertEqual(unwrapped.width / source.scaleFactor, expected.reduce(0) { $0 + $1.advance.width })
                            let raw = source.unroundedLayoutMetrics(lineGlyphs: prepared.lines)
                            XCTAssertEqual(metrics.size.width, ceil(raw.size.width * displayScale) / displayScale)
                            if displayScale == 2 {
                                XCTAssertEqual(metrics.scale, limit == 1 ? 1 : 0.958984375)
                                XCTAssertEqual(raw.size.width, limit == 1 ? 225.009765625
                                    : custom ? 118.50761795043945 : 118.59326171875)
                                XCTAssertEqual(metrics.size.width, limit == 1 ? 225.5 : 119)
                            }
                            XCTAssertEqual(metrics.numberOfLines, UInt(limit))
                            XCTAssertFalse(metrics.hasTruncatedRanges)
                            XCTAssertEqual(owner.metrics(in: request, layoutMargins: nil).size, metrics.size)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textStringMixedSearch27Observed textStringMixedDrawing27Observed
    func testOrdinaryMixedFittingReachesMountedAndRecordedDrawingInBothModes() throws {
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func text(at factor: CGFloat, offset: Bool) -> Text {
                let first = Text(verbatim: "AAA AAA ")
                    .font(.file(file, size: (23 * factor * 4).rounded() * 0.25))
                var second = Text(verbatim: "BBB BBB")
                    .font(.file(file, size: (31 * factor * 4).rounded() * 0.25)).foregroundColor(.red)
                if offset { second = second.baselineOffset(3).kerning(1.5) }
                return first + second
            }
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for offset in [false, true] {
                        for (width, height, minimum, limit): (CGFloat, CGFloat, CGFloat, Int) in [
                            (80, 60, 0.25, 1), (80, 18, 0.5, 1), (120, 60, 0.25, 2)
                        ] {
                            let host = ForegroundTextHost(text(at: 1, offset: offset)
                                .lineLimit(limit).minimumScaleFactor(minimum).foregroundStyle(.black)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: height, alignment: .topLeading), scale: scale)
                            let list = try host.list()
                            let owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                            let factor = owner.metrics(in: CGSize(width: width, height: height), layoutMargins: nil).scale
                            XCTAssertGreaterThanOrEqual(factor, minimum)
                            XCTAssertLessThan(factor, 1)
                            let reference = ForegroundTextHost(text(at: factor, offset: offset)
                                .lineLimit(limit).minimumScaleFactor(1).foregroundStyle(.black)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: height, alignment: .topLeading), scale: scale)
                            let expected = try pixels(reference.list(), device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                            for replay in [false, true] {
                                let actual = try pixels(list, device: device,
                                    resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                XCTAssertTrue(actual == expected,
                                    "\(mode) scale=\(scale) offset=\(offset) minimum=\(minimum) limit=\(limit) replay=\(replay)")
                            }
                            XCTAssertNil(owner.preparedLayout)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textMixedFittingOwners27Observed textManagerMixedDrawing27Observed
    func testMixedFontFittingReachesMountedRendererDrawingInBothModes() throws {
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func text(at factor: CGFloat, offset: Bool) -> Text {
                let first = Text(verbatim: "AAA AAA ").font(.file(file, size: 23 * factor))
                var second = Text(verbatim: "BBB BBB").font(.file(file, size: 31 * factor)).foregroundColor(.red)
                if offset { second = second.baselineOffset(3).kerning(1.5) }
                return first + second
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for offset in [false, true] {
                        for (width, height, minimum, limit): (CGFloat, CGFloat, CGFloat, Int) in [
                            (80, 60, 0.25, 1), (80, 18, 0.5, 1), (120, 60, 0.25, 2)
                        ] {
                            let capture = FittingTextCapture()
                            let host = ForegroundTextHost(text(at: 1, offset: offset)
                                .textRenderer(FittingTextRenderer(capture: capture))
                                .lineLimit(limit).minimumScaleFactor(minimum)
                                .foregroundStyle(.black)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: height, alignment: .topLeading), scale: scale)
                            let list = try host.list()
                            let owner = try XCTUnwrap(capture.owner)
                            let entry = try XCTUnwrap(owner.cache.entries.first {
                                $0.request == CGSize(width: width, height: height)
                            })
                            let factor = entry.metrics.scale
                            XCTAssertGreaterThanOrEqual(factor, minimum)
                            XCTAssertLessThan(factor, 1)
                            let referenceCapture = FittingTextCapture()
                            let reference = ForegroundTextHost(text(at: factor, offset: offset)
                                .textRenderer(FittingTextRenderer(capture: referenceCapture))
                                .lineLimit(limit).minimumScaleFactor(1)
                                .foregroundStyle(.black)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: height, alignment: .topLeading), scale: scale)
                            let actual = try pixels(list, device: device,
                                resources: host.rendererHost.sceneResources, scale: scale)
                            let expected = try pixels(reference.list(), device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(stride(from: 3, to: actual.count, by: 4).contains { actual[$0] > 0 })
                            XCTAssertTrue(actual == expected,
                                "\(mode) scale=\(scale) offset=\(offset) minimum=\(minimum) limit=\(limit)")
                            XCTAssertGreaterThan(capture.draws, 0)
                            XCTAssertGreaterThan(referenceCapture.draws, 0)
                            XCTAssertEqual(owner.cache.entries.count, 1)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textSeparatorFittedDrawing27Observed textFittedDrawingSize27Observed
    func testMixedSeparatorMultilineFittingReachesDrawingAndReplay() throws {
        try checkSeparatorFittingDrawing(lineLimit: 2)
    }

    func testSingleLineSeparatorFittingReachesDrawingAndReplay() throws {
        // ASSERTIONS textSingleLineSeparatorFitting27Observed
        // ASSERTIONS textManagerSeparatorRangeConsumers27Observed
        try checkSeparatorFittingDrawing(lineLimit: 1)
    }

    private func checkSeparatorFittingDrawing(lineLimit: Int) throws {
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func text(separator: String, factor: CGFloat, custom: Bool) -> Text {
                func points(_ size: CGFloat) -> CGFloat {
                    let scaled = size * factor
                    return custom ? scaled : (scaled * 4).rounded() * 0.25
                }
                return Text(verbatim: "AAA AAA" + separator).font(.file(file, size: points(23)))
                    + Text(verbatim: "BBB BBB").font(.file(file, size: points(31)))
            }
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            let request = CGSize(width: lineLimit == 1 ? 80 : 120, height: 60)
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for separator in ["\n", "\u{2028}"] {
                            for minimum: CGFloat in [0.5, 0.25] {
                                let capture = FittingTextCapture()
                                let value = text(separator: separator, factor: 1, custom: custom)
                                    .foregroundColor(.black)
                                let content = custom
                                    ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                                let host = ForegroundTextHost(content.lineLimit(lineLimit).minimumScaleFactor(minimum)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: request.width, height: request.height, alignment: .topLeading), scale: scale)
                                let list = try host.list()
                                let owner: ResolvedStyledText
                                if custom {
                                    owner = try XCTUnwrap(capture.owner)
                                } else {
                                    owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                                }
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(textValues(list).map(\.size), [metrics.size])
                                let unlaid = lineLimit == 1 && custom && separator == "\n"
                                if unlaid {
                                    XCTAssertEqual(metrics.scale, minimum)
                                } else {
                                    XCTAssertGreaterThan(metrics.scale, minimum)
                                }
                                XCTAssertLessThan(metrics.scale, 1)
                                XCTAssertEqual(metrics.numberOfLines, UInt(lineLimit))
                                XCTAssertEqual(metrics.hasTruncatedRanges, unlaid)
                                let referenceCapture = FittingTextCapture()
                                let referenceText = text(separator: separator, factor: metrics.scale, custom: custom)
                                    .foregroundColor(.black)
                                let referenceContent = custom
                                    ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture)))
                                    : AnyView(referenceText)
                                let reference = ForegroundTextHost(referenceContent.lineLimit(lineLimit).minimumScaleFactor(1)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: request.width, height: request.height, alignment: .topLeading), scale: scale)
                                let referenceList = try reference.list()
                                let expected = try pixels(referenceList, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale)
                                XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                                for replay in [false, true] {
                                    let actual = try pixels(list, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                    XCTAssertTrue(actual == expected,
                                        "\(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) minimum=\(minimum) replay=\(replay)")
                                }
                                var environment = EnvironmentValues()
                                environment.displayScale = scale
                                environment.defaultFontRenderingMode = mode
                                let valueForRecording = try XCTUnwrap(textValues(list).first)
                                let contents = host.graph.data.withCurrent {
                                    owner.makeRBDisplayList(for: metrics.size, renderer: valueForRecording.view.renderer,
                                        deviceScale: scale, environment: environment,
                                        inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                            viewport: CGRect(origin: .zero, size: size), contentScaleFactor: scale,
                                            resourceCommandQueue: nil))
                                }
                                var freshList = DisplayList()
                                freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: size)) {
                                    contents.draw(in: $0)
                                }
                                let fresh = try pixels(freshList, device: device,
                                    resources: host.rendererHost.sceneResources, scale: scale)
                                let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                                var localReference = DisplayList()
                                localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                    foreground: .color(.black),
                                    bounds: referenceValue.view.text.frame(in: referenceValue.size,
                                        renderer: referenceValue.view.renderer),
                                    seed: .init(), environment: environment)
                                let localExpected = try pixels(localReference, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale)
                                XCTAssertTrue(fresh == localExpected,
                                    "Fresh recording: \(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) minimum=\(minimum)")
                                if custom {
                                    XCTAssertGreaterThan(capture.draws, 0)
                                    XCTAssertGreaterThan(referenceCapture.draws, 0)
                                    XCTAssertTrue(capture.truncationStates.allSatisfy { !$0 })
                                    XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testParagraphPublicationReachesDrawingAndReplay() throws {
        // ASSERTIONS textParagraphPublication27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for separator in ["\n", "\u{2028}"] {
                            let width: CGFloat = 120
                            let request = CGSize(width: width, height: 60)
                            let capture = FittingTextCapture()
                            let value = (Text(verbatim: "AAA AAA" + separator).font(.file(file, size: 23))
                                + Text(verbatim: "BBB BBB").font(.file(file, size: 31))).foregroundColor(.black)
                            let content = custom
                                ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                            let host = ForegroundTextHost(content.lineLimit(2).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: request.width, height: request.height, alignment: .topLeading), scale: scale)
                            let list = try host.list()
                            let owner: ResolvedStyledText
                            if custom {
                                owner = try XCTUnwrap(capture.owner)
                            } else {
                                owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                            }
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(textValues(list).map(\.size), [metrics.size])
                            XCTAssertEqual(metrics.scale, 1)
                            XCTAssertEqual(metrics.numberOfLines, 1)
                            XCTAssertEqual(metrics.hasTruncatedRanges, custom && separator == "\n")
                            let expectedWidth: CGFloat = custom && separator == "\n" ? 96 : scale == 1 ? 112 : 111.5
                            XCTAssertEqual(metrics.size, CGSize(width: expectedWidth, height: 27))
                            let referenceCapture = FittingTextCapture()
                            // The one-line control has the same retained fonts and
                            // paragraph structure, with an independently measured token line.
                            let referenceText = value
                            let referenceContent = custom
                                ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture)))
                                : AnyView(referenceText)
                            let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: request.width, height: request.height, alignment: .topLeading), scale: scale)
                            let referenceList = try reference.list()
                            let expected = try pixels(referenceList, device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                            for replay in [false, true] {
                                let actual = try pixels(list, device: device,
                                    resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                XCTAssertTrue(actual == expected,
                                    "\(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) replay=\(replay)")
                            }
                            var environment = EnvironmentValues()
                            environment.displayScale = scale
                            environment.defaultFontRenderingMode = mode
                            let valueForRecording = try XCTUnwrap(textValues(list).first)
                            let contents = host.graph.data.withCurrent {
                                owner.makeRBDisplayList(for: metrics.size, renderer: valueForRecording.view.renderer,
                                    deviceScale: scale, environment: environment,
                                    inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                        viewport: CGRect(origin: .zero, size: size), contentScaleFactor: scale,
                                        resourceCommandQueue: nil))
                            }
                            var freshList = DisplayList()
                            freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: size)) {
                                contents.draw(in: $0)
                            }
                            let fresh = try pixels(freshList, device: device,
                                resources: host.rendererHost.sceneResources, scale: scale)
                            let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                            var localReference = DisplayList()
                            localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                foreground: .color(.black),
                                bounds: referenceValue.view.text.frame(in: referenceValue.size,
                                    renderer: referenceValue.view.renderer),
                                seed: .init(), environment: environment)
                            let localExpected = try pixels(localReference, device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(fresh == localExpected,
                                "Fresh recording: \(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription)")
                            if custom {
                                XCTAssertGreaterThan(capture.draws, 0)
                                XCTAssertGreaterThan(referenceCapture.draws, 0)
                                XCTAssertTrue(capture.truncationStates.allSatisfy { !$0 })
                                XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 })
                            }
                        }
                    }
                }
            }
        }
    }

    func testInsetTextInkIsNotClippedToItsMeasurementBounds() throws {
        // ASSERTIONS textInsetInkClipping27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let samples: [(String, Text)] = [
                ("terminal-space-lf", Text(verbatim: "AAA AAA \n").font(.file(file, size: 23))
                    + Text(verbatim: "BBB BBB").font(.file(file, size: 31))),
                ("terminal-space-line", Text(verbatim: "AAA AAA \u{2028}").font(.file(file, size: 23))
                    + Text(verbatim: "BBB BBB").font(.file(file, size: 31))),
                ("left-overhang", Text(verbatim: "jjj").font(.file(file, size: 23))),
                ("right-control", Text(verbatim: "fff").font(.file(file, size: 23))),
                ("top-overhang", Text(verbatim: "Ågj").font(.file(file, size: 23)))
            ]
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for origin in [CGPoint.zero, CGPoint(x: 4, y: 10), CGPoint(x: 4.25, y: 10.25)] {
                        for clipped in [false, true] {
                            for (name, text) in samples {
                                let label = "\(name) \(mode) scale=\(scale) origin=\(origin) clipped=\(clipped)"
                                var results: [[UInt8]] = []
                                for custom in [false, true] {
                                    let capture = FittingTextCapture()
                                    let value = text.foregroundColor(.black)
                                    let source = custom ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                                    let measured = source.lineLimit(1).minimumScaleFactor(1)
                                        .environment(\.defaultFontRenderingMode, mode)
                                    let host = ForegroundTextHost(measured
                                        .frame(width: 120, height: 60, alignment: .topLeading)
                                        .padding(.leading, origin.x).padding(.top, origin.y)
                                        .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                                    let hostList = try host.list()
                                    let textValue = try XCTUnwrap(textValues(hostList).first)
                                    var list = hostList
                                    if clipped {
                                        // Keep the outer clip in viewport coordinates;
                                        // the mounted list already carries text placement.
                                        list = DisplayList()
                                        list.appendEffect(.clip(Path(CGRect(origin: origin, size: textValue.size)), .init(), []),
                                            contents: hostList, frame: CGRect(origin: .zero, size: size))
                                    }
                                    let direct = try pixels(list, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale)
                                    results.append(direct)
                                    XCTAssertTrue(stride(from: 3, to: direct.count, by: 4).contains { direct[$0] > 0 }, label)
                                    let replay = try pixels(list, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale, replay: true)
                                    XCTAssertTrue(replay == direct, "Replay: \(label) custom=\(custom)")

                                    let owner = textValue.view.text
                                    var environment = EnvironmentValues()
                                    environment.displayScale = scale
                                    environment.defaultFontRenderingMode = mode
                                    let viewport = CGRect(origin: .zero, size: size)
                                    let contents = host.graph.data.withCurrent {
                                        owner.makeRBDisplayList(for: textValue.size, renderer: textValue.view.renderer,
                                            deviceScale: scale, environment: environment,
                                            inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                                viewport: viewport, contentScaleFactor: scale, resourceCommandQueue: nil))
                                    }
                                    var freshList = DisplayList()
                                    freshList.appendTextItem(foreground: .color(.black), bounds: viewport) { context in
                                        var context = context
                                        context.translateBy(x: origin.x, y: origin.y)
                                        if clipped {
                                            context.clip(to: Path(CGRect(origin: .zero, size: textValue.size)))
                                        }
                                        contents.draw(in: context)
                                    }
                                    let fresh = try pixels(freshList, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale)
                                    XCTAssertTrue(fresh == direct, "Fresh recording: \(label) custom=\(custom)")
                                    if !custom {
                                        var immediateList = DisplayList()
                                        immediateList.appendTextItem(foreground: .color(.black), bounds: viewport) { context in
                                            var context = context
                                            context.translateBy(x: origin.x, y: origin.y)
                                            if clipped {
                                                context.clip(to: Path(CGRect(origin: .zero, size: textValue.size)))
                                            }
                                            textValue.draw(in: context)
                                        }
                                        let immediate = try pixels(immediateList, device: device,
                                            resources: host.rendererHost.sceneResources, scale: scale)
                                        XCTAssertTrue(immediate == direct, "Uncached drawing: \(label)")
                                    }
                                    if name == "left-overhang", origin == CGPoint(x: 4, y: 10) {
                                        let pixelWidth = Int(size.width * scale)
                                        let outsideInk = stride(from: 3, to: direct.count, by: 4).filter {
                                            ($0 / 4) % pixelWidth < Int(origin.x * scale) && direct[$0] > 0
                                        }.count
                                        if clipped {
                                            XCTAssertEqual(outsideInk, 0, "Outer clip: \(label) custom=\(custom)")
                                        } else {
                                            XCTAssertGreaterThan(outsideInk, 0, "Visible ink: \(label) custom=\(custom)")
                                        }
                                    }
                                    if custom { XCTAssertGreaterThan(capture.draws, 0) }
                                }
                                XCTAssertTrue(results[0] == results[1], "Owners: \(label)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testTerminalWhitespaceFragmentExtentReachesDrawingAndReplay() throws {
        // ASSERTIONS textTerminalSpacePublication27Observed
        // ASSERTIONS textFractionalTokenAdmission27Observed
        // ASSERTIONS textTailTokenEpsilon27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        let cases: [(String, Int, CGFloat)] = [
                            ("\u{2028}", 1, 120), ("\u{2028}", 1, 124),
                            ("\u{2028}", 2, 120), ("\u{2028}", 2, 134),
                            ("\n", 1, 120), ("\n", 2, 134),
                            ("\u{2028}", 1, 116.5), ("\u{2028}", 1, 116.8193359375),
                            ("\u{2028}", 2, 122.5), ("\u{2028}", 2, 122.5244140625),
                            ("\n", 1, 116.5), ("\n", 1, 116.8193359375),
                            ("\n", 2, 122.5), ("\n", 2, 122.5244140625),
                            ("\u{2028}", 1, 116.8193359375 - 0.001), ("\u{2028}", 1, 116.8193359375 - 0.0002),
                            ("\u{2028}", 2, 122.5244140625 - 0.001), ("\u{2028}", 2, 122.5244140625 - 0.0002),
                            ("\n", 1, 116.8193359375 - 0.001), ("\n", 1, 116.8193359375 - 0.0002),
                            ("\n", 2, 122.5244140625 - 0.001), ("\n", 2, 122.5244140625 - 0.0002)
                        ]
                        for (separator, spaces, width) in cases {
                            let request = CGSize(width: width, height: 60)
                            let capture = FittingTextCapture()
                            let body = "AAA AAA" + String(repeating: " ", count: spaces)
                            let insertedWidth: CGFloat = spaces == 1 ? 116.8193359375 : 122.5244140625
                            let removed = insertedWidth > width + (custom ? 0.001 : 0.0002)
                            let glyphWidth: CGFloat = removed ? 111.1142578125 : insertedWidth
                            let fragmentWidth = min(width, insertedWidth > width ? glyphWidth :
                                (spaces == 1 ? 122.5244140625 : 133.9345703125))
                            let value = (Text(verbatim: body + separator).font(.file(file, size: 23))
                                + Text(verbatim: "BBB BBB").font(.file(file, size: 31))).foregroundColor(.black)
                            let content = custom
                                ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                            // Anchor the matched hosts at the image origin so their
                            // viewport and ink-clipping boundary are identical.
                            let host = ForegroundTextHost(content.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: request.width, height: request.height, alignment: .topLeading)
                                .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                            let list = try host.list()
                            let owner: ResolvedStyledText
                            if custom {
                                owner = try XCTUnwrap(capture.owner)
                            } else {
                                owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                            }
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(textValues(list).map(\.size), [metrics.size])
                            XCTAssertEqual(metrics.scale, 1)
                            XCTAssertEqual(metrics.numberOfLines, 1)
                            XCTAssertEqual(metrics.hasTruncatedRanges, removed || (custom && separator == "\n"))
                            let expectedWidth = ceil((custom ? fragmentWidth : glyphWidth) * scale) / scale
                            XCTAssertEqual(metrics.size, CGSize(width: expectedWidth, height: 27))
                            // A request safely on the selected side of the boundary
                            // keeps the reference independent of each owner's tolerance.
                            let referenceCapture = FittingTextCapture()
                            let referenceWidth = removed ? (spaces == 1 ? 116.5 : 122.5) : ceil(insertedWidth)
                            let referenceContent = custom ? AnyView(value)
                                : AnyView(value.textRenderer(FittingTextRenderer(capture: referenceCapture)))
                            let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: referenceWidth, height: request.height, alignment: .topLeading)
                                .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                            let referenceList = try reference.list()
                            let expected = try pixels(referenceList, device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                            for replay in [false, true] {
                                let actual = try pixels(list, device: device,
                                    resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                XCTAssertTrue(actual == expected,
                                    "\(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) spaces=\(spaces) width=\(width) replay=\(replay)")
                            }
                            var environment = EnvironmentValues()
                            environment.displayScale = scale
                            environment.defaultFontRenderingMode = mode
                            let valueForRecording = try XCTUnwrap(textValues(list).first)
                            let contents = host.graph.data.withCurrent {
                                owner.makeRBDisplayList(for: metrics.size, renderer: valueForRecording.view.renderer,
                                    deviceScale: scale, environment: environment,
                                    inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                        viewport: CGRect(origin: .zero, size: size), contentScaleFactor: scale,
                                        resourceCommandQueue: nil))
                            }
                            var freshList = DisplayList()
                            freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: size)) {
                                contents.draw(in: $0)
                            }
                            let fresh = try pixels(freshList, device: device,
                                resources: host.rendererHost.sceneResources, scale: scale)
                            let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                            var localReference = DisplayList()
                            localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                foreground: .color(.black),
                                bounds: referenceValue.view.text.frame(in: referenceValue.size,
                                    renderer: referenceValue.view.renderer),
                                seed: .init(), environment: environment)
                            let localExpected = try pixels(localReference, device: device,
                                resources: reference.rendererHost.sceneResources, scale: scale)
                            XCTAssertTrue(fresh == localExpected,
                                "Fresh recording: \(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) spaces=\(spaces) width=\(width)")
                            if custom {
                                XCTAssertGreaterThan(capture.draws, 0)
                                XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == removed })
                                XCTAssertTrue(capture.lineWidths.allSatisfy { $0 == [fragmentWidth] })
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTruncationWhitespaceReachesDrawingAndReplay() throws {
        // ASSERTIONS textTailTokenWhitespace27Observed
        // ASSERTIONS textTailCharacterFit27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for separator in ["\n", "\u{2028}"] {
                            for (width, tail, expectedText, truncated): (CGFloat, String, String, Bool) in [
                                (80, "", "AAA…", true), (82, "", "AAA A…", true),
                                (112, "", "AAA AAA…", false), (120, " ", "AAA AAA …", false),
                                (60.3974609375 - 0.001, "", custom ? "AAA…" : "AA…", true),
                                ((60.3974609375 - 0.0002).nextDown, "", custom ? "AAA…" : "AA…", true),
                                (60.3974609375 - 0.0002, "", "AAA…", true),
                                (81.1064453125 - 0.0002, "", custom ? "AAA A…" : "AAA…", true),
                                (81.1064453125 - 0.0001, "", "AAA A…", true)
                            ] {
                                let request = CGSize(width: width, height: 60)
                                let capture = FittingTextCapture()
                                let value = (Text(verbatim: "AAA AAA" + tail + separator).font(.file(file, size: 23))
                                    + Text(verbatim: "BBB BBB").font(.file(file, size: 31))).foregroundColor(.black)
                                let content = custom
                                    ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                                let host = ForegroundTextHost(content.lineLimit(1).minimumScaleFactor(1)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: request.width, height: request.height, alignment: .topLeading)
                                    .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                                let list = try host.list()
                                let owner: ResolvedStyledText
                                if custom {
                                    owner = try XCTUnwrap(capture.owner)
                                } else {
                                    owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                                }
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(textValues(list).map(\.size), [metrics.size])
                                XCTAssertEqual(metrics.scale, 1)
                                XCTAssertEqual(metrics.numberOfLines, 1)
                                XCTAssertEqual(metrics.hasTruncatedRanges, truncated || (custom && separator == "\n"))
                                let referenceCapture = FittingTextCapture()
                                // Keep the same font collection and paragraph owners
                                // while appending the token without removing body text.
                                let referenceText = (Text(verbatim: String(expectedText.dropLast()) + separator)
                                    .font(.file(file, size: 23))
                                    + Text(verbatim: "BBB BBB").font(.file(file, size: 31))).foregroundColor(.black)
                                let referenceContent = custom
                                    ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture)))
                                    : AnyView(referenceText)
                                let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: ceil(request.width), height: request.height, alignment: .topLeading)
                                    .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                                let referenceList = try reference.list()
                                let expected = try pixels(referenceList, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale)
                                XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                                for replay in [false, true] {
                                    let actual = try pixels(list, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                    XCTAssertTrue(actual == expected,
                                        "\(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) width=\(width) tail=\(tail.debugDescription) replay=\(replay)")
                                }
                                var environment = EnvironmentValues()
                                environment.displayScale = scale
                                environment.defaultFontRenderingMode = mode
                                let valueForRecording = try XCTUnwrap(textValues(list).first)
                                let contents = host.graph.data.withCurrent {
                                    owner.makeRBDisplayList(for: metrics.size, renderer: valueForRecording.view.renderer,
                                        deviceScale: scale, environment: environment,
                                        inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                            viewport: CGRect(origin: .zero, size: size), contentScaleFactor: scale,
                                            resourceCommandQueue: nil))
                                }
                                var freshList = DisplayList()
                                freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: size)) {
                                    contents.draw(in: $0)
                                }
                                let fresh = try pixels(freshList, device: device,
                                    resources: host.rendererHost.sceneResources, scale: scale)
                                let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                                var localReference = DisplayList()
                                localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                    foreground: .color(.black),
                                    bounds: referenceValue.view.text.frame(in: referenceValue.size,
                                        renderer: referenceValue.view.renderer),
                                    seed: .init(), environment: environment)
                                let localExpected = try pixels(localReference, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale)
                                XCTAssertTrue(fresh == localExpected,
                                    "Fresh recording: \(mode) scale=\(scale) custom=\(custom) separator=\(separator.debugDescription) width=\(width) tail=\(tail.debugDescription)")
                                if custom {
                                    XCTAssertGreaterThan(capture.draws, 0)
                                    XCTAssertGreaterThan(referenceCapture.draws, 0)
                                    XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == truncated })
                                    XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTailTokenRunAttributesReachDrawingAndReplay() throws {
        // ASSERTIONS textTailTokenAttributes27Observed
        // ASSERTIONS textTailLineMetricRetention27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for mixedFont in [false, true] {
                            for mixedColor in [false, true] {
                                let proposals: [(CGFloat, CGFloat, Int)] = mixedFont
                                    ? [(66, 60, 1), (80, 60, 1), (80, 40, 2)] : [(66, 60, 1)]
                                for (width, height, limit) in proposals {
                                    let secondSize: CGFloat = mixedFont ? 31 : 23
                                    let tokenSize: CGFloat = custom || width == 66 ? 23 : secondSize
                                    let baseline: CGFloat = mixedFont && limit == 1 ? 29 : 21
                                    let baselineShift = CGPoint(x: 0, y: baseline - (tokenSize == 31 ? 29 : 21))
                                    let firstColor: VUI.Color = mixedColor ? .red : .black
                                    let secondColor: VUI.Color = mixedColor ? .blue : .black
                                    let tokenColor = custom || (mixedFont && width == 66) ? firstColor : secondColor
                                    let label = "\(mode) scale=\(scale) custom=\(custom) mixedFont=\(mixedFont) mixedColor=\(mixedColor) width=\(width) limit=\(limit)"
                                    let request = CGSize(width: width, height: height)
                                    let capture = FittingTextCapture()
                                    let value = Text(verbatim: "AAA ").font(.file(file, size: 23)).foregroundColor(firstColor)
                                        + Text(verbatim: "BBB BBB").font(.file(file, size: secondSize)).foregroundColor(secondColor)
                                    let content = custom
                                        ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                                    let host = ForegroundTextHost(content.lineLimit(limit).minimumScaleFactor(1)
                                        .environment(\.defaultFontRenderingMode, mode)
                                        .frame(width: request.width, height: request.height, alignment: .topLeading)
                                        .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                                    let list = try host.list()
                                    let owner: ResolvedStyledText
                                    if custom {
                                        owner = try XCTUnwrap(capture.owner)
                                    } else {
                                        owner = try XCTUnwrap(textValues(list).first?.view.text as? ResolvedStyledText.StringDrawing)
                                    }
                                    let metrics = owner.metrics(in: request, layoutMargins: nil)
                                    XCTAssertEqual(textValues(list).map(\.size), [metrics.size])
                                    XCTAssertEqual(metrics.scale, 1)
                                    XCTAssertEqual(metrics.numberOfLines, 1)
                                    XCTAssertEqual(metrics.firstBaseline, baseline)
                                    XCTAssertEqual(metrics.size.height, baseline == 29 ? 37 : 27)
                                    XCTAssertEqual(metrics.hasTruncatedRanges, true)
                                    let referenceCapture = FittingTextCapture()
                                    let referenceText = Text(verbatim: "AAA").font(.file(file, size: 23)).foregroundColor(firstColor)
                                        + Text(verbatim: "…").font(.file(file, size: tokenSize)).foregroundColor(tokenColor)
                                    let referenceContent = custom
                                        ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture)))
                                        : AnyView(referenceText)
                                    let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                        .environment(\.defaultFontRenderingMode, mode)
                                        .frame(width: ceil(request.width), height: request.height, alignment: .topLeading)
                                        .frame(width: size.width, height: size.height, alignment: .topLeading), scale: scale)
                                    let referenceList = try reference.list()
                                    let expected = try pixels(referenceList, device: device,
                                        resources: reference.rendererHost.sceneResources, scale: scale, offset: baselineShift)
                                    XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 })
                                    for replay in [false, true] {
                                        let actual = try pixels(list, device: device,
                                            resources: host.rendererHost.sceneResources, scale: scale, replay: replay)
                                        XCTAssertTrue(actual == expected,
                                            "\(label) replay=\(replay)")
                                    }
                                    var environment = EnvironmentValues()
                                    environment.displayScale = scale
                                    environment.defaultFontRenderingMode = mode
                                    let valueForRecording = try XCTUnwrap(textValues(list).first)
                                    let contents = host.graph.data.withCurrent {
                                        owner.makeRBDisplayList(for: metrics.size, renderer: valueForRecording.view.renderer,
                                            deviceScale: scale, environment: environment,
                                            inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                                viewport: CGRect(origin: .zero, size: size), contentScaleFactor: scale,
                                                resourceCommandQueue: nil))
                                    }
                                    var freshList = DisplayList()
                                    freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: size)) {
                                        contents.draw(in: $0)
                                    }
                                    let fresh = try pixels(freshList, device: device,
                                        resources: host.rendererHost.sceneResources, scale: scale)
                                    let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                                    var localReference = DisplayList()
                                    localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                        foreground: .color(.black),
                                        bounds: referenceValue.view.text.frame(in: referenceValue.size,
                                            renderer: referenceValue.view.renderer),
                                        seed: .init(), environment: environment)
                                    let localExpected = try pixels(localReference, device: device,
                                        resources: reference.rendererHost.sceneResources, scale: scale, offset: baselineShift)
                                    XCTAssertTrue(fresh == localExpected,
                                        "Fresh recording: \(label)")
                                    if custom {
                                        XCTAssertGreaterThan(capture.draws, 0)
                                        XCTAssertGreaterThan(referenceCapture.draws, 0)
                                        XCTAssertTrue(capture.truncationStates.allSatisfy { $0 })
                                        XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testDecoratedTailTokensPreserveBitmapVectorRecording() throws {
        // ASSERTIONS textTailDecorationAttributes27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let canvas = CGSize(width: 256, height: 100)
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            let cases: [(String, String, String, CGFloat)] = ["underline", "strikethrough"].flatMap { kind in
                [(kind, "first", "", 80), (kind, "second", "", 80),
                 (kind, "both", "\n", 80), (kind, "first", "\n", 190),
                 (kind, "second", "\u{2028}", 190), (kind, "both", "\u{2028}", 240)]
            } + [("none", "first", "", 80), ("none", "both", "\n", 240)]
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for (kind, scope, separator, width) in cases {
                            let label = "\(kind) \(scope) \(separator.debugDescription) width=\(width) custom=\(custom) \(mode) scale=\(scale)"
                            let kept = width == 80 ? 3 : 11
                            let firstToken = width == 80 ? custom : width == 190
                            let baseline: CGFloat = !custom && !separator.isEmpty && width == 80
                                ? 21 : 29
                            func run(_ string: String, first: Bool, decorated: Bool = true) -> Text {
                                let value = Text(verbatim: string).font(.file(file, size: first ? 23 : 31))
                                    .foregroundColor(first ? .red : .blue)
                                guard decorated, kind != "none", scope == "both" || (scope == "first") == first else { return value }
                                return kind == "underline" ? value.underline() : value.strikethrough()
                            }
                            var value = run("AAA ", first: true) + run("BBB BBB", first: false)
                            if !separator.isEmpty {
                                value = value + run(separator, first: false) + Text(verbatim: "CCC").font(.file(file, size: 17))
                            }
                            var referenceText = run("AAA ", first: true, decorated: false)
                                + run("BBB BBB", first: false, decorated: false)
                            if !separator.isEmpty {
                                referenceText = referenceText + run(separator, first: false, decorated: false)
                                    + Text(verbatim: "CCC").font(.file(file, size: 17))
                            }
                            let capture = FittingTextCapture()
                            let referenceCapture = FittingTextCapture()
                            let content = custom ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                            let referenceContent = custom
                                ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture))) : AnyView(referenceText)
                            let request = CGSize(width: width, height: 60)
                            let host = ForegroundTextHost(content.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: 60, alignment: .topLeading)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: 60, alignment: .topLeading)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let list = try host.list()
                            let referenceList = try reference.list()
                            let plain = try pixels(referenceList, device: device, resources: reference.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            let direct = try pixels(list, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            XCTAssertTrue(stride(from: 3, to: direct.count, by: 4).contains { direct[$0] > 0 }, label)
                            let hasDecoration = kind != "none" && (scope != "second" || kept == 11 || !firstToken)
                            XCTAssertEqual(direct != plain, hasDecoration, label)
                            let replay = try pixels(list, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, replay: true, canvasSize: canvas)
                            XCTAssertTrue(replay == direct, "Retained recording: \(label)")
                            let textValue = try XCTUnwrap(textValues(list).first)
                            let owner: ResolvedStyledText = custom ? try XCTUnwrap(capture.owner) : textValue.view.text
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(textValue.size, metrics.size, label)
                            XCTAssertEqual(metrics.firstBaseline, baseline, label)
                            var environment = EnvironmentValues()
                            environment.displayScale = scale
                            environment.defaultFontRenderingMode = mode
                            let contents = host.graph.data.withCurrent {
                                owner.makeRBDisplayList(for: metrics.size, renderer: textValue.view.renderer,
                                    deviceScale: scale, environment: environment,
                                    inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                        viewport: CGRect(origin: .zero, size: canvas), contentScaleFactor: scale,
                                        resourceCommandQueue: nil))
                            }
                            var freshList = DisplayList()
                            freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: canvas)) { contents.draw(in: $0) }
                            let fresh = try pixels(freshList, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            var localReference = DisplayList()
                            localReference.appendTextItem(textValue.view, size: textValue.size, foreground: .color(.black),
                                bounds: textValue.view.text.frame(in: textValue.size, renderer: textValue.view.renderer),
                                seed: .init(), environment: environment)
                            let localExpected = try pixels(localReference, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            XCTAssertTrue(fresh == localExpected, "Fresh recording: \(label)")
                            if custom {
                                XCTAssertGreaterThan(capture.draws, 0)
                                XCTAssertGreaterThan(referenceCapture.draws, 0)
                                XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == (kept < 11) }, label)
                                XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { $0 == (kept < 11) }, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testBaselineOffsetTailTokensReachBitmapVectorDrawingAndReplay() throws {
        // ASSERTIONS textTailBaselineAttributes27Observed
        // ASSERTIONS textTailBaselineMetrics27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let canvas = CGSize(width: 256, height: 100)
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            let cases: [(CGFloat, String, String, CGFloat)] = [
                (-3, "first", "", 80), (3, "first", "", 80),
                (-3, "second", "", 80), (3, "second", "", 80),
                (-3, "both", "\n", 80), (3, "both", "\n", 80),
                (-3, "first", "\n", 190), (3, "first", "\n", 190),
                (-3, "second", "\u{2028}", 190), (3, "second", "\u{2028}", 190),
                (-3, "both", "\u{2028}", 240), (3, "both", "\u{2028}", 240),
                (0, "first", "", 80), (0, "both", "\n", 240)
            ]
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for (offset, scope, separator, width) in cases {
                            let label = "offset=\(offset) \(scope) \(separator.debugDescription) width=\(width) custom=\(custom) \(mode) scale=\(scale)"
                            let kept = width == 80 ? 3 : 11
                            let firstToken = width == 80 ? custom : width == 190
                            let firstOffset: CGFloat = scope == "second" ? 0 : offset
                            let secondOffset: CGFloat = scope == "first" ? 0 : offset
                            let baseline: CGFloat = !custom && !separator.isEmpty && width == 80
                                ? 21 + max(firstOffset, 0) : 29 + max(secondOffset, 0)
                            let referenceBaseline: CGFloat = kept == 3 && firstToken
                                ? 21 + max(firstOffset, 0) : 29 + max(secondOffset, 0)
                            let baselineShift = CGPoint(x: 0, y: baseline - referenceBaseline)
                            func run(_ string: String, first: Bool) -> Text {
                                let value = Text(verbatim: string).font(.file(file, size: first ? 23 : 31))
                                    .foregroundColor(first ? .red : .blue)
                                return (first && scope == "second") || (!first && scope == "first")
                                    ? value : value.baselineOffset(offset)
                            }
                            var value = run("AAA ", first: true) + run("BBB BBB", first: false)
                            if !separator.isEmpty {
                                value = value + run(separator, first: false) + Text(verbatim: "CCC").font(.file(file, size: 17))
                            }
                            let referenceText = run(String("AAA ".prefix(min(kept, 4))), first: true)
                                + run(String("BBB BBB".prefix(max(kept - 4, 0))), first: false)
                                + run("…", first: firstToken)
                            let capture = FittingTextCapture()
                            let referenceCapture = FittingTextCapture()
                            let content = custom ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                            let referenceContent = custom
                                ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture))) : AnyView(referenceText)
                            let request = CGSize(width: width, height: 60)
                            let host = ForegroundTextHost(content.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: 60, alignment: .topLeading)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let list = try host.list()
                            let referenceList = try reference.list()
                            let expected = try pixels(referenceList, device: device, resources: reference.rendererHost.sceneResources,
                                scale: scale, offset: baselineShift, canvasSize: canvas)
                            XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 }, label)
                            for replay in [false, true] {
                                let actual = try pixels(list, device: device, resources: host.rendererHost.sceneResources,
                                    scale: scale, replay: replay, canvasSize: canvas)
                                XCTAssertTrue(actual == expected, "\(label) replay=\(replay)")
                            }
                            let textValue = try XCTUnwrap(textValues(list).first)
                            let owner: ResolvedStyledText = custom ? try XCTUnwrap(capture.owner) : textValue.view.text
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(textValue.size, metrics.size, label)
                            XCTAssertEqual(metrics.firstBaseline, baseline, label)
                            var environment = EnvironmentValues()
                            environment.displayScale = scale
                            environment.defaultFontRenderingMode = mode
                            let contents = host.graph.data.withCurrent {
                                owner.makeRBDisplayList(for: metrics.size, renderer: textValue.view.renderer,
                                    deviceScale: scale, environment: environment,
                                    inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                        viewport: CGRect(origin: .zero, size: canvas), contentScaleFactor: scale,
                                        resourceCommandQueue: nil))
                            }
                            var freshList = DisplayList()
                            freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: canvas)) { contents.draw(in: $0) }
                            let fresh = try pixels(freshList, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                            var localReference = DisplayList()
                            localReference.appendTextItem(referenceValue.view, size: referenceValue.size, foreground: .color(.black),
                                bounds: referenceValue.view.text.frame(in: referenceValue.size, renderer: referenceValue.view.renderer),
                                seed: .init(), environment: environment)
                            let localExpected = try pixels(localReference, device: device, resources: reference.rendererHost.sceneResources,
                                scale: scale, offset: baselineShift, canvasSize: canvas)
                            XCTAssertTrue(fresh == localExpected, "Fresh recording: \(label)")
                            if custom {
                                XCTAssertGreaterThan(capture.draws, 0)
                                XCTAssertGreaterThan(referenceCapture.draws, 0)
                                XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == (kept < 11) }, label)
                                XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 }, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTrackedTailWidthsPreserveBitmapVectorDrawingAndReplay() throws {
        // ASSERTIONS textTailAdjustedAdvance27Observed
        // ASSERTIONS textTailTokenSpacing27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let canvas = CGSize(width: 256, height: 100)
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            let cases: [(String, String, String, CGFloat)] = [
                ("tracking", "both", "", 189.5), ("tracking", "both", "\n", 190),
                ("tracking", "both", "\u{2028}", 240), ("tracking", "first", "\n", 190),
                ("tracking", "second", "\u{2028}", 190), ("tracking", "both", "\n", 80),
                ("tracking", "both", "", 98.2685546875), ("tracking", "both", "\n", 98.2683546875),
                ("kern", "both", "", 98.2685546875),
                ("tracking", "first", "\n", 198), ("tracking", "both", "\u{2028}", 208)
            ]
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for (kind, scope, separator, width) in cases {
                            let label = "\(kind) \(scope) \(separator.debugDescription) width=\(width) custom=\(custom) \(mode) scale=\(scale)"
                            let noToken = width == 189.5
                            let replacementOnly = width == 198 || width == 208
                            let kept = noToken || replacementOnly || width == 240 ? 11 : width == 190 ? (scope == "both" ? 9 : 10)
                                : width == 80 || kind == "kern" || (width == 98.2683546875 && !custom) ? 3 : 5
                            let firstToken = replacementOnly || (custom && kept == 3) || (!custom && scope != "both")
                            let tokenSize: CGFloat = firstToken ? 23 : 31
                            let baseline: CGFloat = !custom && !separator.isEmpty && width < 100 ? 21 : 29
                            let baselineShift = CGPoint(x: 0, y: baseline - (kept > 4 || tokenSize == 31 ? 29 : 21))
                            func run(_ string: String, first: Bool) -> Text {
                                let value = Text(verbatim: string).font(.file(file, size: first ? 23 : 31))
                                    .foregroundColor(first ? .red : .blue)
                                let amount: CGFloat = (first && scope == "second") || (!first && scope == "first") ? 0 : 1.5
                                return kind == "kern" ? value.kerning(amount) : value.tracking(amount)
                            }
                            var value = run("AAA ", first: true) + run("BBB BBB", first: false)
                            if !separator.isEmpty {
                                value = value + run(separator, first: false) + Text(verbatim: "CCC").font(.file(file, size: 17))
                            }
                            var referenceText = run(String("AAA ".prefix(min(kept, 4))), first: true)
                                + run(String("BBB BBB".prefix(max(kept - 4, 0))), first: false)
                            if !noToken { referenceText = referenceText + run("…", first: firstToken) }
                            let capture = FittingTextCapture()
                            let referenceCapture = FittingTextCapture()
                            let content = custom ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                            let referenceContent = custom
                                ? AnyView(referenceText.textRenderer(FittingTextRenderer(capture: referenceCapture))) : AnyView(referenceText)
                            let request = CGSize(width: width, height: 60)
                            let host = ForegroundTextHost(content.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: width, height: 60, alignment: .topLeading)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let reference = ForegroundTextHost(referenceContent.lineLimit(1).minimumScaleFactor(1)
                                .environment(\.defaultFontRenderingMode, mode)
                                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                            let list = try host.list()
                            let referenceList = try reference.list()
                            let expected = try pixels(referenceList, device: device, resources: reference.rendererHost.sceneResources,
                                scale: scale, offset: baselineShift, canvasSize: canvas)
                            XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains { expected[$0] > 0 }, label)
                            for replay in [false, true] {
                                let actual = try pixels(list, device: device, resources: host.rendererHost.sceneResources,
                                    scale: scale, replay: replay, canvasSize: canvas)
                                XCTAssertTrue(actual == expected, "\(label) replay=\(replay)")
                            }
                            let textValue = try XCTUnwrap(textValues(list).first)
                            let owner: ResolvedStyledText = custom ? try XCTUnwrap(capture.owner) : textValue.view.text
                            let metrics = owner.metrics(in: request, layoutMargins: nil)
                            XCTAssertEqual(textValue.size, metrics.size, label)
                            XCTAssertEqual(metrics.firstBaseline, baseline, label)
                            var environment = EnvironmentValues()
                            environment.displayScale = scale
                            environment.defaultFontRenderingMode = mode
                            let contents = host.graph.data.withCurrent {
                                owner.makeRBDisplayList(for: metrics.size, renderer: textValue.view.renderer,
                                    deviceScale: scale, environment: environment,
                                    inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                        viewport: CGRect(origin: .zero, size: canvas), contentScaleFactor: scale,
                                        resourceCommandQueue: nil))
                            }
                            var freshList = DisplayList()
                            freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: canvas)) { contents.draw(in: $0) }
                            let fresh = try pixels(freshList, device: device, resources: host.rendererHost.sceneResources,
                                scale: scale, canvasSize: canvas)
                            let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                            var localReference = DisplayList()
                            localReference.appendTextItem(referenceValue.view, size: referenceValue.size, foreground: .color(.black),
                                bounds: referenceValue.view.text.frame(in: referenceValue.size, renderer: referenceValue.view.renderer),
                                seed: .init(), environment: environment)
                            let localExpected = try pixels(localReference, device: device, resources: reference.rendererHost.sceneResources,
                                scale: scale, offset: baselineShift, canvasSize: canvas)
                            XCTAssertTrue(fresh == localExpected, "Fresh recording: \(label)")
                            if custom {
                                XCTAssertGreaterThan(capture.draws, 0)
                                XCTAssertGreaterThan(referenceCapture.draws, 0)
                                XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == (kept < 11) }, label)
                                XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 }, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testExplicitLineTailTokensReachDrawingAndReplay() throws {
        // ASSERTIONS textTailEmptyRangeLookup27Observed
        // ASSERTIONS textTailTokenEmptyRangeAttributes27Observed
        try withDevice { device in
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
            let canvas = CGSize(width: 256, height: 100)
            func textValues(_ list: DisplayList) -> [DisplayList.Content.TextValue] {
                list.items.flatMap { item -> [DisplayList.Content.TextValue] in
                    switch item.value {
                    case let .content(content):
                        if case let .text(text) = content.value { return [text] }
                        if case let .flattened(child, _, _) = content.value { return textValues(child) }
                    case let .effect(_, child): return textValues(child)
                    default: break
                    }
                    return []
                }
            }
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for custom in [false, true] {
                        for separator in ["\n", "\u{2028}"] {
                            for (sample, width, kept): (String, CGFloat, Int) in [
                                ("mixed", 185, 10), ("mixed", 190, 11), ("mixed", 240, 11),
                                ("uniform", 150, 10), ("prefix", 185, 10), ("one", 20, 0)
                            ] {
                                let one = sample == "one"
                                let hasPrefix = sample == "prefix"
                                let limit = hasPrefix ? 2 : 1
                                let secondSize: CGFloat = sample == "uniform" || one ? 23 : 31
                                let firstAttributes = one || width == 190 || (!custom && width != 240)
                                let tokenSize: CGFloat = firstAttributes ? 23 : secondSize
                                let tokenColor: VUI.Color = firstAttributes ? .red : .blue
                                let label = "\(sample) width=\(width) custom=\(custom) \(separator.debugDescription) \(mode) scale=\(scale)"
                                let request = CGSize(width: width, height: hasPrefix ? 100 : 60)
                                var value = Text(verbatim: one ? "A" : "AAA ").font(.file(file, size: 23)).foregroundColor(.red)
                                if !one {
                                    value = value + Text(verbatim: "BBB BBB").font(.file(file, size: secondSize)).foregroundColor(.blue)
                                }
                                value = value + Text(verbatim: separator).font(.file(file, size: secondSize)).foregroundColor(.blue)
                                    + Text(verbatim: "CCC").font(.file(file, size: 17))
                                let referenceText = Text(verbatim: one ? "" : "AAA ").font(.file(file, size: 23)).foregroundColor(.red)
                                    + Text(verbatim: String("BBB BBB".prefix(max(kept - 4, 0))))
                                        .font(.file(file, size: secondSize)).foregroundColor(.blue)
                                    + Text(verbatim: "…").font(.file(file, size: tokenSize)).foregroundColor(tokenColor)
                                var expectedText = referenceText
                                if hasPrefix {
                                    let prefix = Text(verbatim: "CCC" + separator).font(.file(file, size: 17)).foregroundColor(.green)
                                    value = prefix + value
                                    expectedText = prefix + expectedText
                                }
                                let capture = FittingTextCapture()
                                let referenceCapture = FittingTextCapture()
                                let content = custom ? AnyView(value.textRenderer(FittingTextRenderer(capture: capture))) : AnyView(value)
                                let referenceContent = custom
                                    ? AnyView(expectedText.textRenderer(FittingTextRenderer(capture: referenceCapture))) : AnyView(expectedText)
                                let host = ForegroundTextHost(content.lineLimit(limit).minimumScaleFactor(1)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: request.width, height: request.height, alignment: .topLeading)
                                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                                let reference = ForegroundTextHost(referenceContent.lineLimit(limit).minimumScaleFactor(1)
                                    .environment(\.defaultFontRenderingMode, mode)
                                    .frame(width: request.width, height: request.height, alignment: .topLeading)
                                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading), scale: scale, size: canvas)
                                let list = try host.list()
                                let referenceList = try reference.list()
                                let expected = try pixels(referenceList, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale, canvasSize: canvas)
                                let pixelWidth = Int(canvas.width * scale)
                                XCTAssertTrue(stride(from: 3, to: expected.count, by: 4).contains {
                                    expected[$0] > 0 && (one || ($0 / 4) % pixelWidth >= Int(128 * scale))
                                }, label)
                                for replay in [false, true] {
                                    let actual = try pixels(list, device: device, resources: host.rendererHost.sceneResources,
                                        scale: scale, replay: replay, canvasSize: canvas)
                                    XCTAssertTrue(actual == expected, "\(label) replay=\(replay)")
                                }
                                let textValue = try XCTUnwrap(textValues(list).first)
                                let owner: ResolvedStyledText = custom ? try XCTUnwrap(capture.owner) : textValue.view.text
                                let metrics = owner.metrics(in: request, layoutMargins: nil)
                                XCTAssertEqual(textValue.size, metrics.size, label)
                                var environment = EnvironmentValues()
                                environment.displayScale = scale
                                environment.defaultFontRenderingMode = mode
                                let contents = host.graph.data.withCurrent {
                                    owner.makeRBDisplayList(for: metrics.size, renderer: textValue.view.renderer,
                                        deviceScale: scale, environment: environment,
                                        inputs: .init(sceneResources: host.rendererHost.sceneResources,
                                            viewport: CGRect(origin: .zero, size: canvas), contentScaleFactor: scale,
                                            resourceCommandQueue: nil))
                                }
                                var freshList = DisplayList()
                                freshList.appendTextItem(foreground: .color(.black), bounds: CGRect(origin: .zero, size: canvas)) {
                                    contents.draw(in: $0)
                                }
                                let fresh = try pixels(freshList, device: device, resources: host.rendererHost.sceneResources,
                                    scale: scale, canvasSize: canvas)
                                let referenceValue = try XCTUnwrap(textValues(referenceList).first)
                                var localReference = DisplayList()
                                localReference.appendTextItem(referenceValue.view, size: referenceValue.size,
                                    foreground: .color(.black),
                                    bounds: referenceValue.view.text.frame(in: referenceValue.size, renderer: referenceValue.view.renderer),
                                    seed: .init(), environment: environment)
                                let localExpected = try pixels(localReference, device: device,
                                    resources: reference.rendererHost.sceneResources, scale: scale, canvasSize: canvas)
                                XCTAssertTrue(fresh == localExpected, "Fresh recording: \(label)")
                                if custom {
                                    XCTAssertGreaterThan(capture.draws, 0)
                                    XCTAssertGreaterThan(referenceCapture.draws, 0)
                                    XCTAssertTrue(capture.truncationStates.allSatisfy { $0 == (kept < (one ? 1 : 11)) })
                                    XCTAssertTrue(referenceCapture.truncationStates.allSatisfy { !$0 })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS textFontWidthHost27Observed
    // ASSERTIONS viewFontWidthEnvironment27Observed
    func testFontWidthReachesMountedBitmapAndVectorDrawingAtBothScales() throws {
        try withDevice { device in
            let font = VUI.Font.system(size: 23)
            let text = Text(verbatim: "Hg0123")
            let controls: [(AnyView, VUI.Font)] = [
                (AnyView(text.fontWidth(.condensed)), font.width(.condensed)),
                (AnyView(text.fontWidth(.condensed).fontWidth(.expanded)), font.width(.condensed)),
                (AnyView(text.fontWidth(nil).fontWidth(.condensed)), font),
                (AnyView(AnyView(text).fontWidth(.condensed).fontWidth(.expanded)), font.width(.condensed)),
                (AnyView(AnyView(text).fontWidth(nil).fontWidth(.expanded)), font),
                (AnyView(AnyView(text.fontWidth(nil)).fontWidth(.condensed)), font),
                (AnyView(AnyView(text).fontWidth(nil).fontWidth(.expanded).font(font.width(.condensed))), font.width(.condensed)),
                (AnyView(text.fontWidth(.standard).font(font.width(.condensed))), font)
            ]
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for scale: CGFloat in [1, 2] {
                    for (view, expectedFont) in controls {
                        let host = ForegroundTextHost(view.font(font)
                            .environment(\.defaultFontRenderingMode, mode), scale: scale)
                        let reference = ForegroundTextHost(text.font(expectedFont)
                            .environment(\.defaultFontRenderingMode, mode), scale: scale)
                        let actual = try pixels(host.list(), device: device, resources: host.rendererHost.sceneResources, scale: scale)
                        let expected = try pixels(reference.list(), device: device, resources: reference.rendererHost.sceneResources, scale: scale)
                        XCTAssertTrue(stride(from: 3, to: actual.count, by: 4).contains { actual[$0] > 0 })
                        XCTAssertEqual(actual, expected)
                    }
                }
            }
        }
    }

    // ASSERTIONS textFontWidthHost27Observed
    func testChangingViewWidthInvalidatesTheMountedTextResolution() throws {
        try withDevice { device in
            let text = Text(verbatim: "Hg0123")
            let font = VUI.Font.system(size: 23)
            func content(_ width: VUI.Font.Width?) -> some View {
                AnyView(text).fontWidth(width).fontWidth(.condensed).font(font)
                    .environment(\.defaultFontRenderingMode, .vector())
            }
            var environment = EnvironmentValues()
            environment.displayScale = 2
            let renderer = TestViewRendererHost()
            let graph = ViewGraph(replaceableContent: content(.condensed), rendererHost: renderer,
                initialEnvironment: environment)
            renderer.storage = graph
            graph.setSize(size)
            let values: [VUI.Font.Width?] = [.condensed, nil, .standard, .expanded, .condensed, nil]
            for (index, width) in values.enumerated() {
                try graph.data.withCurrent {
                    try XCTUnwrap(graph.rootAnyViewContentInput).setValue(AnyView(content(width)))
                }
                graph.updateOutputs(at: Time(seconds: Double(index)))
                let list = try graph.data.withCurrent { try XCTUnwrap(graph.displayList()) }
                let actual = try pixels(list, device: device, resources: renderer.sceneResources, scale: 2)
                let reference = ForegroundTextHost(text.font(font.width(width ?? .standard))
                    .environment(\.defaultFontRenderingMode, .vector()), scale: 2)
                let expected = try pixels(reference.list(), device: device, resources: reference.rendererHost.sceneResources, scale: 2)
                XCTAssertEqual(actual, expected)
            }
        }
    }

    private func resolvedStyle<S: ShapeStyle>(_ style: S) throws -> _ShapeStyle_Pack.Style {
        var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1), environment: .init())
        style._apply(to: &shape)
        guard case let .pack(pack) = shape.result else { throw XCTUnwrapError.missingStyle }
        return try XCTUnwrap(pack.styles.first?.style)
    }
    private enum XCTUnwrapError: Error { case missingStyle }

    private func withDevice(_ body: (GraphicsDeviceContext) throws -> Void) throws {
        #if canImport(Metal)
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        try body(device)
        #else
        throw XCTSkip("Metal is required for this rendering fixture")
        #endif
    }

    private func drawingInputs(_ host: ForegroundTextHost) -> GraphicsContext.DrawingInputs {
        .init(sceneResources: host.rendererHost.sceneResources, viewport: CGRect(origin: .zero, size: size),
            contentScaleFactor: 1, resourceCommandQueue: nil)
    }

    private func pixels(_ list: DisplayList, device: GraphicsDeviceContext, resources: SceneResources,
                        scale: CGFloat = 1, replay: Bool = false, offset: CGPoint = .zero,
                        canvasSize: CGSize? = nil) throws -> [UInt8] {
        let size = canvasSize ?? self.size
        let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
        let resolution = CGSize(width: size.width * scale, height: size.height * scale)
        var context = try XCTUnwrap(GraphicsContext(sceneResources: resources, environment: .init(),
            viewport: CGRect(origin: .zero, size: resolution), contentOffset: .zero, contentScaleFactor: scale,
            resolution: resolution, commandBuffer: commands))
        context.clear(with: .clear)
        context.translateBy(x: offset.x, y: offset.y)
        if replay {
            let recording = context.recordingContext(size: size)
            list.draw(in: recording)
            try XCTUnwrap(recording.recording).draw(in: context)
        } else {
            list.draw(in: context)
        }
        let done = expectation(description: "foreground readback")
        commands.addCompletedHandler { _ in done.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [done], timeout: 15)
        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()), count: Int(resolution.width * resolution.height) * 4))
    }

    private func drawingContents(in list: DisplayList) -> [(any RBDisplayListContents, RasterizationOptions)] {
        var result: [(any RBDisplayListContents, RasterizationOptions)] = []
        for item in list.items {
            switch item.value {
            case let .content(content):
                if case let .drawing(contents, _, options) = content.value { result.append((contents, options)) }
                if case let .flattened(child, _, _) = content.value { result += drawingContents(in: child) }
            case let .effect(effect, child):
                result += drawingContents(in: child)
                if case let .mask(mask, _) = effect { result += drawingContents(in: mask) }
            default: break
            }
        }
        return result
    }
}

private final class FittingTextCapture {
    weak var owner: ResolvedStyledText.TextLayoutManager?
    var draws = 0
    var truncationStates: [Bool] = []
    var lineWidths: [[CGFloat]] = []
}

private struct FittingTextRenderer: TextRenderer {
    let capture: FittingTextCapture
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        capture.owner = Mirror(reflecting: text).children.first?.value as? ResolvedStyledText.TextLayoutManager
        return text.sizeThatFits(proposal)
    }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        capture.draws += 1
        capture.truncationStates.append(layout.isTruncated)
        capture.lineWidths.append(layout.map { $0.typographicBounds.width })
        for line in layout { context.draw(line) }
    }
}

private final class ForegroundRecordingRenderer: TextRendererBoxBase {
    let values: EnvironmentValues
    var draws = 0
    init(values: EnvironmentValues) { self.values = values }
    override var environment: EnvironmentValues { values }
    override var displayPadding: EdgeInsets { .init() }
    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect { CGRect(origin: .zero, size: size) }
    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        draws += 1
        for line in layout { context.draw(line) }
        context.fill(Path(CGRect(x: 3, y: 50, width: 6, height: 6)), with: .color(.green))
    }
}

private final class ForegroundTextHost {
    let rendererHost = TestViewRendererHost()
    let graph: ViewGraph
    init<V: View>(_ view: V, scale: CGFloat = 1, size: CGSize = CGSize(width: 128, height: 80)) {
        var environment = EnvironmentValues()
        environment.displayScale = scale
        graph = ViewGraph(rootViewType: V.self, content: view, rendererHost: rendererHost, initialEnvironment: environment)
        rendererHost.storage = graph
        graph.setSize(size)
    }
    func list() throws -> DisplayList {
        graph.updateOutputs(at: .zero)
        return try graph.data.withCurrent { try XCTUnwrap(graph.displayList()) }
    }
}
