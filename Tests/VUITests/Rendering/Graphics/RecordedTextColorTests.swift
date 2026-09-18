import XCTest
import VVD
@testable import VUI

final class RecordedTextColorTests: XCTestCase {
    private final class DrawCounter {
        var count = 0
    }

    private final class Attachment: AnyCustomTextAttachment {
        let counter: DrawCounter
        init(counter: DrawCounter) { self.counter = counter }

        override func draw(with bounds: Text.Layout.TypographicBounds, in context: inout GraphicsContext) {
            counter.count += 1
            context.fill(Path(bounds.rect), with: .color(.sRGBLinear, red: -1, green: -1, blue: 0))
        }
    }

    private let wildcard: Float = -32768
    private let size = CGSize(width: 128, height: 64)

    private func device() throws -> GraphicsDeviceContext {
        #if canImport(Metal)
        return try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        #else
        throw XCTSkip("Metal is required for the current drawing fixture")
        #endif
    }

    private func context(_ device: GraphicsDeviceContext) throws -> GraphicsContext {
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        environment.font = .system(size: 20)
        return try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(origin: .zero, size: size), contentOffset: .zero,
            contentScaleFactor: 1, resolution: size, commandBuffer: commands))
    }

    private func render(_ device: GraphicsDeviceContext, _ draw: (inout GraphicsContext) -> Void) throws -> [UInt8] {
        var context = try context(device)
        context.clear(with: .clear)
        draw(&context)
        let finished = expectation(description: "recorded color rendering")
        context.commandBuffer.addCompletedHandler { _ in finished.fulfill() }
        XCTAssertTrue(context.commandBuffer.commit())
        wait(for: [finished], timeout: 10)
        let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(buffer.contents())
        return Array(UnsafeRawBufferPointer(start: pointer, count: Int(size.width * size.height) * 4))
    }

    private func predicate(_ color: SIMD4<Float>) -> RBDisplayListPredicate {
        let predicate = RBDisplayListPredicate()
        predicate.addCondition(fillColor: color, colorSpace: .linearSRGB)
        return predicate
    }

    private func recording(_ context: GraphicsContext) -> RBMovedDisplayListContents {
        let recorded = context.recordingContext(size: size)
        for i in 0..<4 {
            recorded.fill(Path(CGRect(x: i * 20, y: 0, width: 10, height: 10)),
                with: .color(.sRGBLinear, red: -1, green: -1, blue: Double(i) / 1024))
        }
        return recorded.recording!.moveContents()
    }

    // ASSERTIONS recordedColorPredicate27Observed
    // ASSERTIONS recordedColorOperationOwnership27Observed
    func testPredicateSelectionCompositionAndCopyRetainNativeValueSemantics() throws {
        let context = try context(device())
        let source = recording(context)
        for i in 0..<4 {
            let predicate = predicate(SIMD4(-1, -1, Float(i) / 1024, wildcard))
            let selected = predicate.copyFilteredDisplayList(source)
            XCTAssertEqual(selected.boundingRect, CGRect(x: i * 20, y: 0, width: 10, height: 10))
            predicate.invertsResult = true
            let copy = try XCTUnwrap(predicate.copy() as? RBDisplayListPredicate)
            XCTAssertFalse(copy.invertsResult)
            predicate.removeAll()
            XCTAssertTrue(predicate.copyFilteredDisplayList(source).isEmpty)
            XCTAssertEqual(recordedItems(in: copy.copyFilteredDisplayList(source)).count, 3)
            copy.invertsResult = true
            XCTAssertEqual(copy.copyFilteredDisplayList(source).boundingRect, selected.boundingRect)
        }
        let parent = RBDisplayListPredicate()
        let child = predicate(SIMD4(-1, -1, 0, wildcard))
        parent.addPredicate(child)
        child.removeAll()
        XCTAssertEqual(recordedItems(in: parent.copyFilteredDisplayList(source)).count, 1)
        parent.addCondition(fillColor: SIMD4(-1, -1, 1 / 1024, wildcard), colorSpace: .linearSRGB)
        let empty = parent.copyFilteredDisplayList(source)
        XCTAssertTrue(empty is RBEmptyDisplayListContents)
        XCTAssertTrue(empty.boundingRect.isNull)
        XCTAssertEqual(source.items.count, 4)
    }

    // ASSERTIONS recordedColorPredicate27Observed
    func testColorSpaceConversionAndHalfToleranceKeepAdjacentKeysSeparate() {
        let pattern = RecordedColor(SIMD4(-1, -1, 0, wildcard), colorSpace: .linearSRGB)
        for (value, expected): (Float, Bool) in [(0, true), (0.0019, true), (0.00195, true), (0.00197, false)] {
            XCTAssertEqual(pattern.matches(RecordedColor(SIMD4(-1, -1, value, 1), colorSpace: .sRGB)), expected)
        }
        let one = RecordedColor(Color.Resolved(colorSpace: .sRGBLinear, red: -1, green: -1, blue: 1 / 1024))
        XCTAssertEqual(one.components.z, 0.0126190185546875)
        XCTAssertFalse(pattern.matches(one))
    }

    // ASSERTIONS recordedColorReplacement27Observed
    // ASSERTIONS recordedColorOperationOwnership27Observed
    func testReplacementAlphaAndOrderedCopiesPreserveOriginalPixels() throws {
        let device = try device()
        let context = try context(device)
        let record = context.recordingContext(size: size)
        record.fill(Path(CGRect(x: 2, y: 2, width: 10, height: 10)),
            with: .color(.sRGBLinear, red: -1, green: -1, blue: 1 / 1024, opacity: 0.25))
        let source = record.recording!.moveContents()
        let original = try render(device) { source.draw(in: $0) }
        for (fromAlpha, expected): (Float, Double) in [(wildcard, 0.125), (0.25, 0.5)] {
            let transform = RBDisplayListTransform()
            transform.addColorReplacement(from: SIMD4(-1, -1, 1 / 1024, fromAlpha),
                to: SIMD4(1, 0, 0, 0.5), colorSpace: .linearSRGB)
            let changed = transform.copyApplyingToDisplayList(source)
            let pixels = try render(device) { changed.draw(in: $0) }
            let reference = try render(device) {
                $0.fill(Path(CGRect(x: 2, y: 2, width: 10, height: 10)),
                    with: .color(.sRGBLinear, red: 1, green: 0, blue: 0, opacity: expected))
            }
            XCTAssertEqual(pixels, reference)
            transform.removeAll()
            XCTAssertEqual(try render(device) { changed.draw(in: $0) }, reference)
            XCTAssertEqual(try render(device) { transform.copyApplyingToDisplayList(source).draw(in: $0) }, original)
        }
        let transform = RBDisplayListTransform()
        transform.addColorReplacement(from: SIMD4(-1, -1, wildcard, wildcard),
            to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let copy = try XCTUnwrap(transform.copy() as? RBDisplayListTransform)
        transform.addColorReplacement(from: SIMD4(1, 0, 0, wildcard),
            to: SIMD4(0, 1, 0, 1), colorSpace: .linearSRGB)
        XCTAssertEqual(recordedItems(in: transform.copyApplyingToDisplayList(source))[0].color?.components, SIMD4(0, 1, 0, 0.25))
        XCTAssertEqual(recordedItems(in: copy.copyApplyingToDisplayList(source))[0].color?.components, SIMD4(1, 0, 0, 0.25))
        XCTAssertEqual(try render(device) { source.draw(in: $0) }, original)
    }

    // ASSERTIONS textRecordedLayerBoundaryObserved
    // ASSERTIONS textMixedRecordingPartitionObserved
    func testWholeLayerSelectionAndSavedClipSurviveReplacementAndRerecording() throws {
        let device = try device()
        let context = try context(device)
        var record = context.recordingContext(size: size)
        record.clip(to: Path(CGRect(x: 4, y: 0, width: 16, height: 20)))
        record.drawLayer { layer in
            layer.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(.sRGBLinear, red: -1, green: -1, blue: 0))
            layer.fill(Path(CGRect(x: 10, y: 0, width: 10, height: 10)), with: .color(.sRGBLinear, red: 0, green: 1, blue: 0))
        }
        let source = record.recording!.moveContents()
        let predicate = predicate(SIMD4(-1, -1, 0, wildcard))
        let selected = predicate.copyFilteredDisplayList(source)
        XCTAssertEqual(try render(device) { selected.draw(in: $0) }, try render(device) { source.draw(in: $0) })
        predicate.invertsResult = true
        XCTAssertTrue(predicate.copyFilteredDisplayList(source).isEmpty)
        let transform = RBDisplayListTransform()
        transform.addColorReplacement(from: SIMD4(-1, -1, 0, wildcard), to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let changed = transform.copyApplyingToDisplayList(selected)
        let expected = try render(device) { changed.draw(in: $0) }
        XCTAssertTrue(expected.contains { $0 != 0 })
        let rerecorded = context.recordingContext(size: size)
        changed.draw(in: rerecorded)
        XCTAssertEqual(try render(device) { rerecorded.recording!.draw(in: $0) }, expected)
    }

    // ASSERTIONS textMixedRecordingPartitionObserved
    // ASSERTIONS recordedTextColorOperands27Observed
    // ASSERTIONS canvasRecordedPayloadLifetimeObserved
    func testMixedTextRecordsIndependentGeometryAndReleasesPreparedOwner() throws {
        let device = try device()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            var context = try context(device)
            context.environment.defaultFontRenderingMode = mode
            let text = Text(verbatim: "AA").foregroundColor(Color(.sRGBLinear, red: -1, green: -1, blue: 0)) +
                Text(verbatim: "BB").foregroundColor(Color(.sRGBLinear, red: -1, green: -1, blue: 1 / 1024)) +
                Text(verbatim: "CC").foregroundColor(.green).underline(color: .blue)
            let resolved = context.resolve(text)
            let frame = CGRect(x: 2, y: 3, width: 100, height: 40)
            let prepared = try XCTUnwrap(resolved.resolved.prepareDrawing(in: frame, with: frame.size, applyingMarginOffsets: false))
            var drawing: ResolvedTextSource.Drawing? = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
            weak let weakDrawing = drawing
            let record = context.recordingContext(size: size)
            record.draw(drawing!, in: prepared.bounds, shading: .foreground, snapOrigin: false, clipBounds: false)
            let saved = record.recording!.moveContents()
            XCTAssertGreaterThanOrEqual(saved.items.count, 4)
            let selected = predicate(SIMD4(-1, -1, 0, wildcard)).copyFilteredDisplayList(saved)
            XCTAssertEqual(recordedItems(in: selected).count, 1)
            XCTAssertLessThan(selected.boundingRect.maxX, saved.boundingRect.maxX)
            let transform = RBDisplayListTransform()
            transform.addColorReplacement(from: SIMD4(-1, -1, 0, wildcard), to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
            let changed = transform.copyApplyingToDisplayList(selected)
            let before = try render(device) { changed.draw(in: $0) }
            XCTAssertTrue(before.contains { $0 != 0 })
            drawing!.batches.removeAll()
            drawing!.vectorBatches.removeAll()
            drawing!.decorations.removeAll()
            drawing = nil
            XCTAssertNil(weakDrawing)
            XCTAssertEqual(try render(device) { changed.draw(in: $0) }, before)
        }
    }

    // ASSERTIONS recordedColorPredicate27Observed
    func testGradientForegroundResolvesBeforeFilteringAndIsNotAColor() throws {
        var context = try context(device())
        context.environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(
            LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)))
        let record = context.recordingContext(size: size)
        record.fill(Path(CGRect(x: 0, y: 0, width: 20, height: 20)), with: .foreground)
        let saved = record.recording!.moveContents()
        let predicate = predicate(SIMD4(repeating: wildcard))
        XCTAssertTrue(predicate.copyFilteredDisplayList(saved).isEmpty)
        predicate.invertsResult = true
        XCTAssertEqual(recordedItems(in: predicate.copyFilteredDisplayList(saved)).count, 1)
        XCTAssertNil(saved.items[0].color)
    }

    // ASSERTIONS textMixedRecordingPartitionObserved
    // ASSERTIONS textSuffixCustomAttachmentObserved
    // ASSERTIONS canvasRecordedPayloadLifetimeObserved
    func testCustomAttachmentCommandsKeepOrderWithoutRetainingOrRepeatingCallback() throws {
        let device = try device()
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let context = try context(device)
        let frame = CGRect(x: 160, y: 3, width: 100, height: 40)
        let recordingSize = CGSize(width: 280, height: 64)
        let resolved = context.resolve(Text(verbatim: "A").foregroundColor(.green))
        let prepared = try XCTUnwrap(resolved.resolved.prepareDrawing(in: frame, with: frame.size, applyingMarginOffsets: false))
        var drawing: ResolvedTextSource.Drawing? = prepared.source.makeDrawing(lineGlyphs: prepared.lines)
        let counter = DrawCounter()
        var attachment: Attachment? = Attachment(counter: counter)
        weak let weakAttachment = attachment
        var bounds = Text.Layout.TypographicBounds()
        bounds.origin = CGPoint(x: 40, y: 20)
        bounds.width = 10
        bounds.ascent = 10
        drawing!.customAttachments = [.init(attachment: attachment!, bounds: bounds)]
        drawing!.backgrounds = [.init(frame: CGRect(x: 0, y: 0, width: 60, height: 30), color: .yellow)]
        drawing!.decorations = [.init(start: .zero, end: CGPoint(x: 60, y: 0), lineWidth: 1,
            lineStyle: .single, foregroundColor: .blue)]
        let record = context.recordingContext(size: recordingSize)
        record.draw(drawing!, in: frame, shading: .foreground, snapOrigin: false)
        let saved = record.recording!.moveContents()
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(saved.items.count, 4)
        guard case let .text(first, _) = saved.items.first?.contents,
              case .background = first.contents,
              case .fill = saved.items[2].contents,
              case let .text(last, _) = saved.items.last?.contents,
              case .decoration = last.contents else {
            return XCTFail("Background, glyph, attachment and decoration commands must retain draw order")
        }
        drawing = nil
        attachment = nil
        XCTAssertNil(weakAttachment)
        let selected = predicate(SIMD4(-1, -1, 0, wildcard)).copyFilteredDisplayList(saved)
        XCTAssertEqual(recordedItems(in: selected).count, 1)
        let transform = RBDisplayListTransform()
        transform.addColorReplacement(from: SIMD4(-1, -1, 0, wildcard),
            to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let changed = transform.copyApplyingToDisplayList(selected)
        let expected = try render(device) {
            $0.translateBy(x: -158, y: 0)
            changed.draw(in: $0)
        }
        XCTAssertTrue(expected.contains { $0 != 0 })
        let rerecorded = context.recordingContext(size: recordingSize)
        changed.draw(in: rerecorded)
        XCTAssertEqual(try render(device) {
            $0.translateBy(x: -158, y: 0)
            rerecorded.recording!.draw(in: $0)
        }, expected)
        XCTAssertEqual(counter.count, 1)
    }

    // ASSERTIONS recordedNonColorImage27Observed
    func testTextureImageIsNotAColorAndKeepsOriginalPixels() throws {
        let device = try device()
        let context = try context(device)
        let queue = try XCTUnwrap(device.renderQueue())
        let bitmap = VVD.Image(width: 1, height: 1, pixelFormat: .rgba8, data: Data([0, 255, 0, 255]))
        let texture = try XCTUnwrap(bitmap.makeTexture(commandQueue: queue))
        let image = ImageDrawing(baseline: 1, shading: nil, texture: texture,
            textureTransform: .identity, scaleFactor: 1)
        let record = context.recordingContext(size: size)
        record.draw(image, in: CGRect(x: 2, y: 3, width: 10, height: 8))
        let saved = record.recording!.moveContents()
        let original = try render(device) { saved.draw(in: $0) }
        XCTAssertTrue(original.contains { $0 != 0 })
        let predicate = predicate(SIMD4(repeating: wildcard))
        XCTAssertTrue(predicate.copyFilteredDisplayList(saved).isEmpty)
        predicate.invertsResult = true
        let selected = predicate.copyFilteredDisplayList(saved)
        XCTAssertEqual(selected.boundingRect, saved.boundingRect)
        XCTAssertEqual(try render(device) { selected.draw(in: $0) }, original)
        let transform = RBDisplayListTransform()
        transform.addColorReplacement(from: SIMD4(repeating: wildcard),
            to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let changed = transform.copyApplyingToDisplayList(saved)
        XCTAssertEqual(changed.boundingRect, saved.boundingRect)
        XCTAssertEqual(try render(device) { changed.draw(in: $0) }, original)
    }
}
