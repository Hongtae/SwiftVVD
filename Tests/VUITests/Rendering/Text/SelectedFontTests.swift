import Foundation
import XCTest
import VVD
@testable import VUI

final class SelectedFontTests: XCTestCase {
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

    // ASSERTIONS fontResourceIdentity27Observed fontVariationSelection27Observed
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
