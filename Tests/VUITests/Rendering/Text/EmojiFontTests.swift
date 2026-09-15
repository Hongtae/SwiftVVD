import XCTest
import Dispatch
import Synchronization
import VVD
@testable import VUI

final class EmojiFontTests: XCTestCase {
    private func font(_ name: String, size: CGFloat = 48) throws -> VVD.Font {
        let url = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID(name), locale: Locale(identifier: "en")
        )?.url)
        let font = try XCTUnwrap(VVD.Font(path: url.path))
        font.setPointSize(size, dpi: (72, 72))
        return font
    }

    private func bitmap(_ font: VVD.Font, text: String) throws -> (bytes: [UInt8], info: VVD.Font.BitmapInfo) {
        let shaped = try XCTUnwrap(font.shape(text))
        let visible = shaped.glyphs.filter { $0.advance.width > 0 }
        XCTAssertEqual(visible.count, 1, text)
        XCTAssertEqual(visible.first?.sourceRange, 0..<text.unicodeScalars.count, "\(font.familyName): \(text)")
        let index = try XCTUnwrap(visible.first?.index)
        var result: ([UInt8], VVD.Font.BitmapInfo)?
        XCTAssertTrue(font.withGlyphBitmap(at: index, embolden: 0, outline: 0) { bytes, _, info, _ in
            result = (bytes, info)
        })
        return try XCTUnwrap(result)
    }

    func testColorFormatsRenderSkinToneAndJoinedGlyphs() throws {
        for family in ["NotoColorEmoji", "NotoColorEmojiBitmap"] {
            let face = try font(family)
            XCTAssertTrue(face.hasColor)
            let neutral = try bitmap(face, text: "👍")
            var variants: Set<Data> = []
            for value in ["👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"] {
                let value = try bitmap(face, text: value)
                XCTAssertEqual(value.info.pixelMode, .bgra)
                XCTAssertEqual(value.bytes.count, Int(value.info.width * value.info.rows) * 4)
                XCTAssertNotEqual(value.bytes, neutral.bytes)
                variants.insert(Data(value.bytes))
                for offset in stride(from: 0, to: value.bytes.count, by: 4) {
                    let alpha = Int(value.bytes[offset + 3])
                    XCTAssertLessThanOrEqual(Int(value.bytes[offset]), alpha + 1)
                    XCTAssertLessThanOrEqual(Int(value.bytes[offset + 1]), alpha + 1)
                    XCTAssertLessThanOrEqual(Int(value.bytes[offset + 2]), alpha + 1)
                }
            }
            XCTAssertEqual(variants.count, 5)
            for value in ["😀", "👩🏽‍💻", "🇰🇷", "1️⃣", "❤️"] {
                let value = try bitmap(face, text: value)
                XCTAssertTrue(value.bytes.contains { $0 != 0 })
            }
            // The reusable paint context must not retain a previous glyph's output.
            XCTAssertEqual(try bitmap(face, text: "👍").bytes, neutral.bytes)
        }
    }

    func testFixedStrikeScalesWithoutResamplingItsPixels() throws {
        let face = try font("NotoColorEmojiBitmap", size: 17)
        XCTAssertFalse(face.isScalable)
        let first = try bitmap(face, text: "😀")
        let scale = face.bitmapScale
        XCTAssertGreaterThan(scale, 0)
        XCTAssertLessThan(scale, 1)
        face.setPointSize(34, dpi: (72, 72))
        XCTAssertEqual(face.bitmapScale, scale * 2, accuracy: 0.000001)
        XCTAssertEqual(try bitmap(face, text: "😀").bytes, first.bytes)
        face.setPointSize(17, dpi: (144, 144))
        XCTAssertEqual(face.bitmapScale, scale * 2, accuracy: 0.000001)
    }

    func testScalableColorGlyphUsesRequestedRasterSize() throws {
        let face = try font("NotoColorEmoji", size: 24)
        XCTAssertTrue(face.isScalable)
        XCTAssertEqual(face.bitmapScale, 1)
        let small = try bitmap(face, text: "😀")
        face.setPointSize(48, dpi: (72, 72))
        let large = try bitmap(face, text: "😀")
        XCTAssertEqual(Double(large.info.width), Double(small.info.width) * 2, accuracy: 2)
        XCTAssertEqual(Double(large.info.rows), Double(small.info.rows) * 2, accuracy: 2)
        XCTAssertGreaterThan(large.bytes.count, small.bytes.count)
    }

    func testDisablingColorRetainsThePaintedAlphaMask() throws {
        let face = try font("NotoColorEmoji")
        let color = try bitmap(face, text: "😀")
        face.isColorEnabled = false
        let gray = try bitmap(face, text: "😀")
        XCTAssertEqual(gray.info.pixelMode, .gray)
        XCTAssertEqual(gray.bytes, stride(from: 3, to: color.bytes.count, by: 4).map { color.bytes[$0] })
    }

    func testConcurrentColorRasterizationKeepsGlyphsIndependent() throws {
        for family in ["NotoColorEmoji", "NotoColorEmojiBitmap"] {
            let face = try font(family)
            let samples = ["😀", "👍🏽", "👩🏽‍💻"]
            let indices = try samples.map { try XCTUnwrap(face.shape($0)?.glyphs.first?.index) }
            let expected = try samples.map { try bitmap(face, text: $0).bytes }
            let failures = Mutex(0)
            DispatchQueue.concurrentPerform(iterations: 24) { iteration in
                let index = iteration % indices.count
                let loaded = face.withGlyphBitmap(at: indices[index], embolden: 0, outline: 0) { bytes, _, _, _ in
                    if bytes != expected[index] { failures.withLock { $0 += 1 } }
                }
                if !loaded { failures.withLock { $0 += 1 } }
            }
            XCTAssertEqual(failures.withLock { $0 }, 0)
        }
    }

    func testMonochromeEmojiKeepsCoverageAndWeightAxis() throws {
        let face = try font("NotoEmoji")
        XCTAssertFalse(face.hasColor)
        XCTAssertTrue(face.isScalable)
        XCTAssertEqual(face.variationAxes.first?.minimumValue, 300)
        XCTAssertEqual(face.variationAxes.first?.maximumValue, 700)
        for text in ["😀", "👍🏽", "👩🏽‍💻", "🇰🇷"] {
            let value = try bitmap(face, text: text)
            XCTAssertEqual(value.info.pixelMode, .gray)
            XCTAssertTrue(value.bytes.contains { $0 != 0 })
        }
    }

    func testPresetsPreserveConfiguredOrderAndDefault() {
        let configuration = BundledFontCatalog.shared.configuration
        XCTAssertEqual(configuration.emojiFonts(preset: nil).map(\.rawValue),
                       ["NotoColorEmoji", "NotoColorEmojiBitmap", "NotoEmoji"])
        XCTAssertEqual(configuration.emojiFonts(preset: "monochrome").map(\.rawValue),
                       ["NotoEmoji", "NotoColorEmoji", "NotoColorEmojiBitmap"])
        XCTAssertEqual(configuration.emojiFonts(preset: "unknown"), configuration.emojiFonts(preset: nil))
    }

    func testPresetValidationRejectsInvalidReferencesAndDuplicates() throws {
        let url = BundledFontCatalog.shared.resources.resourceDirectory.appendingPathComponent("font-config.json")
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for (presets, defaultPreset) in [(["color": ["Undefined"]], "color"),
                                       (["color": ["NotoEmoji", "NotoEmoji"]], "color"),
                                       (["color": ["LastResort"]], "color"),
                                       (["color": []], "color"),
                                       (["color": ["NotoEmoji"]], "missing")] {
            var source = base
            source["emoji"] = ["defaultPreset": defaultPreset, "presets": presets]
            let data = try JSONSerialization.data(withJSONObject: source)
            XCTAssertThrowsError(try FontFallbackConfiguration(data: data))
        }
        var source = base
        source.removeValue(forKey: "emoji")
        let configuration = try FontFallbackConfiguration(data: JSONSerialization.data(withJSONObject: source))
        XCTAssertTrue(configuration.emojiFonts(preset: nil).isEmpty)
    }

    func testEnvironmentPresetCopiesAndChangesTextResolution() {
        var parent = EnvironmentValues()
        XCTAssertNil(parent.emojiFontPreset)
        parent.emojiFontPreset = "color"
        var child = parent
        child.emojiFontPreset = "monochrome"
        XCTAssertEqual(parent.emojiFontPreset, "color")
        let text = Text("👍🏽")
        let date = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertNotEqual(text._resolutionVersion(in: parent, referenceDate: date),
                          text._resolutionVersion(in: child, referenceDate: date))
    }

    // ASSERTIONS textEmojiPresentationSelectorObserved textEmojiModifierClusterObserved
    @MainActor
    func testPresetControlsEmojiWithoutReplacingOrdinaryText() throws {
        let previous = appContext
        let context = EmojiTestAppContext()
        appContext = context
        defer { appContext = previous }
        let resources = SceneResources()
        for preset in ["color", "monochrome"] {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            environment.emojiFontPreset = preset
            let cascade = VUI.Font.system(size: 17).typefaceCascade(
                in: environment, forContext: resources, dpi: 72
            )
            for text in ["A", "1", "❤︎", "❤️", "👍🏽", "👩🏽‍💻"] {
                let resolved = ResolvedTextSource(runs: [.text(cascade.runFaces, text)], scaleFactor: 1)
                let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)
                let first = try XCTUnwrap(glyphs.first)
                if ["A", "1"].contains(text) {
                    XCTAssertFalse(first.face.isEmojiFallback, text)
                } else if text == "❤︎" {
                    XCTAssertFalse(first.face.hasColorGlyphs)
                } else {
                    XCTAssertTrue(first.face.isEmojiFallback, text)
                    XCTAssertEqual(first.face.identifier,
                                   preset == "color" ? "deferred:NotoColorEmoji:0" : "deferred:NotoEmoji:0")
                    XCTAssertTrue(glyphs.allSatisfy { $0.sourceRange == 0..<text.unicodeScalars.count })
                }
            }
        }
    }

    @MainActor
    func testBitmapEmojiMetricsScaleBeforeGPUResourcesExist() throws {
        let previous = appContext
        let context = EmojiTestAppContext()
        appContext = context
        defer { appContext = previous }
        let provider = try XCTUnwrap(BundledFontProvider(
            family: BundledFontID("NotoColorEmojiBitmap"), locale: Locale(identifier: "en"),
            size: 17, weight: .regular, renderingMode: .bitmap(), isItalic: false,
            catalog: .shared
        ))
        let first = try XCTUnwrap(provider.makeTypeface(context, dpi: 72))
        let second = try XCTUnwrap(provider.makeTypeface(context, dpi: 144))
        XCTAssertTrue(first.hasGlyph(for: "😀"))
        let a = try XCTUnwrap(first.shape("👍🏽", direction: nil, language: nil, features: []))
        let b = try XCTUnwrap(second.shape("👍🏽", direction: nil, language: nil, features: []))
        XCTAssertEqual(a.glyphs.first!.advance.width * 2, b.glyphs.first!.advance.width, accuracy: 0.000001)
        XCTAssertEqual(first.ascender * 2, second.ascender, accuracy: 0.000001)
        XCTAssertLessThan(first.ascender - first.descender, 30)
    }

    // ASSERTIONS textEmojiForegroundOwnershipObserved
    @MainActor
    func testMetalGlyphsPreserveColorAndShadeMonochromeCoverage() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previous = appContext
        let app = EmojiTestAppContext(device: device)
        appContext = app
        defer { appContext = previous }
        func render(_ face: Typeface, color: VUI.Color, opacity: Double = 1) throws -> [UInt8] {
            let buffer = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
            let rect = CGRect(x: 0, y: 0, width: 96, height: 80)
            var context = try XCTUnwrap(GraphicsContext(
                sceneResources: SceneResources(), environment: EnvironmentValues(),
                viewport: rect, contentOffset: .zero, contentScaleFactor: 1,
                resolution: rect.size, commandBuffer: buffer
            ))
            context.clear(with: .clear)
            context.opacity = opacity
            let text = ResolvedTextSource(runs: [.text([face], "😀")], scaleFactor: 1)
            context.draw(text, in: rect, shading: .color(color))
            let completed = expectation(description: "Emoji GPU completion")
            buffer.addCompletedHandler { _ in completed.fulfill() }
            XCTAssertTrue(buffer.commit())
            wait(for: [completed], timeout: 5)
            let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
            return Array(UnsafeRawBufferPointer(start: try XCTUnwrap(staging.contents()), count: 96 * 80 * 4))
        }
        for mode: VUI.Font.RenderingMode in [.bitmap(), .vector()] {
            for family in ["NotoColorEmoji", "NotoColorEmojiBitmap", "NotoEmoji"] {
                let provider = try XCTUnwrap(BundledFontProvider(
                    family: BundledFontID(family), locale: Locale(identifier: "en"),
                    size: 48, weight: .regular, renderingMode: mode, isItalic: false,
                    catalog: .shared
                ))
                let face = try XCTUnwrap(provider.makeTypeface(app, dpi: 72))
                let red = try render(face, color: .red)
                let blue = try render(face, color: .blue)
                XCTAssertGreaterThan(stride(from: 3, to: red.count, by: 4).filter { red[$0] > 0 }.count, 100)
                if family == "NotoEmoji" {
                    XCTAssertNotEqual(red, blue)
                } else {
                    XCTAssertEqual(red, blue, family)
                    let translucent = try render(face, color: .red, opacity: 0.5)
                    let opaqueAlpha = stride(from: 3, to: red.count, by: 4).reduce(0) { $0 + Int(red[$1]) }
                    let fadedAlpha = stride(from: 3, to: translucent.count, by: 4).reduce(0) { $0 + Int(translucent[$1]) }
                    XCTAssertEqual(Double(fadedAlpha) / Double(opaqueAlpha), 0.5, accuracy: 0.02)
                }
            }
        }
    }
}

private final class EmojiTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]
    init(device: GraphicsDeviceContext? = nil) { graphicsDeviceContext = device }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { resources[url] }
    func setResource(data: (any DataProtocol)?, forURL url: URL) { resources[url] = data }
}
