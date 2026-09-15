import Foundation
import XCTest
import VVD
@testable import VUI

final class GraphicsContextTextTests: XCTestCase {
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
            if case let .color(color) = original.shading.properties.first { XCTAssertEqual(color, .black) }
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

private final class CanvasTextTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    init(graphicsDeviceContext: GraphicsDeviceContext) { self.graphicsDeviceContext = graphicsDeviceContext }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
