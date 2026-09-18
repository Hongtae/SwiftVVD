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

    private func effectRecording(_ context: GraphicsContext,
                                 filters: [GraphicsContext.Filter], reversed: Bool = false,
                                 layer: Bool = false, inner: Bool = false) -> RBMovedDisplayListContents {
        var recorded = context.recordingContext(size: size)
        if !inner { for filter in filters { recorded.addFilter(filter) } }
        let shapes: (inout GraphicsContext) -> Void = { context in
            let colors: [VUI.Color] = [Color(.sRGBLinear, red: -1, green: -1, blue: 0),
                Color(.sRGBLinear, red: -1, green: -1, blue: 1 / 1024, opacity: 0.25), .cyan.opacity(0.6)]
            for i in reversed ? [2, 1, 0] : [0, 1, 2] {
                context.fill(Path(CGRect(x: 16 + i * 24, y: 16, width: 8, height: 8)), with: .color(colors[i]))
            }
        }
        if layer {
            recorded.drawLayer { child in
                if inner { for filter in filters { child.addFilter(filter) } }
                shapes(&child)
            }
        } else { shapes(&recorded) }
        return recorded.recording!.moveContents()
    }

    private func shadow(_ color: VUI.Color = .black.opacity(0.5),
                        options: GraphicsContext.ShadowOptions = []) -> GraphicsContext.Filter {
        .shadow(color: color, radius: 2, x: 3, y: 2, options: options)
    }

    private func assertBounds(_ actual: CGRect, _ expected: CGRect,
                              file: StaticString = #filePath, line: UInt = #line) {
        // Recorded effect geometry uses Float operands; aggregation is CGRect.
        for (a, b) in zip([actual.minX, actual.minY, actual.width, actual.height],
                          [expected.minX, expected.minY, expected.width, expected.height]) {
            XCTAssertEqual(a, b, accuracy: 0.00002, file: file, line: line)
        }
    }

    func testRecordedStyleHeadIsSharedUntilAStateCopyAddsAnEffect() throws {
        // ASSERTIONS recordedStyleProduction27Observed
        var record = try context(device()).recordingContext(size: size)
        record.addFilter(shadow())
        let style = try XCTUnwrap(record.storage.state.pointee.style)
        record.fill(Path(CGRect(x: 16, y: 16, width: 8, height: 8)), with: .color(.red))
        var branch = record
        branch.addFilter(.blur(radius: 2))
        branch.fill(Path(CGRect(x: 40, y: 16, width: 8, height: 8)), with: .color(.green))
        record.fill(Path(CGRect(x: 64, y: 16, width: 8, height: 8)), with: .color(.blue))
        let source = record.recording!.moveContents()
        XCTAssertTrue(record.storage.state.pointee.style === style)
        XCTAssertTrue(branch.storage.state.pointee.style?.next === style)
        XCTAssertTrue(source.items[0].state.style === source.items[2].state.style)
        XCTAssertTrue(source.items[1].state.style?.next === source.items[0].state.style)
        XCTAssertNil(style.next)
        XCTAssertEqual(source.items[0].state.filters.count, 1)
        XCTAssertEqual(source.items[1].state.filters.count, 2)
    }

    func testSharedStyleSelectionRetainsSourceOrderAndOperationScopedCopies() throws {
        // ASSERTIONS recordedEffectPartition27Observed
        // ASSERTIONS recordedStyleProduction27Observed
        let device = try device()
        let context = try context(device)
        let key = Color(.sRGBLinear, red: -1, green: -1, blue: 0, opacity: 0.5)
        let predicate = predicate(SIMD4(-1, -1, 0, wildcard))
        var originalPixels: [UInt8]?
        for reversed in [false, true] {
            let source = effectRecording(context, filters: [shadow(key)], reversed: reversed)
            let before = try render(device) { source.draw(in: $0) }
            if let originalPixels { XCTAssertEqual(before, originalPixels) }
            originalPixels = before
            let selected = predicate.copyFilteredDisplayList(source)
            let items = recordedItems(in: selected)
            XCTAssertEqual(items.count, 3)
            let copy = try XCTUnwrap(items[0].state.style as? RBDisplayList.ShadowStyle)
            XCTAssertEqual(copy.options.contains(.shadowOnly), reversed)
            XCTAssertTrue(items.allSatisfy { $0.state.style === copy })
            XCTAssertFalse(copy === source.items[0].state.style)
            XCTAssertEqual((source.items[0].state.style as? RBDisplayList.ShadowStyle)?.options, [])
            let another = recordedItems(in: predicate.copyFilteredDisplayList(source))
            XCTAssertFalse(another[0].state.style === copy)
            XCTAssertTrue(another.allSatisfy { $0.state.style === another[0].state.style })
            let expected = effectRecording(context, filters: [shadow(key, options: reversed ? .shadowOnly : [])], reversed: reversed)
            XCTAssertEqual(try render(device) { selected.draw(in: $0) },
                           try render(device) { expected.draw(in: $0) })
            XCTAssertEqual(try render(device) { source.draw(in: $0) }, before)
            weak var retiredStyle: RBDisplayList.Style?
            autoreleasepool {
                let retired = predicate.copyFilteredDisplayList(source)
                retiredStyle = recordedItems(in: retired)[0].state.style
                XCTAssertNotNil(retiredStyle)
            }
            XCTAssertNil(retiredStyle)
        }
    }

    func testBlackShadowSelectionSeparatesBodyFromStyleAndDropsCachedEmptyChains() throws {
        // ASSERTIONS recordedEffectPartition27Observed
        let device = try device()
        let context = try context(device)
        let plain = effectRecording(context, filters: [])
        let key = predicate(SIMD4(-1, -1, wildcard, wildcard))
        let black = predicate(SIMD4(0, 0, 0, wildcard))
        for options: GraphicsContext.ShadowOptions in [[], .shadowAbove, .shadowOnly, .disablesGroup] {
            let source = effectRecording(context, filters: [shadow(options: options)])
            let selectedKeys = key.copyFilteredDisplayList(source)
            XCTAssertEqual(recordedItems(in: selectedKeys).count, 2)
            XCTAssertTrue(recordedItems(in: selectedKeys).allSatisfy { $0.state.style == nil })
            XCTAssertEqual(try render(device) { selectedKeys.draw(in: $0) },
                           try render(device) { key.copyFilteredDisplayList(plain).draw(in: $0) })
            let selectedShadow = black.copyFilteredDisplayList(source)
            let reference = effectRecording(context, filters: [shadow(options: options.union(.shadowOnly))])
            XCTAssertEqual(try render(device) { selectedShadow.draw(in: $0) },
                           try render(device) { reference.draw(in: $0) })
            black.invertsResult = true
            XCTAssertEqual(try render(device) { black.copyFilteredDisplayList(source).draw(in: $0) },
                           try render(device) { plain.draw(in: $0) })
            black.invertsResult = false
        }
    }

    func testEffectBoundsUseDistinctBlurAndShadowOutsetsAndSurviveSelection() throws {
        // ASSERTIONS recordedEffectBounds27Observed
        // ASSERTIONS recordedEffectPartition27Observed
        let device = try device()
        let context = try context(device)
        let key = predicate(SIMD4(-1, -1, 0, wildcard))
        let blur = effectRecording(context, filters: [.blur(radius: 2)])
        let selectedBlur = key.copyFilteredDisplayList(blur)
        assertBounds(selectedBlur.boundingRect, CGRect(x: 10, y: 10, width: 20, height: 20))
        assertBounds(effectRecording(context, filters: [.blur(radius: 0.75)]).boundingRect,
                     CGRect(x: 13, y: 13, width: 62, height: 14))
        assertBounds(effectRecording(context, filters: [shadow()]).boundingRect,
                     CGRect(x: 13.4, y: 12.4, width: 67.2, height: 19.2))
        assertBounds(effectRecording(context, filters: [.shadow(radius: 0, x: 12, y: 2)]).boundingRect,
                     CGRect(x: 16, y: 16, width: 68, height: 10))
        assertBounds(effectRecording(context, filters: [.shadow(radius: 0, x: 12, y: 2, options: .shadowOnly)]).boundingRect,
                     CGRect(x: 28, y: 18, width: 56, height: 8))
        for (index, filters) in [[GraphicsContext.Filter.blur(radius: 2), shadow()], [shadow(), .blur(radius: 2)]].enumerated() {
            let source = effectRecording(context, filters: filters)
            assertBounds(source.boundingRect, CGRect(x: 7.4, y: 6.4, width: 79.2, height: 31.2))
            XCTAssertEqual(source.boundingRect.minX, [7.399999618530273, 7.400000095367432][index], accuracy: 0.00000001)
            let selected = key.copyFilteredDisplayList(source)
            XCTAssertEqual(selected.boundingRect, selectedBlur.boundingRect)
            XCTAssertEqual(try render(device) { selected.draw(in: $0) },
                           try render(device) { selectedBlur.draw(in: $0) })
        }
    }

    func testLayerBodySelectionKeepsChildrenWhileCopyingTheirStyles() throws {
        // ASSERTIONS recordedEffectPartition27Observed
        // ASSERTIONS textRecordedLayerBoundaryObserved
        let device = try device()
        let context = try context(device)
        let key = predicate(SIMD4(-1, -1, 0, wildcard))
        let black = predicate(SIMD4(0, 0, 0, wildcard))
        let plain = effectRecording(context, filters: [], layer: true)
        for inner in [false, true] {
            let source = effectRecording(context, filters: [shadow()], layer: true, inner: inner)
            let selected = key.copyFilteredDisplayList(source)
            guard case let .layer(children, _) = recordedItems(in: selected).first?.contents else {
                return XCTFail("Selection must keep the ordinary layer owner")
            }
            XCTAssertEqual(children.items.count, 3)
            XCTAssertTrue(children.items.allSatisfy { $0.state.style == nil })
            XCTAssertNil(recordedItems(in: selected)[0].state.style)
            XCTAssertEqual(selected.boundingRect, plain.boundingRect)
            XCTAssertEqual(try render(device) { selected.draw(in: $0) },
                           try render(device) { plain.draw(in: $0) })
            if inner {
                XCTAssertEqual(try render(device) { black.copyFilteredDisplayList(source).draw(in: $0) },
                               try render(device) { source.draw(in: $0) })
            }
        }
    }

    func testReplacementCopiesSharedStylesWithoutReplacingShadowColor() throws {
        // ASSERTIONS recordedEffectReplacement27Observed
        let device = try device()
        let context = try context(device)
        let key = Color(.sRGBLinear, red: -1, green: -1, blue: 0, opacity: 0.5)
        let source = effectRecording(context, filters: [shadow(key)])
        let original = try render(device) { source.draw(in: $0) }
        let transform = RBDisplayListTransform()
        transform.addColorReplacement(from: SIMD4(-1, -1, 0, wildcard), to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let changed = transform.copyApplyingToDisplayList(source)
        let items = recordedItems(in: changed)
        let copied = try XCTUnwrap(items[0].state.style as? RBDisplayList.ShadowStyle)
        XCTAssertTrue(items.allSatisfy { $0.state.style === copied })
        XCTAssertFalse(copied === source.items[0].state.style)
        XCTAssertEqual(copied.color.components, (source.items[0].state.style as? RBDisplayList.ShadowStyle)?.color.components)
        XCTAssertEqual(items[0].color?.components, SIMD4(1, 0, 0, 1))
        XCTAssertEqual(try render(device) { source.draw(in: $0) }, original)
        transform.removeAll()
        transform.addColorReplacement(from: SIMD4(repeating: wildcard), to: SIMD4(1, 0, 0, 1), colorSpace: .linearSRGB)
        let shadowOnly = effectRecording(context, filters: [shadow(options: .shadowOnly)])
        XCTAssertEqual(try render(device) { transform.copyApplyingToDisplayList(shadowOnly).draw(in: $0) },
                       try render(device) { shadowOnly.draw(in: $0) })
    }

    func testRerecordingKeepsSharedStyleIdentityAndReceiverEffects() throws {
        // ASSERTIONS recordedStyleProduction27Observed
        // ASSERTIONS canvasRecordedItemReplayObserved
        let device = try device()
        let context = try context(device)
        let key = Color(.sRGBLinear, red: -1, green: -1, blue: 0, opacity: 0.5)
        let source = effectRecording(context, filters: [shadow(key)])
        for receiverBlur in [false, true] {
            var receiver = context.recordingContext(size: size)
            if receiverBlur { receiver.addFilter(.blur(radius: 2)) }
            source.draw(in: receiver)
            let rerecorded = receiver.recording!.moveContents()
            XCTAssertTrue(rerecorded.items.allSatisfy { $0.state.style === rerecorded.items[0].state.style })
            XCTAssertFalse(rerecorded.items[0].state.style === source.items[0].state.style)
            let expected = effectRecording(context, filters: receiverBlur ? [shadow(key), .blur(radius: 2)] : [shadow(key)])
            XCTAssertEqual(try render(device) { rerecorded.draw(in: $0) },
                           try render(device) { expected.draw(in: $0) })
            let predicate = predicate(SIMD4(-1, -1, 0, wildcard))
            XCTAssertEqual(try render(device) { predicate.copyFilteredDisplayList(rerecorded).draw(in: $0) },
                           try render(device) { predicate.copyFilteredDisplayList(expected).draw(in: $0) })
        }
    }

    func testExecutionOnlyFiltersKeepDirectAndRecordedReplayEquivalent() throws {
        let device = try device()
        let context = try context(device)
        let filters: [GraphicsContext.Filter] = [.colorMultiply(.green), .brightness(0.25)]
        let draw: (inout GraphicsContext) -> Void = { context in
            for filter in filters { context.addFilter(filter) }
            context.fill(Path(CGRect(x: 16, y: 16, width: 8, height: 8)), with: .color(.cyan.opacity(0.6)))
        }
        var record = context.recordingContext(size: size)
        draw(&record)
        let source = record.recording!.moveContents()
        let style = try XCTUnwrap(source.items[0].state.style)
        XCTAssertTrue(style is RBDisplayList.ExecutionFilterStyle)
        XCTAssertFalse(style.supportsColorOperations)
        let expected = try render(device, draw)
        XCTAssertTrue(expected.contains { $0 != 0 })
        XCTAssertEqual(try render(device) { source.draw(in: $0) }, expected)
        let receiver = context.recordingContext(size: size)
        source.draw(in: receiver)
        XCTAssertEqual(try render(device) { receiver.recording!.draw(in: $0) }, expected)
    }
}
