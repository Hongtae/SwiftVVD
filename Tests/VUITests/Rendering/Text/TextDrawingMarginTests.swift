import Foundation
import XCTest
import VVD
@testable import VUI

final class TextDrawingMarginTests: XCTestCase {
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
                        let styled = ResolvedStyledText(resolvedText: source)
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
        let styled = ResolvedStyledText(stylePadding: EdgeInsets(top: 2, leading: 3, bottom: 1, trailing: 4), resolvedText: source)
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
            let styled = ResolvedStyledText(stylePadding: EdgeInsets(top: 2, leading: 3, bottom: 1, trailing: 4), resolvedText: source)
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
    init(environment: EnvironmentValues, operation: Operation) { values = environment; self.operation = operation }
    override var environment: EnvironmentValues { values }
    override var displayPadding: EdgeInsets { EdgeInsets() }
    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect { CGRect(origin: .zero, size: size) }
    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {
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
