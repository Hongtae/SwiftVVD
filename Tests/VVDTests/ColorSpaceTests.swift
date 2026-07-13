import XCTest
@testable import VVD

final class ColorSpaceTests: XCTestCase {
    func testGenericColorStoresOnlyComponents() {
        XCTAssertEqual(MemoryLayout<Color<SRGB>>.size, MemoryLayout<Scalar>.size * 4)
        XCTAssertEqual(MemoryLayout<Color<LinearSRGB>>.size, MemoryLayout<Scalar>.size * 4)
        XCTAssertEqual(MemoryLayout<Color<DisplayP3>>.size, MemoryLayout<Scalar>.size * 4)
    }

    func testPackedGenericColorsRemainFourBytes() {
        XCTAssertEqual(MemoryLayout<Color<SRGB>.RGBA8>.size, 4)
        XCTAssertEqual(MemoryLayout<Color<LinearSRGB>.RGBA8>.size, 4)
        XCTAssertEqual(MemoryLayout<Color<DisplayP3>.ARGB8>.size, 4)

        let packed = Color<SRGB>.RGBA8(r: 51, g: 102, b: 153, a: 204)
        let color = Color<SRGB>(rgba8: packed)
        XCTAssertEqual(color.r, 0.2, accuracy: 1e-12)
        XCTAssertEqual(color.g, 0.4, accuracy: 1e-12)
        XCTAssertEqual(color.b, 0.6, accuracy: 1e-12)
        XCTAssertEqual(color.a, 0.8, accuracy: 1e-12)
        XCTAssertEqual(color.rgba8, packed)
    }

    func testRawVectorsPreserveCurrentColorSpaceComponents() {
        let sRGB = Color<SRGB>(0.25, 0.5, 0.75, 0.6)
        XCTAssertEqual(sRGB.float4.0, 0.25, accuracy: 1e-7)
        XCTAssertEqual(sRGB.float4.1, 0.5, accuracy: 1e-7)
        XCTAssertEqual(sRGB.float4.2, 0.75, accuracy: 1e-7)
        XCTAssertEqual(sRGB.float4.3, 0.6, accuracy: 1e-7)
        XCTAssertEqual(Color<SRGB>.colorSpace, SRGB.descriptor)
        XCTAssertEqual(sRGB.colorSpace, SRGB.descriptor)
    }

    func testSignedSRGBTransferRoundTripsExtendedComponents() {
        let encoded = Color<SRGB>(-0.25, 0.5, 1.25, 0.6)
        let linear = encoded.linearSRGB
        XCTAssertEqual(linear.r, -0.05087608817155679, accuracy: 1e-12)
        XCTAssertEqual(linear.g, 0.21404114048223255, accuracy: 1e-12)
        XCTAssertEqual(linear.b, 1.6659398809545145, accuracy: 1e-12)
        XCTAssertEqual(linear.a, 0.6, accuracy: 0)

        let roundTrip = linear.sRGB
        XCTAssertEqual(roundTrip.r, encoded.r, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.g, encoded.g, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.b, encoded.b, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.a, encoded.a, accuracy: 0)
    }

    func testLinearDisplayP3UsesD65PrimaryConversion() {
        let red = Color<LinearDisplayP3>(1, 0, 0, 0.75).linearSRGB
        XCTAssertEqual(red.r, 1.2249401762805598, accuracy: 1e-12)
        XCTAssertEqual(red.g, -0.04205695470968816, accuracy: 1e-12)
        XCTAssertEqual(red.b, -0.019637554590334432, accuracy: 1e-12)
        XCTAssertEqual(red.a, 0.75, accuracy: 0)

        let roundTrip = red.linearDisplayP3
        XCTAssertEqual(roundTrip.r, 1, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.g, 0, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.b, 0, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.a, 0.75, accuracy: 0)
    }

    func testAnyColorPreservesRuntimeSpaceAndConvertsToTypedColor() {
        let source = Color<DisplayP3>(0.25, 0.5, 0.75, 0.6)
        let erased = AnyColor(source)
        XCTAssertEqual(erased.colorSpace, DisplayP3.descriptor)
        XCTAssertEqual(erased.r, source.r, accuracy: 0)
        XCTAssertEqual(erased.g, source.g, accuracy: 0)
        XCTAssertEqual(erased.b, source.b, accuracy: 0)
        XCTAssertEqual(erased.a, source.a, accuracy: 0)

        let typed = erased.displayP3
        XCTAssertEqual(typed, source)
        XCTAssertEqual(erased.linearSRGB, source.linearSRGB)

        let runtime = AnyColor(
            0.25,
            0.5,
            0.75,
            0.6,
            colorSpace: DisplayP3.descriptor
        )
        XCTAssertEqual(runtime, erased)
        XCTAssertEqual(runtime.opacity(0.25).colorSpace, DisplayP3.descriptor)
        XCTAssertEqual(runtime.opacity(0.25).a, 0.25, accuracy: 0)
    }

    func testHSBInitializerProducesExpectedSectors() {
        XCTAssertEqual(Color<SRGB>(hue: 0, saturation: 1, brightness: 1), .red)
        XCTAssertEqual(Color<SRGB>(hue: 1.0 / 3.0, saturation: 1, brightness: 1), .green)
        XCTAssertEqual(Color<SRGB>(hue: 2.0 / 3.0, saturation: 1, brightness: 1), .blue)
        XCTAssertEqual(Color<SRGB>(hue: 1, saturation: 1, brightness: 1), .red)
    }
}
