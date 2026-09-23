import Foundation
import XCTest
import VVD
@testable import VUI

final class SelectedFontTests: XCTestCase {
    // ASSERTIONS fontGraphicsSizeCopy27Observed
    func testSuppliedVectorSizeCopiesRetainSelectionAndRestoreEquality() throws {
        let context = SelectedFontAppContext()
        let resolution = EnvironmentValues().fontResolutionContext
        let weight: UInt32 = 0x7767_6874, width: UInt32 = 0x7764_7468
        for memory in [false, true] {
            for axes: [UInt32: CGFloat] in [[:], [weight: 700], [weight: 700, width: 90], [weight: 530.0013885498047]] {
                let backend = try XCTUnwrap(memory ? VVD.Font(data: Data(contentsOf: url)) : VVD.Font(path: url.path))
                backend.setPointSize(23.375, dpi: (96, 144))
                XCTAssertTrue(backend.setVariationCoordinates(axes))
                let input = VUI.Font(vector: backend).monospacedDigit()
                let resource = input.platformFont(in: resolution)
                let original = try XCTUnwrap(resource.provider.makeTypeface(context, dpi: 216) as? VectorTypeface)
                let selected = try XCTUnwrap(original.selectedFont)
                let originalMetrics = backend.baseMetrics
                XCTAssertTrue(resource.fontWithSize(0) === resource)
                XCTAssertTrue(resource.fontWithSize(23.375) === resource)
                XCTAssertNil(resource.fontWithSize(-1))
                XCTAssertNil(resource.fontWithSize(.infinity))
                XCTAssertNil(resource.fontWithSize(.nan))
                guard let copied = resource.fontWithSize(31.375) else {
                    XCTFail("A supplied font must retain its construction through a size copy")
                    continue
                }
                let face = try XCTUnwrap(copied.provider.makeTypeface(context, dpi: 72) as? VectorTypeface)
                let copySelection = try XCTUnwrap(face.selectedFont)
                XCTAssertFalse(face.font === backend)
                XCTAssertEqual(copied.pointSize, 31.375)
                XCTAssertEqual(face.font.pointSize, 31.375)
                XCTAssertEqual(face.font.dpi.x, 96)
                XCTAssertEqual(face.font.dpi.y, 144)
                XCTAssertEqual(face.font.variationCoordinates, backend.variationCoordinates)
                XCTAssertEqual(copySelection.descriptor, selected.descriptor)
                XCTAssertEqual(copySelection.variation, selected.variation)
                XCTAssertEqual(copySelection.variationExtras, selected.variationExtras)
                XCTAssertEqual(copySelection.pointSize, 31.375)
                XCTAssertFalse(copySelection.isEqual(to: selected))
                XCTAssertEqual(copied.shapingFeatures, resource.shapingFeatures)
                let restored = try XCTUnwrap(copied.fontWithSize(23.375))
                XCTAssertTrue(try XCTUnwrap(restored.provider.makeTypeface(context, dpi: 72)?.selectedFont).isEqual(to: selected))
                XCTAssertEqual(restored, resource)
                XCTAssertEqual(restored.hashValue, resource.hashValue)
                let independent = try XCTUnwrap(VVD.Font(path: url.path))
                independent.setPointSize(23.375, dpi: (96, 144))
                XCTAssertTrue(independent.setVariationCoordinates(axes))
                XCTAssertNotEqual(VUI.Font(vector: independent).monospacedDigit().platformFont(in: resolution), restored)
                XCTAssertEqual(backend.pointSize, 23.375)
                XCTAssertEqual(backend.baseMetrics.ascender, originalMetrics.ascender)
                XCTAssertEqual(backend.baseMetrics.descender, originalMetrics.descender)
                XCTAssertEqual(backend.baseMetrics.height, originalMetrics.height)
                XCTAssertEqual(copied.requestedPointSize, 31.375)
                let metrics = try XCTUnwrap(copied.resolvedMetrics(for: face, scaleFactor: 2))
                XCTAssertEqual(metrics.ascender, 29.107666015625)
                XCTAssertEqual(metrics.descender, -7.659912109375)
                XCTAssertEqual(metrics.leading, 0)
            }
        }
    }

    // ASSERTIONS fontGraphicsSizeCopy27Observed fontStructureInputs27Observed fontPlatformInputs27Observed
    func testSuppliedVectorCacheIdentityKeepsPhysicalConfigurationSeparateFromSelection() throws {
        let resolution = EnvironmentValues().fontResolutionContext
        let backend = try XCTUnwrap(VVD.Font(path: url.path))
        backend.setPointSize(23.375, dpi: (96, 144))
        XCTAssertTrue(backend.setVariationCoordinates([0x7767_6874: 700, 0x7764_7468: 90]))

        func copy(_ update: (VVD.Font) -> Void = { _ in }) throws -> VVD.Font {
            let value = try XCTUnwrap(backend.copy())
            update(value)
            return value
        }
        func selected(_ font: VUI.Font) throws -> SelectedFont {
            let provider = try XCTUnwrap(font.typefaceProvider as? FixedFontProvider)
            return try XCTUnwrap(provider.face.selectedFont)
        }

        let original = VUI.Font(vector: try copy(), embolden: 0.25, outlineThickness: 0.5)
        let equivalent = VUI.Font(vector: try copy(), embolden: 0.25, outlineThickness: 0.5)
        XCTAssertEqual(original, equivalent)
        XCTAssertEqual(original.hashValue, equivalent.hashValue)
        XCTAssertEqual(original.platformFont(in: resolution), equivalent.platformFont(in: resolution))

        let controls: [(String, VUI.Font)] = [
            ("outline", VUI.Font(vector: try copy(), embolden: 0.25, outlineThickness: 0.75)),
            ("dpi", VUI.Font(vector: try copy { $0.dpi = (72, 72) }, embolden: 0.25, outlineThickness: 0.5)),
            ("bitmap", VUI.Font(vector: try copy { $0.isBitmapPreferred = true }, embolden: 0.25, outlineThickness: 0.5)),
            ("kerning", VUI.Font(vector: try copy { $0.isKerningEnabled = false }, embolden: 0.25, outlineThickness: 0.5)),
            ("color", VUI.Font(vector: try copy { $0.isColorEnabled = false }, embolden: 0.25, outlineThickness: 0.5))
        ]
        let originalSelection = try selected(original)
        for (label, value) in controls {
            XCTAssertTrue(originalSelection.isEqual(to: try selected(value)), label)
            XCTAssertNotEqual(original, value, label)
            XCTAssertNotEqual(original.platformFont(in: resolution), value.platformFont(in: resolution), label)
        }
    }

    // ASSERTIONS fontGraphicsSource27Observed fontVariationSelection27Observed fontGraphicsRegistry27Observed
    func testSuppliedVectorFontRetainsVariationWithoutDescriptorExtras() throws {
        let context = SelectedFontAppContext()
        let resolution = EnvironmentValues().fontResolutionContext
        let weight: UInt32 = 0x7767_6874, width: UInt32 = 0x7764_7468
        let controls: [([UInt32: CGFloat], [UInt32: CGFloat], String)] = [
            ([:], [:], "Roboto-Regular"),
            ([weight: 400, width: 100], [:], "Roboto-Regular"),
            ([weight: 700], [weight: 700], "Roboto-Bold"),
            ([weight: 700, width: 90], [weight: 700, width: 90], "Roboto-Regular_wght2BC0000_wdth5A0000"),
            ([weight: 530.0014], [weight: 530.0013], "Roboto-Regular_wght212005B_wdth")
        ]
        for memory in [false, true] {
            for (request, comparison, logicalName) in controls {
                let backend = try XCTUnwrap(memory ? VVD.Font(data: Data(contentsOf: url)) : VVD.Font(path: url.path))
                XCTAssertTrue(backend.setVariationCoordinates(request))
                backend.setPointSize(23.375, dpi: (144, 144))
                let coordinates = backend.variationCoordinates
                let name = backend.postScriptName
                let input = VUI.Font(vector: backend)
                let resource = input.resolve(in: resolution).resource
                let wrapped = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
                for font in [input, wrapped, input.monospacedDigit(), wrapped.monospacedDigit()] {
                    let face = try XCTUnwrap(font.resolve(in: resolution).resource.provider.makeTypeface(context, dpi: 216) as? VectorTypeface)
                    let selected = try XCTUnwrap(face.selectedFont)
                    XCTAssertEqual(selected.variation, comparison)
                    XCTAssertNil(selected.variationExtras)
                    XCTAssertEqual(selected.descriptor.postScriptName, logicalName)
                    XCTAssertEqual(selected.pointSize, 23.375)
                    guard case let .supplied(owner) = selected.descriptor.source else {
                        return XCTFail("A supplied font lost its resource identity")
                    }
                    XCTAssertTrue(owner === backend.source)
                    XCTAssertTrue(face.font === backend)
                }
                XCTAssertEqual(backend.variationCoordinates, coordinates)
                XCTAssertEqual(backend.postScriptName, name)
                XCTAssertEqual(backend.pointSize, 23.375)
                XCTAssertEqual(backend.dpi.x, 144)
                XCTAssertEqual(backend.dpi.y, 144)
            }
        }
    }

    // ASSERTIONS fontGraphicsConstruction27Observed
    func testSuppliedVectorFontPreservesPointSizeIndependentlyOfPixelMetrics() throws {
        let context = SelectedFontAppContext()
        let resolution = EnvironmentValues().fontResolutionContext
        for dpi: UInt32 in [72, 144] {
            for size: CGFloat in [23, 23.375] {
                let backend = try XCTUnwrap(VVD.Font(path: url.path))
                backend.setPointSize(size, dpi: (dpi, dpi))
                let originalHeight = backend.height
                XCTAssertNotEqual(originalHeight, size)
                let input = VUI.Font(vector: backend)
                let descriptor = input.resolveDescriptor(in: resolution)
                let resource = input.resolve(in: resolution).resource
                XCTAssertEqual(descriptor.pointSize, size)
                XCTAssertEqual(input.resolveTraits(in: resolution).pointSize, size)
                XCTAssertEqual(input.resolve(in: resolution).pointSize, size)
                let wrapped = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(font: resource)))
                for font in [input, wrapped, input.monospacedDigit(), wrapped.monospacedDigit()] {
                    let resolved = font.resolve(in: resolution)
                    XCTAssertEqual(resolved.pointSize, size)
                    let face = try XCTUnwrap(resolved.resource.provider.makeTypeface(context, dpi: 216) as? VectorTypeface)
                    XCTAssertTrue(face.font === backend)
                    XCTAssertEqual(face.lineHeight, originalHeight)
                    XCTAssertEqual(face.selectedFont?.pointSize, size)
                    XCTAssertEqual(face.font.dpi.x, dpi)
                    XCTAssertEqual(face.font.dpi.y, dpi)
                }
                XCTAssertEqual(backend.pointSize, size)
                XCTAssertEqual(backend.height, originalHeight)
            }
        }
    }

    private var url: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
    }

    // ASSERTIONS fontVariationExtras27Observed fontVariationSelection27Observed
    func testProvidersRetainVariationExtrasBeforeCoordinateComparison() throws {
        let metadata = try XCTUnwrap(VVD.Font.metadata(path: url.path))
        let context = SelectedFontAppContext()
        let w: UInt32 = 0x7767_6874, h: UInt32 = 0x7764_7468, unknown: UInt32 = 0x4142_4344
        let controls: [(CGFloat, [UInt32: CGFloat], [UInt32: CGFloat]?, [UInt32: CGFloat], String)] = [
            (400, [:], nil, [:], "Roboto-Regular"),
            (400, [w: 400.0001], nil, [:], "Roboto-Regular"),
            (400, [w: 400.001], [w: 400.001], [w: 400.0009], "Roboto-Regular"),
            (400, [w: 0], [w: 0], [w: 100], "Roboto-Regular_wght0_wdth"),
            (400, [w: 1000], [w: 1000], [w: 900], "Roboto-Regular_wght3E80000_wdth"),
            (400, [h: 200], nil, [:], "Roboto-Regular"),
            (400, [h: 99.9999999], [h: 99.9999999], [h: 99.9999], "Roboto-Regular"),
            (400, [unknown: 400], [unknown: 400], [:], "Roboto-Regular"),
            (400, [w: 400, unknown: 400], nil, [:], "Roboto-Regular"),
            (400, [w: 700, h: 100, unknown: 400], [w: 700, h: 100, unknown: 400], [w: 700], "Roboto-Bold"),
            (100, [:], nil, [w: 100], "Roboto-Thin"),
            (100, [w: 100], nil, [w: 100], "Roboto-Thin"),
            (100, [w: 400], [w: 400], [:], "Roboto-Regular"),
            (100, [w: 400.001], [w: 400.0009], [w: 400.0009], "Roboto-Regular"),
            (100, [h: 90], [w: 100, h: 90], [w: 100, h: 90], "Roboto-Regular_wght640000_wdth5A0000"),
            (100, [h: 200], nil, [w: 100], "Roboto-Thin"),
            (100, [unknown: 400], nil, [w: 100], "Roboto-Thin"),
            (700, [w: 700], nil, [w: 700], "Roboto-Bold"),
            (700, [w: 400], [w: 400], [:], "Roboto-Regular"),
            (700, [w: 700, h: 100, unknown: 400], nil, [w: 700], "Roboto-Bold")
        ]
        for (baseWeight, request, extras, comparison, name) in controls {
            let instance = try XCTUnwrap(metadata.variationInstances.first {
                $0.coordinates == [baseWeight, 100]
            })
            let provider = BundledFontProvider(resource: .init(url: url), size: 23, weight: .regular,
                renderingMode: .vector(), variations: request.map { .init(tag: $0.key, value: $0.value) },
                appliesSyntheticWeight: false, instanceIndex: instance.index)
            let selected = try XCTUnwrap(provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.variationExtras, extras, "\(baseWeight), \(request)")
            XCTAssertEqual(selected.variation, comparison, "\(baseWeight), \(request)")
            XCTAssertEqual(selected.descriptor.postScriptName, name, "\(baseWeight), \(request)")
            XCTAssertEqual(selected.hasExtras, extras != nil)
        }
        let external = ExternalFontProvider(source: .file(url), size: 23, weight: .bold,
            design: .default, faceIndex: 0, renderingMode: .vector())
        XCTAssertEqual(external.makeTypeface(context, dpi: 72)?.selectedFont?.variationExtras, [w: 700])
    }

    // ASSERTIONS fontVariationSelection27Observed
    func testSelectedNameAndComparisonVariationKeepIndependentPrecision() throws {
        let metadata = try XCTUnwrap(VVD.Font.metadata(path: url.path))
        let base = FontVariationSelection(metadata: metadata)
        let weight: UInt32 = 0x7767_6874
        let retained = base.applying([weight: 400.001])
        XCTAssertEqual(retained.coordinates, [400, 100])
        XCTAssertEqual(retained.postScriptName, "Roboto-Regular")
        XCTAssertEqual(retained.comparisonCoordinates(requested: [weight: 400.001]), [weight: 400.0009])
        let previous = base.applying([weight: 600.07]).applying([weight: 600.08])
        let fresh = base.applying([weight: 600.08])
        XCTAssertEqual(previous.coordinates, [600.07, 100])
        XCTAssertEqual(fresh.coordinates, [600.08, 100])
        XCTAssertEqual(previous.postScriptName, "Roboto-Regular_wght25811EB_wdth")
        XCTAssertEqual(fresh.postScriptName, "Roboto-Regular_wght258147A_wdth")
        XCTAssertEqual(previous.comparisonCoordinates(requested: [weight: 600.08]),
                       fresh.comparisonCoordinates(requested: [weight: 600.08]))
        func selected(_ variation: FontVariationSelection, request: CGFloat) -> SelectedFont {
            SelectedFont(source: .file(url, faceIndex: 0, namedInstance: nil), pointSize: 23,
                variation: variation, comparisonCoordinates: variation.comparisonCoordinates(requested: [weight: request]),
                syntheticWeight: 0)
        }
        XCTAssertFalse(selected(previous, request: 600.08).isEqual(to: selected(fresh, request: 600.08)))
        let a = base.applying([weight: 400.1])
        let b = base.applying([weight: 400.100000001])
        XCTAssertNotEqual(a.coordinates, b.coordinates)
        XCTAssertEqual(a.postScriptName, "Roboto-Regular_wght1901999_wdth")
        XCTAssertTrue(selected(a, request: 400.1).isEqual(to: selected(b, request: 400.100000001)))
        let oldNamed = base.applying([weight: 600]).applying([weight: 600.01])
        let freshNamed = base.applying([weight: 600.01])
        XCTAssertEqual(oldNamed.coordinates, [600, 100])
        XCTAssertEqual(freshNamed.coordinates, [600.01, 100])
        XCTAssertEqual(oldNamed.postScriptName, "Roboto-SemiBold")
        XCTAssertTrue(selected(oldNamed, request: 600.01).isEqual(to: selected(freshNamed, request: 600.01)))
    }

    // ASSERTIONS fontVariationSelection27Observed
    func testAxisDefaultsRemainInGeneratedNamesAndRasterBoundsStaySeparate() throws {
        let base = FontVariationSelection(metadata: try XCTUnwrap(VVD.Font.metadata(path: url.path)))
        let weight: UInt32 = 0x7767_6874, width: UInt32 = 0x7764_7468
        for (request, name, physical): (CGFloat, String, CGFloat) in [
            (0, "Roboto-Regular_wght0_wdth", 100),
            (1000, "Roboto-Regular_wght3E80000_wdth", 900)
        ] {
            let selection = base.applying([weight: request])
            XCTAssertEqual(selection.postScriptName, name)
            XCTAssertEqual(selection.coordinates[0], request)
            XCTAssertEqual(selection.rasterCoordinates[weight], physical)
        }
        XCTAssertEqual(base.applying([width: 90]).postScriptName, "Roboto-Regular_wght_wdth5A0000")
        let retained = base.applying([width: 99.9999999])
        XCTAssertEqual(retained.coordinates[1], 100)
        XCTAssertEqual(retained.comparisonCoordinates(requested: [width: 99.9999999]), [width: 99.9999])
    }

    // ASSERTIONS fontResourceIdentity27Observed fontVariationSelection27Observed fontURLDescriptorHistory27Observed
    func testProvidersRetainLogicalSelectionAcrossDPIAndMemoryLoading() throws {
        let context = SelectedFontAppContext()
        let resource = BundledFontResource(url: url)
        let defaultInstance = try XCTUnwrap(VVD.Font.metadata(path: url.path)?.defaultVariationInstanceIndex)
        let named = BundledFontProvider(resource: resource, size: 23, weight: .regular,
            renderingMode: .vector(.init()), variations: [BundledFontVariation(tag: 0x7767_6874, value: 400)],
            appliesSyntheticWeight: false, instanceIndex: defaultInstance)
        let a = try XCTUnwrap(named.makeTypeface(context, dpi: 72))
        let b = try XCTUnwrap(named.makeTypeface(context, dpi: 144))
        XCTAssertFalse(a.isEqual(to: b))
        XCTAssertTrue(try XCTUnwrap(a.selectedFont).isEqual(to: XCTUnwrap(b.selectedFont)))
        XCTAssertEqual(a.selectedFont?.pointSize, 23)
        guard case let .file(selectedURL, faceIndex, instance) = a.selectedFont?.descriptor.source else {
            return XCTFail("A bundled file loaded from cached bytes lost its file identity")
        }
        XCTAssertEqual(selectedURL, url)
        XCTAssertEqual(faceIndex, 0)
        XCTAssertEqual(instance, defaultInstance)
        let external = ExternalFontProvider(source: .file(url), size: 23, weight: .regular,
            design: .default, faceIndex: 0, renderingMode: .vector(.init()))
        let c = try XCTUnwrap(external.makeTypeface(context, dpi: 72))
        XCTAssertFalse(try XCTUnwrap(a.selectedFont).isEqual(to: XCTUnwrap(c.selectedFont)))
        let data = ExternalFontData(try Data(contentsOf: url))
        func memory(_ source: ExternalFontData, dpi: UInt32) throws -> SelectedFont {
            let provider = ExternalFontProvider(source: .data(source), size: 23, weight: .regular,
                design: .default, faceIndex: 0, renderingMode: .vector(.init()))
            return try XCTUnwrap(provider.makeTypeface(context, dpi: dpi)?.selectedFont)
        }
        XCTAssertTrue(try memory(data, dpi: 72).isEqual(to: memory(data, dpi: 144)))
        XCTAssertFalse(try memory(data, dpi: 72).isEqual(to:
            memory(ExternalFontData(Data(contentsOf: url)), dpi: 72)))
    }
}

private final class SelectedFontAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
