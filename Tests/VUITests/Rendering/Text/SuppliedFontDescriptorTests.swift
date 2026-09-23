import Foundation
import XCTest
import VVD
@testable import VUI

final class SuppliedFontDescriptorTests: XCTestCase {
    private let weightTag: UInt32 = 0x7767_6874
    private let nearWeight: CGFloat = 530.0013885498047

    // ASSERTIONS fontSuppliedAttributeHistory27Observed
    func testSuppliedGeneralCopiesPreserveSizeBeforeAndAfterResolution() throws {
        for registration in [0, 2] {
            let (bundle, url) = try fixture(registration: registration)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let context = environment.fontResolutionContext
            for weight: CGFloat in [400, nearWeight, 700] {
                let backend = try loaded(url, weight: weight, data: true)
                for warm in [false, true] {
                    for language in [false, true] {
                        var descriptor = VUI.Font(vector: backend).resolveDescriptor(in: context)
                        if warm { _ = descriptor.resolvedWeight }
                        if language {
                            LanguageFontModifier(identifier: "en").modify(descriptor: &descriptor, in: context)
                            let first = descriptor
                            LanguageFontModifier(identifier: "ko").modify(descriptor: &descriptor, in: context)
                            XCTAssertTrue(descriptor === first)
                        } else {
                            descriptor = descriptor.clearFeatures()
                        }
                        let italic = descriptor.symbolicTrait(1, active: true)
                        XCTAssertEqual(italic.pointSize, 23.375)
                        XCTAssertEqual(italic.traitsPointSize, 23.375)
                        XCTAssertEqual(italic.language, language && registration == 0 && weight == 700 ? "en" : nil)
                        let resource = FontResource(descriptor: descriptor, in: context)
                        let copied = try XCTUnwrap(resource.fontWithSize(31.375))
                        XCTAssertEqual(copied.descriptor().symbolicTrait(1, active: true).pointSize, 31.375)
                    }
                }
                // A copied option cannot create a size attribute that was absent.
                let first = VUI.Font(vector: backend).resolveDescriptor(in: context).symbolicTrait(1, active: true)
                for next in [first.clearFeatures(), first.withTypesetting(language: "en")] {
                    let bold = next.symbolicTrait(2, active: true)
                    XCTAssertEqual(bold.traitsPointSize, registration == 0 && weight == 700 ? 23.375 : 0)
                    XCTAssertEqual(FontResource(descriptor: bold, in: context).pointSize,
                                   registration == 0 && weight == 700 ? 23.375 : 12)
                }
            }
        }
    }

    // ASSERTIONS fontSuppliedAttributeHistory27Observed fontPlatformRedaction27Observed
    func testSuppliedProviderRedactionPreservesSizeAndClearsWrappedFeatures() throws {
        for registration in [0, 2] {
            let (bundle, url) = try fixture(registration: registration)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            let normal = environment.fontResolutionContext
            environment.shouldRedactContent = true
            let redacted = environment.fontResolutionContext
            for data in [false, true] {
                for weight: CGFloat in [400, nearWeight, 700] {
                    let font = VUI.Font(vector: try loaded(url, weight: weight, data: data))
                    let digits = font.monospacedDigit().platformFont(in: normal)
                    let wrapped = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: digits)))
                    for request in [font.italic(), font.bold(), font.monospacedDigit().italic(), wrapped.italic()] {
                        let result = request.platformFont(in: redacted)
                        XCTAssertEqual(result.pointSize, 23.375)
                        XCTAssertEqual(request.resolveTraits(in: redacted).pointSize, 23.375)
                        XCTAssertTrue(result.shapingFeatures.isEmpty)
                        let face = try XCTUnwrap(result.provider.makeTypeface(StyleTestAppContext(), dpi: 72))
                        XCTAssertEqual(face.selectedFont?.pointSize, 23.375)
                    }
                    XCTAssertEqual(digits.shapingFeatures.map(\.value), [1])
                }
            }
        }
    }

    // ASSERTIONS fontSuppliedAttributeHistory27Observed
    func testSuppliedRatioCopiesRematchBeforeSymbolicSelection() throws {
        for registration in [0, 2] {
            for weight: CGFloat in [400, nearWeight, 700] {
                for warm in [false, true] {
                    // Each independent source gets its own name-request scope;
                    // numeric URL cache warming has separate ordered guards.
                    let (bundle, url) = try fixture(registration: registration)
                    var environment = EnvironmentValues()
                    environment.resourceBundle = bundle
                    environment.defaultFontRenderingMode = .vector()
                    let context = environment.fontResolutionContext
                    let backend = try loaded(url, weight: weight, data: true)
                    var descriptor = VUI.Font(vector: backend).resolveDescriptor(in: context)
                    if warm { _ = descriptor.resolvedWeight }
                    LanguageAwareLineHeightRatioFontModifier(ratio: 1.2).modify(descriptor: &descriptor, in: context)
                    guard case .named = descriptor.source else {
                        XCTFail("A ratio copy must rematch its original name")
                        continue
                    }
                    let italic = descriptor.symbolicTrait(1, active: true)
                    XCTAssertEqual(italic.pointSize, 23.375)
                    let resource = FontResource(descriptor: italic, in: context)
                    let face = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 72) as? VectorTypeface)
                    let name = registration == 0 ? "Roboto-Regular" : weight == 400 ? "Qzfont-Italic"
                        : weight == 700 ? "Qzfont-BoldItalic" : "Qzfont-MediumItalic"
                    XCTAssertEqual(face.selectedFont?.descriptor.postScriptName, name)
                    XCTAssertFalse(face.font.source === backend.source)
                    // Once an actual fallback font is constructed, its copied
                    // descriptor can select a variant of that selected family.
                    let plain = FontResource(descriptor: descriptor, in: context)
                    for realized in [plain, try XCTUnwrap(plain.fontWithSize(31.375))] {
                        let next = FontResource(descriptor: realized.descriptor().symbolicTrait(1, active: true), in: context)
                        let nextFace = try XCTUnwrap(next.provider.makeTypeface(StyleTestAppContext(), dpi: 72))
                        let expected = registration == 0 ? "Roboto-Italic" : weight == nearWeight
                            ? "Qzfont-Italic_wght2120055_wdth" : weight == 400 ? "Qzfont-Italic" : "Qzfont-BoldItalic"
                        XCTAssertEqual(nextFace.selectedFont?.descriptor.postScriptName, expected)
                        XCTAssertEqual(next.pointSize, realized.pointSize)
                    }
                    XCTAssertEqual(backend.pointSize, 23.375)
                    XCTAssertEqual(backend.variationCoordinates[weightTag], weight)
                }
            }
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed fontSuppliedAttributeHistory27Observed
    func testSuppliedSymbolicCopiesReachMetalDrawingAndRecordedReplay() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let (bundle, url) = try fixture(registration: 0)
        let bytes = try Data(contentsOf: url)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let extent = CGSize(width: 256, height: 64)
        let scene = SceneResources()
        func draw(_ font: VUI.Font, replay: Bool) throws -> ([UInt8], CGSize, CGFloat) {
            let commands = try XCTUnwrap(device.renderQueue()?.makeCommandBuffer())
            let context = try XCTUnwrap(GraphicsContext(sceneResources: scene, environment: environment,
                viewport: CGRect(origin: .zero, size: extent), contentOffset: .zero,
                contentScaleFactor: 1, resolution: extent, commandBuffer: commands))
            let text = context.resolve(Text(verbatim: "AM0g").font(font))
            let size = text.measure(in: extent)
            let baseline = text.firstBaseline(in: extent)
            context.clear(with: .clear)
            if replay {
                let recording = context.recordingContext(size: extent)
                recording.draw(text, in: CGRect(origin: .zero, size: extent))
                try XCTUnwrap(recording.recording).draw(in: context)
            } else {
                context.draw(text, in: CGRect(origin: .zero, size: extent))
            }
            let completed = expectation(description: "Supplied variant readback")
            commands.addCompletedHandler { _ in completed.fulfill() }
            XCTAssertTrue(commands.commit())
            wait(for: [completed], timeout: 15)
            let buffer = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
            let pixels = Array(UnsafeRawBufferPointer(start: try XCTUnwrap(buffer.contents()), count: 256 * 64 * 4))
            return (pixels, size, baseline)
        }
        for bitmap in [false, true] {
            for dpi: UInt32 in [72, 144] {
                func font(_ weight: CGFloat, _ size: CGFloat) throws -> VUI.Font {
                    let backend: VVD.Font = try XCTUnwrap(bitmap ? TextureFont(deviceContext: device, data: bytes)
                        : VVD.Font(data: bytes))
                    backend.setPointSize(size, dpi: (dpi, dpi))
                    XCTAssertTrue(backend.setVariationCoordinates([weightTag: weight]))
                    return (backend as? TextureFont).map { VUI.Font($0) } ?? VUI.Font(vector: backend)
                }
                for weight: CGFloat in [400, nearWeight, 700] {
                    let original = try font(weight, 23.375)
                    let request = weight == 400 ? original.bold() : weight == 700 ? original.bold(false) : original.italic()
                    for redacted in [false, true] {
                        var context = environment.fontResolutionContext
                        context.shouldRedactContent = redacted
                        let resource = request.platformFont(in: context)
                        let actual = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
                        let direct = try draw(actual, replay: false)
                        let recorded = try draw(actual, replay: true)
                        XCTAssertTrue(stride(from: 3, to: direct.0.count, by: 4).contains { direct.0[$0] > 0 })
                        XCTAssertTrue(direct.0 == recorded.0)
                        XCTAssertEqual(direct.1, recorded.1)
                        XCTAssertEqual(direct.2, recorded.2)
                        if weight != 700 {
                            let reference = try draw(font(weight == 400 ? 700 : nearWeight, redacted ? 23.375 : 12), replay: false)
                            XCTAssertEqual(direct.1, reference.1)
                            XCTAssertEqual(direct.2, reference.2)
                            XCTAssertTrue(direct.0 == reference.0)
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS fontSuppliedTraits27Observed fontGraphicsRegistry27Observed
    func testSuppliedResolvedTraitsKeepAbsentSizeSeparateFromConstructionSize() throws {
        let (bundle, url) = try fixture(registration: 0)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        for weight: CGFloat in [400, nearWeight, 700] {
            let font = VUI.Font(vector: try loaded(url, weight: weight, data: true))
            let logical: CGFloat = weight == 400 ? 0 : weight == 700 ? CGFloat(Float(0.4)) : CGFloat(Float(0.23))
            let requests: [(VUI.Font, CGFloat, CGFloat)] = [
                (font, 23.375, logical),
                (font.italic(), weight == 700 ? 23.375 : 0, logical),
                (font.bold(), weight == 700 ? 23.375 : 0, CGFloat(Float(0.4))),
                (font.bold(false), weight == 700 ? 0 : 23.375, weight == 700 ? 0 : logical),
                (font.weight(.bold), 23.375, 0), (font.width(.condensed), 23.375, 0),
                (font.monospacedDigit(), 23.375, logical),
                (font.leading(.loose), weight == 700 ? 23.375 : 0, logical)
            ]
            for (request, size, selectedWeight) in requests {
                let traits = request.resolveTraits(in: context)
                XCTAssertEqual(traits.pointSize, size)
                XCTAssertEqual(traits.weight, selectedWeight)
                XCTAssertNil(traits.width)
                XCTAssertEqual(request.platformFont(in: context).pointSize, size == 0 ? 12 : size)
            }
        }
        let defaultAxisURL = BundledFontCatalog.shared.resources.resourceDirectory
            .appendingPathComponent("NanumSquareNeo/NanumSquareNeo-Variable.ttf")
        let backend = try XCTUnwrap(VVD.Font(path: defaultAxisURL.path))
        backend.setPointSize(23.375, dpi: (72, 72))
        let input = VUI.Font(vector: backend)
        for request in [input, input.monospacedDigit()] {
            XCTAssertEqual(request.resolveTraits(in: context).weight, CGFloat(Float(-0.6)))
            XCTAssertEqual(request.resolveTraits(in: context).pointSize, 23.375)
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed fontGraphicsSizeCopy27Observed
    func testSuppliedVariantCopiesRetainLoadedBytesAfterReplacementAndParentRelease() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let app = StyleTestAppContext(graphicsDeviceContext: device)
        for bitmap in [false, true] {
            for data in [false, true] {
                let (bundle, url) = try fixture(registration: 0)
                var environment = EnvironmentValues()
                environment.resourceBundle = bundle
                weak var parent: VVD.Font?
                weak var owner: VVD.Font.Source?
                func makeCopy() throws -> FontResource {
                    let font: VVD.Font
                    if bitmap {
                        font = try XCTUnwrap(data ? TextureFont(deviceContext: device, data: Data(contentsOf: url))
                            : TextureFont(deviceContext: device, path: url.path))
                    } else {
                        font = try loaded(url, weight: nearWeight, data: data)
                    }
                    font.setPointSize(23.375, dpi: (96, 144))
                    XCTAssertTrue(font.setVariationCoordinates([weightTag: nearWeight]))
                    parent = font
                    owner = font.source
                    let metadata = try XCTUnwrap(VVD.Font.metadata(path: url.path))
                    let replacement = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("Unrelated.ttf"))
                    try replacement.write(to: url, options: .atomic)
                    XCTAssertEqual(font.metadata(), metadata)
                    let input = (font as? TextureFont).map { VUI.Font($0) } ?? VUI.Font(vector: font)
                    // Inspect copy ownership independently of the request cache,
                    // whose key intentionally retains the original Font value.
                    let context = environment.fontResolutionContext
                    let resource = FontResource(descriptor: input.italic().monospacedDigit().resolveDescriptor(in: context),
                                                in: context)
                    XCTAssertEqual(resource.pointSize, 12)
                    XCTAssertEqual(font.pointSize, 23.375)
                    XCTAssertEqual(font.variationCoordinates[weightTag], nearWeight)
                    return resource
                }
                let resource = try makeCopy()
                XCTAssertNil(parent)
                XCTAssertNotNil(owner)
                try FileManager.default.removeItem(at: url)
                for selected in [resource, try XCTUnwrap(resource.fontWithSize(31.375))] {
                    let face = try XCTUnwrap(selected.provider.makeTypeface(app, dpi: 72) as? any VVDFontBackedTypeface)
                    XCTAssertEqual(face is TextureTypeface, bitmap)
                    XCTAssertTrue(face.font.source === owner)
                    XCTAssertEqual(face.font.familyName, "Qzfont")
                    XCTAssertEqual(face.font.metadata()?.familyName, "Qzfont")
                    XCTAssertEqual(face.font.dpi.x, 96)
                    XCTAssertEqual(face.font.dpi.y, 144)
                    XCTAssertEqual(face.font.variationCoordinates[weightTag], nearWeight)
                    XCTAssertEqual(face.selectedFont?.variation, [weightTag: 530])
                    XCTAssertEqual(face.selectedFont?.descriptor.postScriptName, "Qzfont-Regular_wght212005B_wdth")
                    XCTAssertNotNil(face.font.shape("AM0g"))
                    XCTAssertEqual(selected.shapingFeatures.map(\.value), [1])
                }
            }
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed
    func testUnregisteredCopiesSeparateComparisonFromPhysicalVariation() throws {
        let (bundle, url) = try fixture(registration: 0)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        for data in [false, true] {
            for weight: CGFloat in [400, nearWeight, 700] {
                let original = try loaded(url, weight: weight, data: data)
                let font = VUI.Font(vector: original)
                let originalName = original.postScriptName
                let originalCoordinates = original.variationCoordinates
                let originalGlyph = try XCTUnwrap(original.shape("AM0g"))
                let expectedName = weight == 400 ? "Qzfont-Regular" : weight == 700
                    ? "Qzfont-Bold" : "Qzfont-Regular_wght212005B_wdth"
                let plain = font.platformFont(in: context)
                for (request, size, comparison, physical): (VUI.Font, CGFloat, CGFloat?, CGFloat) in [
                    (font, 23.375, weight == 400 ? nil : weight == 700 ? 700 : 530.0013, weight),
                    (font.italic(), weight == 700 ? 23.375 : 12, weight == 400 ? nil : weight == 700 ? 700 : 530, weight),
                    (font.bold(), weight == 700 ? 23.375 : 12, 700, 700),
                    (font.bold(false), weight == 700 ? 12 : 23.375, weight == nearWeight ? 530.0013 : nil, weight),
                    (font.leading(.loose), weight == 700 ? 23.375 : 12, weight == 400 ? nil : weight == 700 ? 700 : 530, weight)
                ] {
                    let resource = request.platformFont(in: context)
                    let face = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 144) as? VectorTypeface)
                    let selected = try XCTUnwrap(face.selectedFont)
                    XCTAssertEqual(resource.pointSize, size)
                    XCTAssertEqual(face.font.pointSize, size)
                    XCTAssertEqual(selected.pointSize, size)
                    XCTAssertEqual(selected.descriptor.postScriptName, expectedName)
                    XCTAssertEqual(selected.variation[weightTag], comparison)
                    XCTAssertEqual(face.font.variationCoordinates[weightTag], physical)
                    XCTAssertTrue(face.font.source === original.source)
                    XCTAssertEqual(face.font.dpi.y, 72)
                    if physical == weight {
                        let glyphs = try XCTUnwrap(face.font.shape("AM0g"))
                        XCTAssertEqual(glyphs.glyphs.map(\.index), originalGlyph.glyphs.map(\.index))
                        for (a, b) in zip(glyphs.glyphs, originalGlyph.glyphs) {
                            XCTAssertEqual(a.advance.width / size, b.advance.width / 23.375, accuracy: 0.000001)
                        }
                    }
                    let copy = try XCTUnwrap(resource.fontWithSize(31.375))
                    let copied = try XCTUnwrap(copy.provider.makeTypeface(StyleTestAppContext(), dpi: 72) as? VectorTypeface)
                    XCTAssertEqual(copied.font.pointSize, 31.375)
                    XCTAssertTrue(copied.font.source === original.source)
                    XCTAssertEqual(copied.font.variationCoordinates[weightTag], physical)
                    XCTAssertEqual(copied.selectedFont?.variation, selected.variation)
                    XCTAssertEqual(copied.selectedFont?.descriptor.postScriptName, expectedName)
                }
                for request in [font.weight(.bold), font.width(.condensed)] {
                    let result = request.platformFont(in: context)
                    let face = try XCTUnwrap(result.provider.makeTypeface(StyleTestAppContext(), dpi: 72) as? VectorTypeface)
                    XCTAssertEqual(result.pointSize, 23.375)
                    XCTAssertEqual(face.font.familyName, "Roboto")
                    XCTAssertFalse(face.font.source === original.source)
                }
                XCTAssertEqual(original.postScriptName, originalName)
                XCTAssertEqual(original.variationCoordinates, originalCoordinates)
                XCTAssertEqual(original.pointSize, 23.375)
                XCTAssertTrue((plain.provider as? FixedFontProvider)?.face is VectorTypeface)
            }
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed
    func testScopedRegistryChoosesVariantsWithoutChangingSuppliedOrigin() throws {
        for registration in [1, 2] {
            let (bundle, url) = try fixture(registration: registration)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            for weight: CGFloat in [400, nearWeight, 700] {
                let original = try loaded(url, weight: weight, data: true)
                let font = VUI.Font(vector: original)
                let context = environment.fontResolutionContext
                let plain = try XCTUnwrap(font.platformFont(in: context).provider as? FixedFontProvider)
                XCTAssertTrue((plain.face as? VectorTypeface)?.font === original)
                let suffix = weight == 400 ? "Regular" : weight == 700 ? "Bold" : "Medium"
                let italic = font.italic().platformFont(in: context)
                let italicFace = try XCTUnwrap(italic.provider.makeTypeface(StyleTestAppContext(), dpi: 72) as? VectorTypeface)
                XCTAssertEqual(italic.pointSize, registration == 1 && weight == 700 ? 23.375 : 12)
                if registration == 2 {
                    XCTAssertEqual(italicFace.selectedFont?.descriptor.postScriptName,
                                   "Qzfont-" + (weight == 400 ? "Italic" : suffix + "Italic"))
                    XCTAssertEqual(italicFace.font.variationCoordinates[weightTag], weight == nearWeight ? 500 : weight)
                    XCTAssertFalse(italicFace.font.source === original.source)
                } else {
                    XCTAssertTrue(italicFace.font.source === original.source)
                    XCTAssertEqual(italicFace.font.variationCoordinates[weightTag], weight)
                }
                for (request, name, size, coordinate, width): (VUI.Font, String, CGFloat, CGFloat, CGFloat) in [
                    (font.bold(), "Qzfont-Bold", weight == 700 ? 23.375 : 12, 700, 100),
                    (font.weight(.bold), "Qzfont-Bold", 23.375, 700, 100),
                    (font.width(.condensed), "Qzfont-Condensed" + suffix, 23.375, weight == nearWeight ? 500 : weight, 75),
                    (font.leading(.loose), "Qzfont-" + suffix, 12, weight == nearWeight ? 500 : weight, 100)
                ] {
                    let resource = request.platformFont(in: context)
                    let face = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 72) as? VectorTypeface)
                    XCTAssertEqual(resource.pointSize, size)
                    XCTAssertEqual(face.selectedFont?.descriptor.postScriptName, name)
                    XCTAssertEqual(face.font.variationCoordinates[weightTag], coordinate)
                    XCTAssertEqual(face.font.variationCoordinates[0x7764_7468], width)
                }
                XCTAssertEqual(original.pointSize, 23.375)
                XCTAssertEqual(original.variationCoordinates[weightTag], weight)
            }
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed
    func testSuppliedFeatureOrderFollowsDirectAndUnchangedCopies() throws {
        for registration in 0...2 {
            let (bundle, url) = try fixture(registration: registration)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            for weight: CGFloat in [400, nearWeight, 700] {
                let original = try loaded(url, weight: weight, data: true)
                let font = VUI.Font(vector: original)
                let before = font.monospacedDigit().italic().platformFont(in: environment.fontResolutionContext)
                let after = font.italic().monospacedDigit().platformFont(in: environment.fontResolutionContext)
                XCTAssertEqual(before.shapingFeatures.isEmpty, registration == 2 || weight != 700)
                XCTAssertEqual(after.shapingFeatures.map(\.value), [1])
                let face = try XCTUnwrap(after.provider.makeTypeface(StyleTestAppContext(), dpi: 72))
                let shaped = ShapingFeatureTypeface(face, features: after.shapingFeatures)
                XCTAssertEqual(shaped.selectedFont?.features.count, 1)
                XCTAssertEqual(before.pointSize, after.pointSize)
            }
        }
    }

    private func loaded(_ url: URL, weight: CGFloat, data: Bool) throws -> VVD.Font {
        let font = try XCTUnwrap(data ? VVD.Font(data: Data(contentsOf: url)) : VVD.Font(path: url.path))
        font.setPointSize(23.375, dpi: (72, 72))
        XCTAssertTrue(font.setVariationCoordinates([weightTag: weight]))
        return font
    }

    private func fixture(registration: Int) throws -> (Bundle, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        let fonts = directory.appendingPathComponent("Contents/Resources/Fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>supplied-font.\(UUID().uuidString)</string>
        <key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
        """.utf8).write(to: directory.appendingPathComponent("Contents/Info.plist"))
        #if !canImport(Darwin)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("Fonts"), withDestinationURL: fonts)
        #endif
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let original = BundledFontCatalog.shared.resources.resourceDirectory
        for (source, target) in [("Roboto-VariableFont_wdth,wght.ttf", "Regular.ttf"),
                                 ("Roboto-Italic-VariableFont_wdth,wght.ttf", "Italic.ttf")] {
            var data = try Data(contentsOf: original.appendingPathComponent("Roboto/" + source))
            for encoding in [String.Encoding.utf16BigEndian, .ascii] {
                let old = try XCTUnwrap("Roboto".data(using: encoding))
                let replacement = try XCTUnwrap("Qzfont".data(using: encoding))
                while let range = data.range(of: old) { data.replaceSubrange(range, with: replacement) }
            }
            try data.write(to: fonts.appendingPathComponent(target))
        }
        let primary = registration == 0 ? "Unrelated.ttf" : "Regular.ttf"
        try FileManager.default.copyItem(at: original.appendingPathComponent("RobotoMono/RobotoMono-VariableFont_wght.ttf"),
                                         to: fonts.appendingPathComponent("Unrelated.ttf"))
        let extra = registration == 2 ? #", "Italic":{"sources":[{"file":"Italic.ttf","faceIndex":0,"weight":400}],"syntheticWeight":false}"# : ""
        try Data("""
        {"version":2,"fonts":{
          "Primary":{"sources":[{"file":"\(primary)","faceIndex":0,"weight":400}],"syntheticWeight":false},
          "Terminal":{"sources":[{"file":"\(primary)","faceIndex":0,"weight":400}],"syntheticWeight":false}\(extra)},
         "defaultLocale":"en","designs":{"default":{"systemFont":"Primary","locales":{"en":["Primary"]}}},"missingGlyphFont":"Terminal"}
        """.utf8).write(to: fonts.appendingPathComponent("font-config.json"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        _ = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
        return (bundle, fonts.appendingPathComponent("Regular.ttf"))
    }
}
