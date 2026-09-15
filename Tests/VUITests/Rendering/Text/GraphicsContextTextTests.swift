import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextTextTests: XCTestCase {
    // ASSERTIONS textParagraphDirectionalAlignmentAggregationObserved
    func testCanvasPreservesLogicalAndExplicitPhysicalAlignment() throws {
        try withContext { original in
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                for alignment: TextAlignment in [.leading, .center, .trailing] {
                    var context = original
                    context.environment.layoutDirection = direction
                    context.environment.multilineTextAlignment = alignment
                    let plain = context.resolve(Text(verbatim: "HHH\nH"))
                    XCTAssertEqual(plain.resolved.layoutProperties.multilineTextAlignment, alignment)
                    XCTAssertEqual(plain.resolved.layoutProperties.layoutDirection, direction)
                    for (physical, expected): (TextParagraphAlignment, TextAlignment) in [
                        (.left, direction == .leftToRight ? .leading : .trailing), (.center, .center),
                        (.right, direction == .leftToRight ? .trailing : .leading)
                    ] {
                        var attributed = AttributedString("HHH\nH")
                        attributed[TextParagraphAlignmentAttribute.self] = physical
                        let text = context.resolve(Text(attributed))
                        XCTAssertEqual(text.resolved.layoutProperties.multilineTextAlignment, expected)
                        XCTAssertEqual(text.resolved.layoutProperties.layoutDirection, direction)
                    }
                }
            }
        }
    }

    // ASSERTIONS textStringDrawingDrawGeometryObserved textStringDrawingRequestedDrawingWidthObserved
    func testDrawingBoundsKeepTheMeasurementProposalAndCachedWidthSeparate() throws {
        try withContext { context in
            let owner = try XCTUnwrap(context.resolve(Text(verbatim: "HHH")).resolved as? ResolvedStyledText.StringDrawing)
            owner.layoutMargins = .init(top: 1.25, leading: 2.5, bottom: 3.75, trailing: 4.5)
            owner.layoutProperties.bodyHeadOutdent = 6
            let metrics = owner.cachedMetrics(in: CGSize(width: 300, height: 81))
            let request = CGSize(width: 100, height: 60)
            let rect = CGRect(x: 32.25, y: 32.25, width: 1000, height: 1000)
            let ordinary = owner.drawingBounds(in: rect, with: request, applyingMarginOffsets: false)
            XCTAssertEqual(ordinary.origin.x, 32.25)
            XCTAssertEqual(ordinary.origin.y, 32.25 + metrics.baselineAdjustment)
            XCTAssertEqual(ordinary.size.width, metrics.size.width + 6)
            XCTAssertEqual(ordinary.size.height, metrics.size.height)
            XCTAssertEqual(ordinary, owner.drawingBounds(in: CGRect(origin: rect.origin, size: .zero),
                                                        with: request, applyingMarginOffsets: false))
            let inset = owner.drawingBounds(in: rect, with: request, applyingMarginOffsets: true)
            XCTAssertEqual(inset.origin.x - ordinary.origin.x, owner.drawingMargins.leading)
            XCTAssertEqual(inset.origin.y - ordinary.origin.y, owner.drawingMargins.top)
            XCTAssertEqual(ordinary.size.width - inset.size.width, 7)
            XCTAssertEqual(ordinary.size.height - inset.size.height, 5)
            owner.layoutProperties.hyphenationFactor = 0.7
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                owner.layoutProperties.layoutDirection = direction
                for alignment: TextAlignment in [.leading, .center, .trailing] {
                    owner.layoutProperties.multilineTextAlignment = alignment
                    for margins in [false, true] {
                        let drawing = owner.drawingBounds(in: rect, with: request, applyingMarginOffsets: margins)
                        let reference = margins ? inset : ordinary
                        XCTAssertEqual(drawing.size.width, 299)
                        XCTAssertEqual(drawing.origin.y, reference.origin.y)
                        XCTAssertEqual(drawing.size.height, reference.size.height)
                        if alignment == .center { XCTAssertEqual(drawing.midX, reference.midX) }
                        else if (alignment == .leading) == (direction == .leftToRight) {
                            XCTAssertEqual(drawing.minX, reference.minX)
                        } else { XCTAssertEqual(drawing.maxX, reference.maxX) }
                    }
                }
            }
            XCTAssertEqual(owner.cachedMetrics(in: request).requestedWidth, 299)
            XCTAssertEqual(owner.metricsCacheEntryCount, 1)
        }
    }

    // ASSERTIONS textStringDrawingResolvableLayoutGateObserved
    func testResolvableDrawingKeepsTheOwnersPreparedLayoutAndMeasurements() throws {
        XCTAssertNil(ResolvedStyledText.StringDrawing().prepareDrawing(in: .zero, with: .zero,
                                                                      applyingMarginOffsets: false))
        try withContext { context in
            let owner = try XCTUnwrap(context.resolve(Text(verbatim: "HHH\nH")).resolved as? ResolvedStyledText.StringDrawing)
            let request = CGSize(width: 160, height: 81)
            let measurement = owner.cachedMetrics(in: request)
            let cache = try XCTUnwrap(owner.preparedLayout)
            let rect = CGRect(x: 12, y: 7, width: 160, height: 81)
            let ordinary = try XCTUnwrap(owner.prepareDrawing(in: rect, with: request, applyingMarginOffsets: false))
            for flag in [true, false, true] {
                let drawing = try XCTUnwrap(owner.prepareDrawing(in: rect, with: request,
                    applyingMarginOffsets: false, containsResolvable: flag))
                XCTAssertEqual(drawing.bounds, ordinary.bounds)
                XCTAssertEqual(drawing.lines.map(\.width), ordinary.lines.map(\.width))
                XCTAssertEqual(drawing.lines.map(\.baseline), ordinary.lines.map(\.baseline))
                XCTAssertTrue(owner.preparedLayout === cache)
                XCTAssertEqual(owner.cachedMetrics(in: request).size, measurement.size)
                XCTAssertEqual(owner.metricsCacheEntryCount, 1)
            }
        }
    }

    // ASSERTIONS canvasTextForegroundKeyColorObserved
    func testCanvasForegroundOptionsReachNestedAttributedAndLocalizedRuns() throws {
        try withContext { context in
            let red = Color(.sRGB, red: 1, green: 0, blue: 0)
            var attributed = AttributedString("H")
            attributed.foregroundColor = red
            attributed.append(AttributedString("H"))
            let samples: [(Text, [Bool])] = [
                (Text(verbatim: "H"), [true]),
                (Text(verbatim: "H").foregroundColor(nil), [true]),
                (Text(verbatim: "H").foregroundColor(red), [false]),
                ((Text(verbatim: "H") + Text(verbatim: "H").foregroundColor(nil)).foregroundColor(red), [false, true]),
                (Text(verbatim: "H") + Text(verbatim: "H").foregroundColor(red) + Text(verbatim: "H"), [true, false, true]),
                (Text(attributed), [false, true]),
                (Text("\(Text(verbatim: "H").foregroundColor(red))\(Text(verbatim: "H"))"), [false, true])
            ]
            for (text, expected) in samples {
                let canvas = context.resolve(text)
                let source = try XCTUnwrap(canvas.resolved.resolvedText)
                let colors = try source.runs.map { run -> VUI.Color.Resolved in
                    guard case let .styledText(_, _, _, attributes) = run else {
                        throw NSError(domain: "Expected a styled text run", code: 1)
                    }
                    return try XCTUnwrap(attributes.foregroundColor).resolve(in: context.environment)
                }
                XCTAssertEqual(colors.map { $0.linearRed == -1 && $0.linearGreen == -1 && $0.linearBlue == -1 }, expected)
                XCTAssertEqual(canvas.resolved.features.contains(.keyColor), expected.contains(true))
                XCTAssertTrue(canvas.resolved.styles.isEmpty)
                XCTAssertEqual(canvas.resolved.needsStyledRendering, expected.contains(true))
                for (color, key) in zip(colors, expected) where !key {
                    XCTAssertEqual(color, red.resolve(in: context.environment))
                }
                let attributes = try XCTUnwrap(canvas.resolved.storage)
                var storedColors: [VUI.Color.Resolved] = []
                attributes.enumerateAttributes(in: NSRange(location: 0, length: attributes.length)) { values, _, _ in
                    if let color = values[.coreForegroundColor] as? VUI.Color {
                        storedColors.append(color.resolve(in: context.environment))
                    }
                }
                XCTAssertEqual(storedColors, colors)
            }
            let plain = Text(verbatim: "H")
            let ordinary = plain._resolve(context: context)
            XCTAssertFalse(ordinary.resolvedFeatures.contains(.keyColor))
            let empty = context.resolve(Text(verbatim: ""))
            XCTAssertTrue(empty.resolved.features.contains(.keyColor))
            XCTAssertTrue(empty.resolved.resolvedText?.runs.isEmpty == true)
            var properties = Text.ResolvedProperties()
            let omitted = Text.Style().nsAttributes(in: context.environment, properties: &properties,
                options: .foregroundKeyColor, includeDefaultAttributes: false)
            XCTAssertNil(omitted.foregroundColor)
            XCTAssertFalse(properties.features.contains(.keyColor))
            var explicit = Text.Style()
            explicit.color = .explicit(AnyShapeStyle(red))
            let included = explicit.nsAttributes(in: context.environment, properties: &properties,
                options: .foregroundKeyColor, includeDefaultAttributes: false)
            XCTAssertEqual(included.foregroundColor?.resolve(in: context.environment), red.resolve(in: context.environment))
            var environment = context.environment
            environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(red))
            explicit.color = .explicit(AnyShapeStyle(EmptyTextStyle()))
            let fallback = explicit.nsAttributes(in: environment, properties: &properties, options: .foregroundKeyColor)
            XCTAssertEqual(fallback.foregroundColor?.resolve(in: environment), red.resolve(in: environment))
        }
    }

    // ASSERTIONS canvasResolvedTextOwnerDispatchObserved textStringDrawingKitCacheOwnershipObserved
    // ASSERTIONS textStringDrawingMetricsCacheReuseObserved textStringDrawingCountConsumerObserved
    func testCopiesShareTheOwnerAndSeparateResolvesKeepIndependentCaches() throws {
        try withContext { context in
            let text = Text(verbatim: "A A A A A A")
            let original = context.resolve(text)
            let independent = context.resolve(text)
            let owner = try XCTUnwrap(original.resolved as? ResolvedStyledText.StringDrawing)
            let other = try XCTUnwrap(independent.resolved as? ResolvedStyledText.StringDrawing)
            XCTAssertEqual(Mirror(reflecting: original).children.compactMap(\.label), ["resolved", "shared", "shading"])
            XCTAssertTrue(original.shared === context.storage.shared)
            XCTAssertTrue(independent.shared === original.shared)
            XCTAssertFalse(owner === other)
            XCTAssertEqual(owner.metricsCacheEntryCount, 0)
            XCTAssertNil(owner.preparedLayout)
            let request = CGSize(width: 300, height: 81)
            let measured = original.measure(in: request)
            XCTAssertEqual(owner.metricsCacheEntryCount, 1)
            let prepared = try XCTUnwrap(owner.preparedLayout)
            var copy = original
            copy.shading = .color(.red)
            XCTAssertTrue(copy.resolved === owner)
            XCTAssertTrue(copy.shared === original.shared)
            if case let .color(color) = copy.shading.properties.first { XCTAssertEqual(color, .red) }
            else { XCTFail("Expected copied shading") }
            if case .foreground = original.shading.properties.first { }
            else { XCTFail("Expected original foreground shading") }
            XCTAssertEqual(copy.measure(in: measured), measured)
            XCTAssertEqual(copy.firstBaseline(in: request), original.firstBaseline(in: request))
            XCTAssertEqual(copy.lastBaseline(in: request), original.lastBaseline(in: request))
            XCTAssertEqual(owner.metricsCacheEntryCount, 1)
            XCTAssertNil(owner.cachedMetrics(in: request).numberOfLines)
            _ = owner.textSizeCacheMetrics(in: request)
            XCTAssertEqual(owner.metricsCacheEntryCount, 2)
            XCTAssertNil(owner.cachedMetrics(in: request).numberOfLines)
            let narrow = copy.measure(in: CGSize(width: 50, height: 81))
            XCTAssertGreaterThan(narrow.height, measured.height)
            XCTAssertTrue(owner.preparedLayout === prepared)
            XCTAssertEqual(other.metricsCacheEntryCount, 0)
            XCTAssertNil(other.preparedLayout)
            XCTAssertEqual(independent.measure(in: request), measured)
            XCTAssertFalse(other.preparedLayout === prepared)
        }
    }

    // ASSERTIONS canvasResolvedTextOwnerDispatchObserved textStringDrawingCacheInvalidationObserved
    // ASSERTIONS textStringDrawingScaleOverrideReconstructionObserved
    func testOverrideResetsAreSharedAndDoNotRetainTheOwnerThroughItsSource() throws {
        try withContext { context in
            var original: GraphicsContext.ResolvedText? = context.resolve(Text(verbatim: "A"))
            var copy = original
            let independent = context.resolve(Text(verbatim: "A"))
            weak var owner = original?.resolved as? ResolvedStyledText.StringDrawing
            let request = CGSize(width: 300, height: 81)
            let natural = try XCTUnwrap(original?.measure(in: request))
            XCTAssertEqual(independent.measure(in: request), natural)
            weak var prepared = owner?.preparedLayout
            for scale: CGFloat? in [0.5, 0.5, 0.75, 1, nil] {
                owner?.scaleFactorOverride = scale
                XCTAssertNil(prepared)
                XCTAssertEqual(owner?.metricsCacheEntryCount, 0)
                XCTAssertEqual(original?.measure(in: request), copy?.measure(in: request))
                XCTAssertEqual(original?.firstBaseline(in: request), copy?.firstBaseline(in: request))
                XCTAssertEqual(original?.lastBaseline(in: request), copy?.lastBaseline(in: request))
                XCTAssertEqual(owner?.metricsCacheEntryCount, 1)
                XCTAssertEqual(independent.measure(in: request), natural)
                prepared = owner?.preparedLayout
            }
            XCTAssertEqual(copy?.measure(in: request), natural)
            original = nil
            XCTAssertNotNil(owner)
            copy = nil
            XCTAssertNil(owner)
            XCTAssertNil(prepared)
        }
    }

    // ASSERTIONS canvasResolvedTextOwnerDispatchObserved textStringDrawingMultilineFittingObserved
    func testCanvasConsumesLayoutInputsAndMeasuresZeroProposalsThroughTheOwner() throws {
        try withContext { original in
            var context = original
            var environment = context.environment
            environment.lineLimit = 2
            environment.minimumScaleFactor = 0.25
            context.environment = environment
            let text = context.resolve(Text(verbatim: "A A A A A A"))
            let owner = try XCTUnwrap(text.resolved as? ResolvedStyledText.StringDrawing)
            XCTAssertEqual(owner.layoutProperties.lineLimit, 2)
            XCTAssertEqual(owner.layoutProperties.minScaleFactor, 0.25)
            XCTAssertFalse(owner.layoutProperties.sizeFitting)
            let request = CGSize(width: 50, height: 81)
            let size = text.measure(in: request)
            XCTAssertEqual(size.height, 48)
            XCTAssertEqual(owner.drawingSource(in: request)?.uniformFont?.pointSize, 20.25)
            XCTAssertEqual(text.firstBaseline(in: request), owner.cachedMetrics(in: request).firstBaseline)
            XCTAssertEqual(owner.metricsCacheEntryCount, 1)
            for value in ["", "A", "\n\n", "A\n"] {
                let zero = original.resolve(Text(verbatim: value))
                XCTAssertGreaterThan(zero.measure(in: .zero).height, 0, value.debugDescription)
                _ = zero.firstBaseline(in: .zero)
                _ = zero.lastBaseline(in: .zero)
                XCTAssertEqual(zero.resolved.metricsCacheEntryCount, 1)
            }
        }
    }

    private func withContext(_ body: (GraphicsContext) throws -> Void) throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = CanvasTextTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 23)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(x: 0, y: 0, width: 128, height: 128),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 128, height: 128), commandBuffer: commands))
        try body(context)
    }
}

private struct EmptyTextStyle: ShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape) {}
    static func _apply(to type: inout _ShapeStyle_ShapeType) {}
}

private final class CanvasTextTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    init(graphicsDeviceContext: GraphicsDeviceContext) { self.graphicsDeviceContext = graphicsDeviceContext }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
