import XCTest
@testable import VUI

final class ColorResolvedTests: XCTestCase {
    func testSRGBColorResolvesToLinearStorageAndPreservesSRGBAccessors() {
        let resolved = Color(
            .sRGB,
            red: 0.156863,
            green: 0.803922,
            blue: 0.254902,
            opacity: 0.35
        ).resolve(in: EnvironmentValues())

        XCTAssertEqual(resolved.linearRed, 0.021219075, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearGreen, 0.6104964, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearBlue, 0.052860666, accuracy: 0.000001)
        XCTAssertEqual(resolved.red, 0.156863, accuracy: 0.000001)
        XCTAssertEqual(resolved.green, 0.803922, accuracy: 0.000001)
        XCTAssertEqual(resolved.blue, 0.254902, accuracy: 0.000001)
        XCTAssertEqual(resolved.opacity, 0.35, accuracy: 0.000001)
    }

    func testLinearSRGBColorPreservesLinearStorageAndConvertsRenderComponents() {
        let color = Color(
            .sRGBLinear,
            red: 0.156863,
            green: 0.803922,
            blue: 0.254902,
            opacity: 0.35
        )
        let resolved = color.resolve(in: EnvironmentValues())

        XCTAssertEqual(resolved.linearRed, 0.156863, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearGreen, 0.803922, accuracy: 0.000001)
        XCTAssertEqual(resolved.linearBlue, 0.254902, accuracy: 0.000001)
        XCTAssertEqual(resolved.red, 0.4325876, accuracy: 0.000001)
        XCTAssertEqual(resolved.green, 0.9082926, accuracy: 0.000001)
        XCTAssertEqual(resolved.blue, 0.5419088, accuracy: 0.000001)
        XCTAssertEqual(resolved.opacity, 0.35, accuracy: 0.000001)

        XCTAssertEqual(color.backendColor.r, Double(resolved.red), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.g, Double(resolved.green), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.b, Double(resolved.blue), accuracy: 0.000001)
        XCTAssertEqual(color.backendColor.a, Double(resolved.opacity), accuracy: 0.000001)
    }

}
